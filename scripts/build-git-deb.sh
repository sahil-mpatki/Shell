#!/usr/bin/env bash
# Build a .deb from an upstream git commit plus a debian/ dir kept in this repo.
#   scripts/build-git-deb.sh <pkgdir>
# <pkgdir>/upstream holds: URL=, COMMIT=, SUBMODULES=(yes|no)
set -euo pipefail
PKGDIR="$(cd "$1" && pwd)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="$(basename "$PKGDIR")"
WORK="${WORKDIR:-$REPO/build/$NAME}"
OUTDIR="${OUTDIR:-$REPO/out/packages}"
# shellcheck source=/dev/null
. "$PKGDIR/upstream"

rm -rf "$WORK" && mkdir -p "$WORK/src" "$OUTDIR"
git -C "$WORK/src" init -q
git -C "$WORK/src" fetch -q --depth 1 "$URL" "$COMMIT"
git -C "$WORK/src" checkout -q FETCH_HEAD
if [[ ${SUBMODULES:-no} == yes ]]; then
	git -C "$WORK/src" submodule update -q --init --depth 1 --recursive
fi
cp -a "$PKGDIR/debian" "$WORK/src/"
[[ -n ${CI_REV:-} ]] && "$REPO/scripts/ci-version.sh" "$WORK/src" "$CI_REV"
cd "$WORK/src"
if command -v mk-build-deps >/dev/null && [[ $EUID -eq 0 ]]; then
	mk-build-deps -i -r -t 'apt-get -y --no-install-recommends' debian/control
fi
dpkg-buildpackage -b -us -uc
mv ../*.deb "$OUTDIR"/
