#!/usr/bin/env bash
# Assemble the signed ShellOS apt repository for GitHub Pages.
#
#   scripts/publish-apt.sh NEW_DEBS_DIR SITE_DIR
#
# Packages already published at $SHELLOS_APT_URL are carried forward, so a
# workflow whose artifacts have expired doesn't drop its packages. Only the
# newest version of each package is kept (Pages sites are capped at ~1 GB);
# -dbg packages are skipped (they go to GitHub Releases instead), as are
# -dbgsym packages. linux-libc-dev is never published: the repo is pinned
# above Debian, so ours would replace trixie's userspace kernel headers.
#
# Environment:
#   SHELLOS_APT_URL  live repo to carry packages forward from (optional)
#   GPG_KEY_ID       signing key, already imported into gpg
set -euo pipefail

# Absolute paths: the script cd's into the repo to build indices, and the
# workflow passes relative ones.
NEW="$(realpath "$1")"
SITE="$(realpath -m "$2")"
APT="$SITE/apt"
POOL="$APT/pool/main"
DIST="$APT/dists/trixie"
: "${GPG_KEY_ID:?set GPG_KEY_ID to the imported signing key}"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }

mkdir -p "$POOL" "$DIST/main/binary-amd64"

# --- carry forward what is live ------------------------------------------------
if [[ -n ${SHELLOS_APT_URL:-} ]]; then
	if live="$(curl -fsSL "$SHELLOS_APT_URL/dists/trixie/main/binary-amd64/Packages.gz" | gunzip)"; then
		log "Carrying forward live packages from $SHELLOS_APT_URL"
		sed -n 's/^Filename: //p' <<<"$live" | while read -r f; do
			curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
				-o "$POOL/$(basename "$f")" "$SHELLOS_APT_URL/$f"
		done
	else
		log "No live repo yet at $SHELLOS_APT_URL"
	fi
fi

# --- add new builds ----------------------------------------------------------------
find "$NEW" -name '*.deb' ! -name '*-dbg_*' ! -name '*-dbgsym_*' -exec cp -f -t "$POOL" {} +
# Also drops a copy carried forward from before this rule existed.
rm -f "$POOL"/linux-libc-dev_*.deb

# --- keep only the newest version of each package -------------------------------
declare -A best_ver best_file
for deb in "$POOL"/*.deb; do
	key="$(dpkg-deb -f "$deb" Package):$(dpkg-deb -f "$deb" Architecture)"
	ver="$(dpkg-deb -f "$deb" Version)"
	if [[ -z ${best_ver[$key]:-} ]] || dpkg --compare-versions "$ver" gt "${best_ver[$key]}"; then
		[[ -n ${best_file[$key]:-} ]] && rm -f "${best_file[$key]}"
		best_ver[$key]="$ver"
		best_file[$key]="$deb"
	elif [[ $deb != "${best_file[$key]}" ]]; then
		rm -f "$deb"
	fi
done
log "${#best_ver[@]} packages, $(du -sh "$POOL" | cut -f1)"

# --- indices -------------------------------------------------------------------------
cd "$APT"
apt-ftparchive packages pool/main > dists/trixie/main/binary-amd64/Packages
gzip -9kf dists/trixie/main/binary-amd64/Packages
apt-ftparchive \
	-o APT::FTPArchive::Release::Origin=ShellOS \
	-o APT::FTPArchive::Release::Label=ShellOS \
	-o APT::FTPArchive::Release::Suite=trixie \
	-o APT::FTPArchive::Release::Codename=trixie \
	-o APT::FTPArchive::Release::Architectures=amd64 \
	-o APT::FTPArchive::Release::Components=main \
	-o APT::FTPArchive::Release::Description="ShellOS packages for Debian trixie" \
	release dists/trixie > dists/trixie/Release

# --- signatures -------------------------------------------------------------------
gpg --batch --yes --local-user "$GPG_KEY_ID" --clearsign -o dists/trixie/InRelease dists/trixie/Release
gpg --batch --yes --local-user "$GPG_KEY_ID" -abs -o dists/trixie/Release.gpg dists/trixie/Release
gpg --armor --export "$GPG_KEY_ID" > shellos-archive.asc

# --- website ------------------------------------------------------------------------
# The project site (web/) at the root, with the logo generated from the same
# script as the OS artwork, so the two never drift apart.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp -a "$REPO/web/." "$SITE/"
python3 "$REPO/packages/shellos-branding/art/generate.py" "$SITE/art" >/dev/null
log "Repository ready in $APT"
