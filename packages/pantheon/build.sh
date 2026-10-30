#!/usr/bin/env bash
# Rebuild Pantheon (elementary's own Debian packaging) against Debian trixie.
#
#   packages/pantheon/build.sh                 build every component, in stage order
#   packages/pantheon/build.sh gala wingpanel  build only these
#   packages/pantheon/build.sh --list [STAGE]  print component names (for CI)
#   LOCAL_DEBS=dir ...                          .debs from earlier stages to build against
#
# Runs as root inside a debian:trixie container.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORKDIR="${WORKDIR:-$REPO/build/pantheon}"
OUTDIR="${OUTDIR:-$REPO/out/packages}"
SUFFIX="+shellos${CI_REV:-1}"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

components() { grep -v '^\s*\(#\|$\)' "$HERE/components.txt"; }

if [[ ${1:-} == --list ]]; then
	components | awk -v s="${2:-}" 's == "" || $2 == s {print $1}'
	exit 0
fi

setup_toolchain() {
	# A previous run's local repo may point at a directory that's gone.
	rm -f /etc/apt/sources.list.d/pantheon-local.list
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		build-essential ca-certificates devscripts dpkg-dev equivs git python3
}

# Earlier stages' packages (granite, gala, wingpanel, switchboard...) as a
# local apt repo. Ours are newer than trixie's, so apt prefers them.
local_repo() {
	[[ -n ${LOCAL_DEBS:-} ]] || return 0
	local dir
	dir="$(realpath "$LOCAL_DEBS")"
	compgen -G "$dir/*.deb" >/dev/null || return 0
	(cd "$dir" && dpkg-scanpackages --multiversion . > Packages)
	echo "deb [trusted=yes] file:$dir ./" > /etc/apt/sources.list.d/pantheon-local.list
	apt-get update
	log "local repo: $(grep -c '^Package:' "$dir/Packages") packages from earlier stages"
}

# Source at the release commit, debian/ from the packaging commit.
fetch_component() { # name src deb
	local name="$1" src="$2" deb="$3" dir="$WORKDIR/$1"
	rm -rf "$dir" "$WORKDIR/$1.pkg"
	git init -q "$dir"
	git -C "$dir" fetch -q --depth 1 "https://github.com/elementary/$name.git" "$src"
	git -C "$dir" checkout -q FETCH_HEAD
	git init -q "$WORKDIR/$1.pkg"
	git -C "$WORKDIR/$1.pkg" fetch -q --depth 1 "https://github.com/elementary/$name.git" "$deb"
	git -C "$WORKDIR/$1.pkg" checkout -q FETCH_HEAD
	[[ -f $WORKDIR/$1.pkg/debian/control ]] || die "$name: no debian/ at $deb"
	rm -rf "$dir/debian"
	cp -a "$WORKDIR/$1.pkg/debian" "$dir/"
	rm -rf "$WORKDIR/$1.pkg"
}

# ShellOS adjustments beyond fix-control.py, kept as small, explicit edits.
fixups() { # name dir
	local name="$1" dir="$2" f
	case "$name" in
		granite)
			# Debian calls the library package libgranite-7-7 (epiphany-browser
			# depends on it). Same name, so ours upgrades it rather than both
			# shipping libgranite-7.so.7.
			sed -i 's/\blibgranite7\b/libgranite-7-7/' "$dir/debian/control" "$dir/debian/libgranite7.symbols"
			for f in "$dir"/debian/libgranite7.*; do
				mv "$f" "${f/libgranite7./libgranite-7-7.}"
			done
			! grep -rqw libgranite7 "$dir/debian" || die "granite: package rename no longer applies"
			;;
		default-settings)
			# Ubuntu-only pieces: an AppArmor profile for bubblewrap under
			# Ubuntu's userns restriction, and a netplan file (ShellOS uses
			# NetworkManager directly).
			rm -f "$dir/debian/links"
			sed -i '\#usr/share/apparmor/extra-profiles#d; \#etc/netplan/#d' "$dir/debian/install"
			! grep -qE 'apparmor|netplan' "$dir/debian/install" \
				|| die "default-settings: Ubuntu-only file removal no longer applies"
			# Built but deliberately not packaged (dh_missing would fail).
			printf '%s\n' etc/netplan/01-network-manager-all.yml \
				usr/share/apparmor/extra-profiles/bwrap-userns-restrict-patched \
				>> "$dir/debian/not-installed"
			;;
		wingpanel)
			# wingpanel.pc requires gee-0.8 and gtk+-3.0, but libwingpanel-dev
			# only depends on GLib's headers (Ubuntu gets the rest indirectly).
			python3 - "$dir/debian/control" <<-'EOF'
			import re, sys
			path = sys.argv[1]
			paras = open(path).read().split("\n\n")
			for i, p in enumerate(paras):
			    if re.search(r"^Package:\s*libwingpanel-dev\s*$", p, re.M):
			        paras[i] = re.sub(r"^Depends:\n", "Depends:\n libgee-0.8-dev,\n libgtk-3-dev (>= 3.10),\n", p, count=1, flags=re.M)
			        assert paras[i] != p, "libwingpanel-dev has no Depends field"
			open(path, "w").write("\n\n".join(paras))
			EOF
			;;
	esac
}

build_component() { # name src deb
	local name="$1" dir="$WORKDIR/$1" version
	log "[$name] fetching"
	fetch_component "$@"
	python3 "$HERE/fix-control.py" "$dir/debian/control"
	fixups "$name" "$dir"

	cd "$dir"
	version="$(dpkg-parsechangelog -S Version)"
	DEBFULLNAME="ShellOS CI" DEBEMAIL="161210761+sahil-mpatki@users.noreply.github.com" \
		dch -b -v "$version$SUFFIX" -D trixie --force-distribution \
		"Rebuild for ShellOS (Debian trixie)."

	log "[$name] installing build dependencies"
	mk-build-deps -i -r -t 'apt-get -y --no-install-recommends -o Debug::pkgProblemResolver=yes' debian/control

	log "[$name] building $(dpkg-parsechangelog -S Version)"
	dpkg-buildpackage -b -us -uc
	mkdir -p "$OUTDIR"
	mv ../*.deb "$OUTDIR"/
	rm -f ../*.buildinfo ../*.changes
	cd - >/dev/null
}

main() {
	mkdir -p "$WORKDIR"
	setup_toolchain
	local_repo
	local want=("$@") name src deb
	# Local builds of several stages install each stage's output first.
	while read -r name _ _ src deb <&3; do
		if (( ${#want[@]} )) && [[ ! " ${want[*]} " == *" $name "* ]]; then
			continue
		fi
		build_component "$name" "$src" "$deb"
		if (( ${#want[@]} != 1 )); then
			LOCAL_DEBS="$OUTDIR" local_repo
		fi
	done 3< <(components | sort -k2,2n)
	log "Done:"
	ls -1 "$OUTDIR"
}

main "$@"
