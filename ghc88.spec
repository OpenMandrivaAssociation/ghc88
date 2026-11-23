%global debug_package %{nil}
%global _find_debuginfo_opts --no-ar-files
Summary:	Glasgow Haskell Compiler 8.8.4
Name:		ghc88
Version:	8.8.4
Release:	1
License:	BSD
Group:		Development/Other
Url:		https://www.haskell.org/ghc/
# Complement of distro ghc. The binaries are ghc88 and ghc-pkg88, so no Epoch.
# Bootstrapped from the previous in-chain compiler. No upstream bindist.
ExclusiveArch:	x86_64 znver1
Source0:	ghc-8.8.4-src.tar.xz
Source1:	ghc88-build.sh
Source2:	ghc88-bootstrap.sh
Source3:	regen-parsers.sh
Source4:	cmp-regenerated.sh
Source5:	T3.hs
Source6:	T3.out
Source7:	GmpZero.hs
Source8:	%{name}.rpmlintrc

BuildRequires:	ghc84
BuildRequires:	pkgconfig(gmp)
BuildRequires:	gcc
BuildRequires:	make
BuildRequires:	patch
BuildRequires:	perl
BuildRequires:	python
BuildRequires:	diffutils
BuildRequires:	binutils
BuildRequires:	file
BuildRequires:	findutils
BuildRequires:	coreutils
BuildRequires:	util-linux
BuildRequires:	gawk
BuildRequires:	grep
BuildRequires:	sed
BuildRequires:	tar
BuildRequires:	xz
BuildRequires:	pkgconfig(ncurses)
BuildRequires:	pkgconfig(libffi)
BuildRequires:	pkgconfig(numa)
BuildRequires:	ghc74tools

%description
GHC 8.8.4 compiled from its Haskell sources by the packaged ghc84.
Happy and alex are the ones built earlier in this source-only chain.
Integer arithmetic uses the system GMP. No upstream bindist and no GHCup
compiler are used.

Installed as ghc88 so it does not replace the distribution ghc package.

%prep
set -eu
cd %{_builddir}
rm -rf ghc-root
mkdir -p ghc-root/incoming/common
cp -a %{SOURCE0} ghc-root/incoming/ghc-8.8.4-src.tar.xz
cp -a %{SOURCE1} ghc-root/incoming/ghc88-build.sh
cp -a %{SOURCE2} ghc-root/incoming/bootstrap.sh
cp -a %{SOURCE3} ghc-root/incoming/regen-parsers.sh
cp -a %{SOURCE4} ghc-root/incoming/cmp-regenerated.sh
cp -a %{SOURCE5} ghc-root/incoming/T3.hs
cp -a %{SOURCE6} ghc-root/incoming/T3.out
cp -a %{SOURCE7} ghc-root/incoming/GmpZero.hs

chmod 755 ghc-root/incoming/ghc88-build.sh ghc-root/incoming/bootstrap.sh
set +u

%build
set -eu
bash %{_builddir}/ghc-root/incoming/ghc88-build.sh "%{_builddir}/ghc-root" "%{_libdir}"
set +u

%install
set -eu
dest=%{_builddir}/ghc-root/dest
if [ -d "$dest/lib/ghc-8.8.4" ]; then
	src=$dest/lib/ghc-8.8.4
elif [ -d "$dest/lib64/ghc-8.8.4" ]; then
	src=$dest/lib64/ghc-8.8.4
else
	echo "ghc88: install tree has no lib/ghc-8.8.4" >&2
	exit 1
fi
mkdir -p %{buildroot}%{_libdir} %{buildroot}%{_bindir}
cp -a "$src" %{buildroot}%{_libdir}/ghc-8.8.4
top=%{buildroot}%{_libdir}/ghc-8.8.4
if [ -x "$top/bin/ghc" ] && file "$top/bin/ghc" | grep -q ELF; then
	rel=bin/ghc
elif [ -x "$top/ghc-8.8.4" ] && file "$top/ghc-8.8.4" | grep -q ELF; then
	rel=ghc-8.8.4
