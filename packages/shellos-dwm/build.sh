#!/usr/bin/env bash
# Build shellos-dwm: suckless dwm (pinned release) with ShellOS's config.h.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=6.5
SHA256=21d79ebfa9f2fb93141836c2666cb81f4784c69d64e7f1b2352f9b970ba09729
OUTDIR="${OUTDIR:-$HERE/../../out/packages}"
WORK="${WORKDIR:-$HERE/../../build/shellos-dwm}"

rm -rf "$WORK" && mkdir -p "$WORK" "$OUTDIR"
cd "$WORK"
curl -fsSLo "shellos-dwm_$VERSION.orig.tar.gz" "https://dl.suckless.org/dwm/dwm-$VERSION.tar.gz"
echo "$SHA256  shellos-dwm_$VERSION.orig.tar.gz" | sha256sum -c -
tar xf "shellos-dwm_$VERSION.orig.tar.gz"
mv "dwm-$VERSION" "shellos-dwm-$VERSION"
cp -a "$HERE/debian" "$HERE/files" "shellos-dwm-$VERSION/"
[[ -n ${CI_REV:-} ]] && "$HERE/../../scripts/ci-version.sh" "shellos-dwm-$VERSION" "$CI_REV"
(cd "shellos-dwm-$VERSION" && dpkg-buildpackage -b -us -uc)
mv ./*.deb "$OUTDIR"/
