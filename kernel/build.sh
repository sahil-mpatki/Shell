#!/usr/bin/env bash
# Build the ShellOS kernel as Debian packages.
#
#   kernel/build.sh                 full build -> out/kernel/*.deb
#   kernel/build.sh --config-only   fetch, patch, configure and verify only
#   kernel/build.sh --check         --config-only, then compile the patched
#                                   subsystems (kernel/sched, drivers/cpuidle)
#   kernel/build.sh --install-deps  apt-get the build dependencies (Debian/Ubuntu)
#
# Environment:
#   LLVM_SUFFIX   clang/lld version suffix (default: -19, Debian trixie)
#   SHELL_REV     Debian revision for the packages (default: 1)
#   JOBS          parallel jobs (default: nproc)
#   WORKDIR       scratch dir for sources (default: <repo>/build/kernel)
#   OUTDIR        where .debs land (default: <repo>/out/kernel)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
VERSION="$(cat "$HERE/VERSION")"
MARCH="$(cat "$HERE/MARCH")"
LLVM_SUFFIX="${LLVM_SUFFIX--19}"
SHELL_REV="${SHELL_REV:-1}"
JOBS="${JOBS:-$(nproc)}"
WORKDIR="${WORKDIR:-$REPO/build/kernel}"
OUTDIR="${OUTDIR:-$REPO/out/kernel}"
MODE="${1:-build}"

SRC="$WORKDIR/linux-$VERSION"
TARBALL="linux-$VERSION.tar.xz"
MAJOR="${VERSION%%.*}"
CDN="https://cdn.kernel.org/pub/linux/kernel/v$MAJOR.x"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

BUILD_DEPS=(
	bc bison build-essential cpio curl debhelper dpkg-dev dwarves flex kmod
	libdw-dev libelf-dev libssl-dev python3 rsync xz-utils zstd
	"clang$LLVM_SUFFIX" "lld$LLVM_SUFFIX" "llvm$LLVM_SUFFIX"
)

install_deps() {
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${BUILD_DEPS[@]}"
}

make_k() {
	make -C "$SRC" LLVM="$LLVM_SUFFIX" -j"$JOBS" \
		KCFLAGS="-march=$MARCH -mtune=$MARCH" "$@"
}

fetch() {
	mkdir -p "$WORKDIR"
	cd "$WORKDIR"
	if [[ ! -f $TARBALL ]]; then
		log "Downloading $TARBALL"
		curl -fsSLo "$TARBALL.part" "$CDN/$TARBALL"
		mv "$TARBALL.part" "$TARBALL"
	fi
	log "Verifying checksum against kernel.org sha256sums.asc"
	curl -fsSL "$CDN/sha256sums.asc" | grep " $TARBALL\$" | sha256sum -c - \
		|| die "checksum mismatch for $TARBALL"
}

extract_and_patch() {
	cd "$WORKDIR"
	rm -rf "$SRC"
	log "Extracting"
	tar xf "$TARBALL"
	local p
	grep -v '^\s*\(#\|$\)' "$HERE/patches/series" | while read -r p; do
		log "Applying $p"
		patch -d "$SRC" -p1 --forward --fuzz=0 --quiet < "$HERE/patches/$p" \
			|| die "$p does not apply to $VERSION"
	done
}

configure() {
	log "Configuring: Debian base + shellos.config"
	cp "$HERE/config/debian-6.18.15-amd64.config" "$SRC/.config"
	(cd "$SRC" && KCONFIG_CONFIG=.config \
		scripts/kconfig/merge_config.sh -m .config "$HERE/config/shellos.config" >/dev/null)
	make_k olddefconfig >/dev/null
	verify_config
}

