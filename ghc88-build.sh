#!/bin/bash
# Lay out the paths the ghc88 bootstrap script checks, run that script, then
# rewrite the installed tree so package.conf uses $topdir and the recorded
# C compiler is %{_libdir}/ghc-8.8.4/bin/host-gcc.
set -euo pipefail
ROOT=${1:?usage: ghc88-build.sh ROOT LIBDIR}
LIBDIR=${2:?}
export STAGE="$ROOT"
export GMP_PREFIX=
export HOST_GCC="$LIBDIR/ghc-8.8.4/bin/host-gcc"
export TMPDIR="$ROOT/tmp"
mkdir -p "$TMPDIR" "$ROOT/build/sources" "$ROOT/build/ref-ghc-bootstrap/common/test" \
	"$ROOT/build/ghc84-work/ghc84-prefix/bin"
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS RPM_OPT_FLAGS RPM_LD_FLAGS || true
ulimit -s unlimited 2>/dev/null || true

mkdir -p "$(dirname "$HOST_GCC")"
touch "$LIBDIR/ghc-8.8.4/.omv-bootstrap-hostgcc"

cp -a "$ROOT/incoming/ghc-8.8.4-src.tar.xz" "$ROOT/build/sources/ghc-8.8.4-src.tar.xz"
cp -a "$ROOT/incoming/regen-parsers.sh" "$ROOT/build/ref-ghc-bootstrap/common/regen-parsers.sh"
cp -a "$ROOT/incoming/cmp-regenerated.sh" "$ROOT/build/ref-ghc-bootstrap/common/cmp-regenerated.sh"
cp -a "$ROOT/incoming/T3.hs" "$ROOT/build/ref-ghc-bootstrap/common/test/T3.hs"
cp -a "$ROOT/incoming/T3.out" "$ROOT/build/ref-ghc-bootstrap/common/test/T3.out"
cp -a "$ROOT/incoming/GmpZero.hs" "$ROOT/build/ref-ghc-bootstrap/common/test/GmpZero.hs"
chmod 755 "$ROOT/build/ref-ghc-bootstrap/common/regen-parsers.sh" \
	"$ROOT/build/ref-ghc-bootstrap/common/cmp-regenerated.sh"

cat > "$ROOT/build/ghc84-work/ghc84-prefix/bin/ghc" << EOF
#!/bin/sh
exec /usr/bin/ghc84 "\$@"
EOF
cat > "$ROOT/build/ghc84-work/ghc84-prefix/bin/ghc-pkg" << EOF
#!/bin/sh
exec /usr/bin/ghc-pkg84 "\$@"
EOF
chmod 755 "$ROOT/build/ghc84-work/ghc84-prefix/bin/ghc" "$ROOT/build/ghc84-work/ghc84-prefix/bin/ghc-pkg"
mkdir -p "$ROOT/build/ghc74-tools/happy-1.19.5-prefix/bin"
ln -sfn /usr/bin/happy1195 "$ROOT/build/ghc74-tools/happy-1.19.5-prefix/bin/happy"
mkdir -p "$ROOT/build/ghc74-tools/alex-3.2.7.4-prefix/bin"
ln -sfn /usr/bin/alex327 "$ROOT/build/ghc74-tools/alex-3.2.7.4-prefix/bin/alex"

bash "$ROOT/incoming/bootstrap.sh"

python - "$ROOT" "8.8.4" "$ROOT/dest" "$HOST_GCC" "$ROOT/build/ghc88-work/ghc88-prefix" "ghc88" << 'PY'
import os, shutil, sys
root, ver, dest, host_gcc, prefix, pkg = sys.argv[1:]
lib = None
rel = None
for cand in ("lib/ghc-%s" % ver, "lib64/ghc-%s" % ver):
    if os.path.isdir(os.path.join(prefix, cand)):
        lib = os.path.join(prefix, cand)
        rel = cand
        break
if lib is None:
    sys.exit("no lib/ghc-%s under %s" % (ver, prefix))
os.makedirs(os.path.join(lib, "bin"), exist_ok=True)
shutil.copy(host_gcc, os.path.join(lib, "bin", "host-gcc"))
os.chmod(os.path.join(lib, "bin", "host-gcc"), 0o755)
work_gcc = os.path.join(root, "build", pkg + "-work", "bin", "gcc")
build_work = os.path.join(root, "build", pkg + "-work")
for dirpath, dirnames, filenames in os.walk(lib):
    for name in filenames:
        path = os.path.join(dirpath, name)
        if name == "package.cache":
            os.remove(path)
            continue
        if not (name.endswith(".conf") or name in ("package.conf", "settings") or name.endswith(".hs") or name.endswith(".sh")):
            continue
        try:
            text = open(path, encoding="utf-8", errors="surrogateescape").read()
        except IsADirectoryError:
            continue
        if lib not in text and prefix not in text and work_gcc not in text:
            continue
        # Library dirs become $topdir. The driver records host-gcc there.
        # Haddock and data-dir entries live under prefix/share; point those
        # at /usr/share. Compiling does not open them.
        text = text.replace(work_gcc, "$topdir/bin/host-gcc")
        text = text.replace(lib, "$topdir")
        text = text.replace(prefix, "/usr")
        open(path, "w", encoding="utf-8", errors="surrogateescape").write(text)
for dirpath, dirnames, filenames in os.walk(lib):
    if "package.cache" in filenames:
        os.remove(os.path.join(dirpath, "package.cache"))
bad = []
for dirpath, dirnames, filenames in os.walk(lib):
    for name in filenames:
        if not (name.endswith(".conf") or name == "package.conf" or name == "settings"):
            continue
        path = os.path.join(dirpath, name)
        text = open(path, encoding="utf-8", errors="surrogateescape").read()
        if prefix in text or build_work in text or "/media/space" in text:
            bad.append(path)
if bad:
    sys.exit("build prefix still in: %s" % " ".join(bad))
if os.path.isdir(dest):
    shutil.rmtree(dest)
os.makedirs(os.path.join(dest, os.path.dirname(rel)))
shutil.copytree(lib, os.path.join(dest, rel), symlinks=True)
print("RELOCATED", os.path.join(dest, rel))
PY
