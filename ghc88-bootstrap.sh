#!/bin/bash
# Package adaptation: STAGE is the build root, GMP_PREFIX is
# %{_libdir}/gmp612 when this hop still uses the private GMP, and
# The C compiler is the bare name host-gcc on PATH. Install is -j1.
# Build GHC 8.8.4 from its sources with the in-chain GHC 8.4.4.
# Registerised NCG, GHCi, SMP, static libraries, threaded RTS, host GMP.
# A GHCi-less 8.8.4 does not compile (DynFlags uses Ptr outside the GHCI ifdef).
set -euo pipefail

ROOT=${STAGE:?}
R=$ROOT/build/ref-ghc-bootstrap
WORK=$ROOT/build/ghc88-work
TREE=$WORK/src/ghc-8.8.4
PREFIX=$WORK/ghc88-prefix
BOOT=$ROOT/build/ghc84-work/ghc84-prefix
HAPPY=$ROOT/build/ghc74-tools/happy-1.19.5-prefix
ALEX=$ROOT/build/ghc74-tools/alex-3.2.7.4-prefix
SRC=$ROOT/build/sources/ghc-8.8.4-src.tar.xz
EXPECT_SHA=f0505e38b2235ff9f1090b51f44d6c8efd371068e5a6bb42a2a6d8b67b5ffc2d
JOBS=8

export TMPDIR=$WORK/tmp
mkdir -p "$TMPDIR" "$WORK/logs" "$WORK/bin" "$WORK/shipped" "$WORK/src"

exec 9>"$WORK/bootstrap.lock"
flock -n 9 || { printf 'GHC88_FAILED: another bootstrap holds %s\n' "$WORK/bootstrap.lock"; exit 1; }

phase() { printf 'GHC88_PHASE %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { printf 'GHC88_FAILED: %s\n' "$*"; exit 1; }
errline() {
	grep -E 'ERR:|error:|Error:|unrecognised|not in scope|Not in scope|Failed' "$1" 2>/dev/null | tail -4 | tr '\n' ' ' | cut -c1-400 || true
}

printf '%s\n' "$$" > "$WORK/bootstrap.pid"
ulimit -s unlimited 2>/dev/null || true
phase "start pid $$"

[ -x "$BOOT/bin/ghc" ] || fail "boot compiler missing: $BOOT/bin/ghc"
ver=$("$BOOT/bin/ghc" --numeric-version | tr -d '[:space:]')
[ "$ver" = "8.4.4" ] || fail "boot numeric-version is '$ver'"
phase "boot compiler 8.4.4"
[ -x "$HAPPY/bin/happy" ] || fail "happy missing"
[ -x "$ALEX/bin/alex" ] || fail "alex missing"
got_sha=$(sha256sum "$SRC" | awk '{print $1}')
[ "$got_sha" = "$EXPECT_SHA" ] || fail "tarball sha256 $got_sha"

cat > "$WORK/bin/gcc" <<'EOF'
#!/bin/bash
link=1
for a in "$@"; do
	case "$a" in
	-c|-E|-S|-M|-MM|-shared|--version|-dumpversion) link=0 ;;
	esac
done
args=(-fno-pie "$@")
if [ "$link" = 1 ]; then
	args+=(-no-pie)
fi
exec /usr/bin/gcc "${args[@]}"
EOF
chmod +x "$WORK/bin/gcc"
# cGCC / settings record the bare name host-gcc. mockbuild cannot
# create /usr/lib64/ghc-VER. The PATH export below finds this copy.
/bin/cp -f "$WORK/bin/gcc" "$WORK/bin/host-gcc"
chmod 755 "$WORK/bin/host-gcc"

clean=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '\.ghcup' -e '\.cabal' -e '/ghc66-work/' -e '/ghc610-work/' -e '/ghc612-work/' -e '/ghc74-work/' -e '/ghc74-tools/' -e '/ghc78-work/' -e '/ghc80-work/' -e '/ghc84-work/' -e '/ghc88-work/' | paste -sd: -)
export PATH="$BOOT/bin:$HAPPY/bin:$ALEX/bin:$WORK/bin:$clean"
export CC="host-gcc"
export CFLAGS="-std=gnu11 -w"
unset LD_LIBRARY_PATH || true
hash -r
command -v ghc | grep -q ghc84-prefix || fail "PATH ghc is $(command -v ghc)"
command -v happy | grep -q happy-1.19.5-prefix || fail "PATH happy is $(command -v happy)"
command -v alex | grep -q alex-3.2.7.4-prefix || fail "PATH alex is $(command -v alex)"
command -v gcc | grep -q '/ghc88-work/bin/gcc' || fail "PATH gcc is $(command -v gcc)"
phase "tools on PATH"

if [ ! -d "$TREE/mk" ]; then
	phase "unpack"
	tar -C "$WORK/src" -xJf "$SRC"
fi
[ -d "$TREE/mk" ] || fail "unpack did not produce $TREE"

cd "$TREE"

