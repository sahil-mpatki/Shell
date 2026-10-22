#!/usr/bin/env bash
# Build the limine .deb from the pinned upstream release tarball.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=12.9.4
SHA256=0b576463ec818d09df5dfd27d06cf3028be54bd95b12007053cc0818c041f4c3
OUTDIR="${OUTDIR:-$HERE/../../out/packages}"
WORK="${WORKDIR:-$HERE/../../build/limine}"

rm -rf "$WORK" && mkdir -p "$WORK" "$OUTDIR"
cd "$WORK"
curl -fsSLo "limine_$VERSION.orig.tar.xz" \
	"https://github.com/limine-bootloader/limine/releases/download/v$VERSION/limine-$VERSION.tar.xz"
echo "$SHA256  limine_$VERSION.orig.tar.xz" | sha256sum -c -
tar xf "limine_$VERSION.orig.tar.xz"
cp -a "$HERE/debian" "limine-$VERSION/"
[[ -n ${CI_REV:-} ]] && "$HERE/../../scripts/ci-version.sh" "limine-$VERSION" "$CI_REV"
(cd "limine-$VERSION" && dpkg-buildpackage -b -us -uc)
mv ./*.deb "$OUTDIR"/