elif [ -x "$top/ghc" ] && file "$top/ghc" | grep -q ELF; then
	rel=ghc
else
	echo "ghc88: no compiler ELF in $top" >&2
	find "$top" -maxdepth 2 -type f -executable >&2 || true
	exit 1
fi
if [ -x "$top/ghc-pkg.bin" ]; then
	pkgrel=ghc-pkg.bin
elif [ -x "$top/bin/ghc-pkg" ] && file "$top/bin/ghc-pkg" | grep -q ELF; then
	pkgrel=bin/ghc-pkg
elif [ -x "$top/ghc-pkg" ] && file "$top/ghc-pkg" | grep -q ELF; then
	pkgrel=ghc-pkg
else
	echo "ghc88: no ghc-pkg ELF in $top" >&2
	exit 1
fi
if [ -f "$top/package.conf" ]; then
	db=package.conf
elif [ -d "$top/package.conf.d" ]; then
	db=package.conf.d
else
	echo "ghc88: no package database" >&2
	exit 1
fi
if "$top/$pkgrel" --help 2>&1 | grep -q -- '--global-package-db'; then
	dbflag=--global-package-db
else
	dbflag=--global-conf
fi
test -x "$top/bin/host-gcc"
libname=$(basename %{_libdir})
cat > %{buildroot}%{_bindir}/ghc88 << EOF
#!/bin/sh
if [ -x "\$0" ] && [ "\$0" != "\${0#*/}" ]; then
	arg0=\$0
else
	arg0=\$(command -v "\$0") || exit 1
fi
here=\$(CDPATH= cd -- "\$(dirname "\$arg0")" && pwd)
root=\$(dirname "\$here")
exec "\$root/$libname/ghc-8.8.4/$rel" -B"\$root/$libname/ghc-8.8.4" "\$@"
EOF
cat > %{buildroot}%{_bindir}/ghc-pkg88 << EOF
#!/bin/sh
if [ -x "\$0" ] && [ "\$0" != "\${0#*/}" ]; then
	arg0=\$0
else
	arg0=\$(command -v "\$0") || exit 1
fi
here=\$(CDPATH= cd -- "\$(dirname "\$arg0")" && pwd)
root=\$(dirname "\$here")
top="\$root/$libname/ghc-8.8.4"
exec "\$top/$pkgrel" $dbflag "\$top/$db" "\$@"
EOF
chmod 755 %{buildroot}%{_bindir}/ghc88 %{buildroot}%{_bindir}/ghc-pkg88
ln -sfn ghc88 %{buildroot}%{_bindir}/ghc-8.8.4
ln -sfn ghc-pkg88 %{buildroot}%{_bindir}/ghc-pkg-8.8.4
set +u

%files
%{_bindir}/ghc88
%{_bindir}/ghc-pkg88
%{_bindir}/ghc-8.8.4
%{_bindir}/ghc-pkg-8.8.4
%{_libdir}/ghc-8.8.4/

%check
set -eu
export PATH=%{buildroot}%{_bindir}:$PATH
hash -r
b=$(command -v ghc88)
test "$("$b" --numeric-version | tr -d '[:space:]')" = "8.8.4"
test "$("$b" --numeric-version | tr -d '[:space:]')" = "8.8.4"
rm -rf t3check
mkdir t3check
cp -a %{_builddir}/ghc-root/incoming/T3.hs t3check/T3.hs
( cd t3check && "$b" -v0 --make T3.hs -o t3 && ./t3 ) > t3.out
cmp -s %{_builddir}/ghc-root/incoming/T3.out t3.out

live=%{_libdir}/ghc-8.8.4
if [ -f "$live/.omv-bootstrap-hostgcc" ] && [ ! -e "$live/bin/ghc" ] && [ ! -e "$live/ghc" ] && [ ! -e "$live/ghc-8.8.4" ]; then
	rm -rf "$live"
fi
set +u