if [ ! -f "$WORK/regen.done" ]; then
	phase "regen parsers"
	if ! SHIPPED="$WORK/shipped" sh "$R/common/regen-parsers.sh" > "$WORK/logs/regen.log" 2>&1; then
		fail "regen-parsers: $(tail -8 "$WORK/logs/regen.log" | tr '\n' ' ' | cut -c1-500)"
	fi
	touch "$WORK/regen.done"
fi
phase "regen $(grep -c '^regen-parsers:' "$WORK/logs/regen.log" || true) lines"

if [ ! -f mk/build.mk ]; then
	phase "build.mk"
	cat > mk/build.mk <<'EOF'
GhcUnregisterised = NO
GhcWithNativeCodeGen = YES
GhcWithInterpreter = YES
GhcWithSMP = YES
GhcLibWays = v
GhcRTSWays = thr
DYNAMIC_BY_DEFAULT = NO
DYNAMIC_GHC_PROGRAMS = NO
DYNAMIC_TOO = NO
BUILD_PROF_LIBS = NO
SplitObjs = NO
SplitSections = NO
HADDOCK_DOCS = NO
HSCOLOUR_SRCS = NO
BUILD_SPHINX_HTML = NO
BUILD_SPHINX_PDF = NO
BUILD_MAN = NO
GhcStage1HcOpts = -O
GhcStage2HcOpts = -O -fasm
GhcLibHcOpts = -O -fasm
SRC_HC_OPTS = -H64m -O -optc-std=gnu11 -optc-w
SRC_CC_OPTS += -std=gnu11 -w
SRC_HSC2HS_OPTS += --cflag=-std=gnu11 --cflag=-w
EOF
fi

phase "configure"
if [ ! -f mk/config.mk ]; then
	if ! ./configure --prefix="$PREFIX" GHC="$BOOT/bin/ghc" CC="host-gcc" \
		CFLAGS="-std=gnu11 -w" > "$WORK/logs/configure.log" 2>&1
	then
		fail "configure: $(errline "$WORK/logs/configure.log") $(tail -8 "$WORK/logs/configure.log" | tr '\n' ' ' | cut -c1-500)"
	fi
fi
grep -q "GHC=$BOOT/bin/ghc" config.log || fail "config.log did not record the 8.4.4 boot compiler"
happy_mk=$(grep -E '^HAPPY[[:space:]]*=' mk/config.mk | head -1)
alex_mk=$(grep -E '^ALEX[[:space:]]*=' mk/config.mk | head -1)
phase "config $happy_mk"
phase "config $alex_mk"
printf '%s\n' "$happy_mk" | grep -q happy-1.19.5-prefix || fail "config.mk HAPPY is $happy_mk"
printf '%s\n' "$alex_mk" | grep -q alex-3.2.7.4-prefix || fail "config.mk ALEX is $alex_mk"

phase "make -j$JOBS"
if ! stdbuf -oL -eL make -j"$JOBS" > "$WORK/logs/make.log" 2>&1; then
	fail "make: $(tail -15 "$WORK/logs/make.log" | tr '\n' ' ' | cut -c1-800)"
fi
phase "make rc=0"

phase "install"
# Parallel install races on lib/ghc-8.8.4: one job installs a file into the
# directory while another is still creating lib/ghc-8.8.4/include.
if ! make -j1 install > "$WORK/logs/install.log" 2>&1; then
	fail "install: $(errline "$WORK/logs/install.log") $(tail -6 "$WORK/logs/install.log" | tr '\n' ' ' | cut -c1-500)"
fi
iver=$("$PREFIX/bin/ghc" --numeric-version | tr -d '[:space:]')
[ "$iver" = "8.8.4" ] || fail "installed numeric-version '$iver'"
iver2=$("$PREFIX/bin/ghc" --numeric-version | tr -d '[:space:]')
[ "$iver2" = "8.8.4" ] || fail "second numeric-version '$iver2'"
printf '%s\n%s\n' "$iver" "$iver2" > "$WORK/logs/ghc88-version.log"
phase "installed 8.8.4"

phase "T3"
T3=$WORK/test-t3
rm -rf "$T3"
mkdir -p "$T3"
/bin/cp -f "$R/common/test/T3.hs" "$T3/T3.hs"
(
	cd "$T3"
	"$PREFIX/bin/ghc" -v0 --make T3.hs -o t3 > "$WORK/logs/t3-compile.log" 2>&1
	./t3 > "$WORK/logs/t3.out"
) || fail "T3: $(errline "$WORK/logs/t3-compile.log") $(tail -5 "$WORK/logs/t3.out" 2>/dev/null | tr '\n' ' ')"
cmp -s "$R/common/test/T3.out" "$WORK/logs/t3.out" || fail "T3 output mismatch"
phase "T3 ok"

phase "cmp generated"
if ! SHIPPED="$WORK/shipped" sh "$R/common/cmp-regenerated.sh" > "$WORK/logs/cmp-regenerated.log" 2>&1; then
	fail "cmp-regenerated: $(tail -15 "$WORK/logs/cmp-regenerated.log" | tr '\n' ' ' | cut -c1-700)"
fi
phase "parsers compared"

printf 'GHC88_DONE installed %s numeric-version %s\n' "$PREFIX/bin/ghc" "$iver"
