#!/usr/bin/env bash
# Build the adw-gtk3 .deb from the pinned upstream release tarball.
# The release ships the compiled CSS: the SCSS needs dart-sass (for @use),
# which Debian doesn't package.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=6.5
SHA256=a81780fadfc432be0fc3d89c4ebb41aa28e4f032d42c36f9789c57dd10cfa41c
OUTDIR="${OUTDIR:-$HERE/../../out/packages}"
WORK="${WORKDIR:-$HERE/../../build/adw-gtk3}"

rm -rf "$WORK" && mkdir -p "$WORK/adw-gtk3-$VERSION" "$OUTDIR"
cd "$WORK"
curl -fsSLo "adw-gtk3_$VERSION.orig.tar.xz" \
	"https://github.com/lassekongo83/adw-gtk3/releases/download/v$VERSION/adw-gtk3v$VERSION.tar.xz"
echo "$SHA256  adw-gtk3_$VERSION.orig.tar.xz" | sha256sum -c -
tar xf "adw-gtk3_$VERSION.orig.tar.xz" -C "adw-gtk3-$VERSION"
cp -a "$HERE/debian" "adw-gtk3-$VERSION/"
[[ -n ${CI_REV:-} ]] && "$HERE/../../scripts/ci-version.sh" "adw-gtk3-$VERSION" "$CI_REV"
(cd "adw-gtk3-$VERSION" && dpkg-buildpackage -b -us -uc)
mv ./*.deb "$OUTDIR"/
