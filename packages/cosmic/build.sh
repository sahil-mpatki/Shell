#!/usr/bin/env bash
# Rebuild COSMIC (System76's own Debian packaging) against Debian trixie.
#
#   packages/cosmic/build.sh                 build every component
#   packages/cosmic/build.sh cosmic-comp ... build only these
#   packages/cosmic/build.sh --list          print component names (for CI)
#
# Runs as root inside a debian:trixie container. Rust comes from
# trixie-backports because COSMIC needs a newer rustc than trixie's 1.85.
set -euo pipefail
# fetch_component runs inside $(...); make failures there abort the build.
shopt -s inherit_errexit

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EPOCH="${EPOCH:-epoch-1.11.0}"
WORKDIR="${WORKDIR:-$REPO/build/cosmic}"
OUTDIR="${OUTDIR:-$REPO/out/packages}"
SUFFIX="+shellos${CI_REV:-1}"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

components() { grep -v '^\s*\(#\|$\)' "$HERE/components.txt"; }

if [[ ${1:-} == --list ]]; then
	components | awk '{print $1}'
	exit 0
fi

setup_toolchain() {
	if ! grep -rqs trixie-backports /etc/apt/sources.list.d/ /etc/apt/sources.list; then
		echo "deb http://deb.debian.org/debian trixie-backports main" \
			> /etc/apt/sources.list.d/backports.list
	fi
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		build-essential ca-certificates curl devscripts equivs git just
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		-t trixie-backports cargo rustc
	log "rustc: $(rustc --version)"
}

# Fetch cosmic-epoch once; each component is a submodule pinned by the tag.
fetch_epoch() {
	if [[ ! -d $WORKDIR/cosmic-epoch ]]; then
		git clone --depth 1 --branch "$EPOCH" \
			https://github.com/pop-os/cosmic-epoch.git "$WORKDIR/cosmic-epoch"
	fi
}

# Path of a component's source tree, fetched at its pinned commit.
fetch_component() { # name origin
	local name="$1" origin="$2" dir
	if [[ $origin == epoch ]]; then
		fetch_epoch
		git -C "$WORKDIR/cosmic-epoch" submodule update --init --depth 1 "$name" >&2
		dir="$WORKDIR/cosmic-epoch/$name"
	else
		local commit
		commit="$(awk -v n="$name" '$1 == n {print $2}' "$HERE/pins.txt")"
		[[ -n $commit ]] || die "no pin for $name in pins.txt"
		dir="$WORKDIR/$name"
		if [[ ! -d $dir ]]; then
			git init -q "$dir" >&2
			git -C "$dir" fetch -q --depth 1 "$origin" "$commit" >&2
			git -C "$dir" checkout -q FETCH_HEAD >&2
		fi
	fi
	printf '%s' "$dir"
}

# ShellOS adjustments, kept as small, explicit edits.
fixups() { # name dir
	local name="$1" dir="$2"
	case "$name" in
		cosmic-settings-daemon)
			# Super+T opens Alacritty, ShellOS's terminal.
			sed -i 's/Terminal: "cosmic-term"/Terminal: "alacritty"/' "$dir/data/system_actions.ron"
			grep -q 'Terminal: "alacritty"' "$dir/data/system_actions.ron" \
				|| die "cosmic-settings-daemon: terminal fixup no longer applies"
			;;
		pop-icon-theme)
			# Debian dropped the -full split; adwaita-icon-theme has everything.
			sed -i 's/adwaita-icon-theme-full/adwaita-icon-theme/' "$dir/debian/control"
			;;
	esac
}

build_component() { # name origin
	local name="$1" origin="$2" dir version
	log "[$name] fetching"
	dir="$(fetch_component "$name" "$origin")"
	[[ -f $dir/debian/control ]] || die "$name has no debian/ packaging"
	fixups "$name" "$dir"

	cd "$dir"
	version="$(dpkg-parsechangelog -S Version)"
	if [[ $version != *"$SUFFIX"* ]]; then
		DEBFULLNAME="ShellOS CI" DEBEMAIL="161210761+sahil-mpatki@users.noreply.github.com" \
			dch -b -v "$version$SUFFIX" -D trixie --force-distribution \
			"Rebuild for ShellOS (Debian trixie)."
	fi

	log "[$name] installing build dependencies"
	mk-build-deps -i -r -t 'apt-get -y --no-install-recommends -o Debug::pkgProblemResolver=yes' debian/control

	log "[$name] building $(dpkg-parsechangelog -S Version)"
	# System76's rules vendor Cargo crates only when `! ischroot` (their
	# sbuild pre-vendors). We always want vendoring, chroot or container.
	local shim="$WORKDIR/shim"
	mkdir -p "$shim"
	printf '#!/bin/sh\nexit 1\n' > "$shim/ischroot"
	chmod +x "$shim/ischroot"
	PATH="$shim:$PATH" dpkg-buildpackage -b -us -uc
	mkdir -p "$OUTDIR"
	mv ../*.deb "$OUTDIR"/
	rm -f ../*.buildinfo ../*.changes
	cd - >/dev/null
}

main() {
	mkdir -p "$WORKDIR"
	setup_toolchain
	local want=("$@") name origin
	# fd 3, so apt/dpkg inside the loop can't swallow the component list.
	while read -r name origin <&3; do
		if (( ${#want[@]} )) && [[ ! " ${want[*]} " == *" $name "* ]]; then
			continue
		fi
		build_component "$name" "$origin"
	done 3< <(components)
	log "Done:"
	ls -1 "$OUTDIR"
}

main "$@"