# Kconfig silently drops options whose dependencies aren't met; catch that.
verify_config() {
	local line sym want have bad=0
	while IFS= read -r line; do
		if [[ $line =~ ^(CONFIG_[A-Za-z0-9_]+)=(.*)$ ]]; then
			sym="${BASH_REMATCH[1]}" want="${BASH_REMATCH[2]}"
			have="$(grep -m1 "^$sym=" "$SRC/.config" | cut -d= -f2- || true)"
		elif [[ $line =~ ^#\ (CONFIG_[A-Za-z0-9_]+)\ is\ not\ set$ ]]; then
			sym="${BASH_REMATCH[1]}" want=""
			have="$(grep -m1 "^$sym=" "$SRC/.config" | cut -d= -f2- || true)"
		else
			continue
		fi
		if [[ $have != "$want" ]]; then
			printf '    %s: wanted "%s", got "%s"\n' "$sym" "${want:-unset}" "${have:-unset}" >&2
			bad=1
		fi
	done < "$HERE/config/shellos.config"
	(( bad == 0 )) || die "config fragment not honoured (see above)"
	log "Config verified ($(grep -c '^CONFIG_\|^# CONFIG_' "$HERE/config/shellos.config") pinned options)"
}

# Pick up personal profiles committed by shell-kernel-profile. The suffix
# goes into the release string so `uname -r` says what the kernel was
# optimised with, and the profiler knows which stage to collect next.
profile_args() {
	PROFILE_ARGS=()
	PROFILE_SUFFIX=""
	local afdo="$HERE/profiles/kernel.afdo"
	local prop="$HERE/profiles/propeller"
	if [[ -f $afdo ]]; then
		PROFILE_ARGS+=("CLANG_AUTOFDO_PROFILE=$afdo")
		PROFILE_SUFFIX="-afdo"
		if [[ -f ${prop}_cc_profile.txt && -f ${prop}_ld_profile.txt ]]; then
			PROFILE_ARGS+=("CLANG_PROPELLER_PROFILE_PREFIX=$prop")
			PROFILE_SUFFIX="-afdo-prop"
		fi
	fi
	log "Profiles: ${PROFILE_SUFFIX:-none (instrumentation-ready baseline)}"
}

build() {
	profile_args
	log "Building linux $VERSION-shellos$PROFILE_SUFFIX for -march=$MARCH with $JOBS jobs"
	make_k bindeb-pkg \
		LOCALVERSION="$PROFILE_SUFFIX" \
		KDEB_PKGVERSION="$VERSION-$SHELL_REV" \
		KDEB_SOURCENAME="linux-shellos" \
		KDEB_CHANGELOG_DIST="trixie" \
		"${PROFILE_ARGS[@]}"
	mkdir -p "$OUTDIR"
	mv "$WORKDIR"/*.deb "$OUTDIR"/
	rm -f "$WORKDIR"/*.buildinfo "$WORKDIR"/*.changes
	build_meta
	log "Packages:"
	ls -1 "$OUTDIR"
}

# linux-shellos always depends on the newest build, so `apt upgrade` moves
# to new kernels (bindeb-pkg names each image after its release).
build_meta() {
	local krel="$VERSION-shellos$PROFILE_SUFFIX" ver="$VERSION-$SHELL_REV"
	local d="$WORKDIR/meta"
	rm -rf "$d"
	mkdir -p "$d/DEBIAN"
	cat > "$d/DEBIAN/control" <<-EOF
	Package: linux-shellos
	Version: $ver
	Architecture: amd64
	Section: kernel
	Priority: optional
	Maintainer: Sahil Patki <161210761+sahil-mpatki@users.noreply.github.com>
	Depends: linux-image-$krel (= $ver)
	Recommends: linux-headers-$krel (= $ver)
	Description: ShellOS kernel (tracks the newest build)
	 Currently $krel, built with -march=$MARCH.
	EOF
	dpkg-deb --root-owner-group -b "$d" "$OUTDIR/linux-shellos_${ver}_amd64.deb"
}

check() {
	log "Compile-checking patched subsystems"
	make_k prepare >/dev/null
	make_k kernel/sched/ drivers/cpuidle/
	log "kernel/sched and drivers/cpuidle compile cleanly"
}

case "$MODE" in
	--install-deps) install_deps ;;
	build)          fetch; extract_and_patch; configure; build ;;
	--config-only)  fetch; extract_and_patch; configure ;;
	--check)        fetch; extract_and_patch; configure; check ;;
	*)              die "unknown mode: $MODE" ;;
esac
