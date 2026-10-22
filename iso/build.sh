#!/usr/bin/env bash
# Build the ShellOS live/installer ISO (UEFI + BIOS, booted by Limine).
#
#   iso/build.sh [desktop|minimal]
#
# Packages come from Debian trixie, Mozilla's apt repo, and ShellOS's own
# .debs: either local build output (DEB_DIRS, default out/packages and
# out/kernel) or the published apt repo (SHELLOS_APT_URL + keys/shellos-archive.asc).
#
# Environment:
#   DEB_DIRS        space-separated dirs of local .debs to make available
#   DEBIAN_KEYRING  Debian archive keyring to use if the host's lacks trixie keys
#   MIRROR          Debian mirror (default http://deb.debian.org/debian)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
PROFILE="${1:-desktop}"
WORK="${WORKDIR:-$REPO/build/iso-$PROFILE}"
OUTDIR="${OUTDIR:-$REPO/out/iso}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
DEB_DIRS="${DEB_DIRS:-$REPO/out/packages $REPO/out/kernel}"
DATE="$(date -u +%Y%m%d)"
ISO="$OUTDIR/shellos-$PROFILE-$DATE-amd64.iso"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (mmdebstrap root mode, chroot, loop mounts)"
[[ -f $HERE/packages-$PROFILE.txt ]] || die "unknown profile: $PROFILE"
for t in mmdebstrap mksquashfs xorriso limine apt-ftparchive; do
	command -v "$t" >/dev/null || die "missing tool: $t"
done

# A failed earlier run can leave bind mounts inside the rootfs; never let
# rm reach through one into the host.
cleanup_work() {
	findmnt -rn -o TARGET | { grep "^$WORK/" || true; } | sort -r | xargs -r -n1 umount -l
	rm -rf --one-file-system "$WORK"
}
cleanup_work
mkdir -p "$WORK" "$OUTDIR"

# --- local package repo ------------------------------------------------------
MIRRORS=()
LOCAL="$WORK/localrepo"
mkdir -p "$LOCAL"
for d in $DEB_DIRS; do
	[[ -d $d ]] && find "$d" -maxdepth 1 -name '*.deb' -exec cp -t "$LOCAL" {} +
done
if compgen -G "$LOCAL/*.deb" >/dev/null; then
	(cd "$LOCAL" && apt-ftparchive packages . > Packages && gzip -9kf Packages &&
		apt-ftparchive release . > Release)
	log "Local repo: $(grep -c '^Package:' "$LOCAL/Packages") packages"
	MIRRORS+=("deb [trusted=yes] file://$LOCAL ./")
fi

COMPONENTS="main contrib non-free non-free-firmware"
# A host that isn't Debian trixie (e.g. Ubuntu) lacks the trixie archive keys.
# apt verifies as the unprivileged _apt user, so the keyring must be readable.
DSIGN=""
if [[ -n ${DEBIAN_KEYRING:-} ]]; then
	install -m644 "$(readlink -f "$DEBIAN_KEYRING")" "$WORK/debian-archive-keyring.gpg"
	DSIGN="[signed-by=$WORK/debian-archive-keyring.gpg] "
fi
MIRRORS+=(
	"deb $DSIGN$MIRROR trixie $COMPONENTS"
	"deb $DSIGN$MIRROR trixie-updates $COMPONENTS"
	"deb $DSIGN$MIRROR trixie-backports $COMPONENTS"
	"deb ${DSIGN}http://security.debian.org/debian-security trixie-security $COMPONENTS"
	"deb [signed-by=$HERE/keys/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main"
)
if [[ -n ${SHELLOS_APT_URL:-} && -f $HERE/keys/shellos-archive.asc ]]; then
	MIRRORS+=("deb [signed-by=$HERE/keys/shellos-archive.asc] $SHELLOS_APT_URL trixie main")
fi

PACKAGES="$(grep -v '^\s*\(#\|$\)' "$HERE/packages-$PROFILE.txt" | paste -sd, -)"

# --- root filesystem -----------------------------------------------------------
log "Bootstrapping trixie ($PROFILE)"
mmdebstrap --mode=root --variant=important \
	--components="$COMPONENTS" \
	--include="$PACKAGES" \
	--hook-dir=/usr/share/mmdebstrap/hooks/file-mirror-automount \
	--customize-hook="$HERE/customize.sh \"\$1\"" \
	trixie "$WORK/rootfs" "${MIRRORS[@]}"

# --- ISO tree ------------------------------------------------------------------
T="$WORK/iso_root"
mkdir -p "$T/live" "$T/boot/limine" "$T/EFI/BOOT" "$T/shellos"
KVER="$(find "$WORK/rootfs/boot" -name 'vmlinuz-*' -printf '%f\n' | sed 's/^vmlinuz-//' | sort -V | tail -1)"
[[ -n $KVER ]] || die "no kernel in the root filesystem"
log "Kernel: $KVER"
cp "$WORK/rootfs/boot/vmlinuz-$KVER" "$T/live/vmlinuz"
cp "$WORK/rootfs/boot/initrd.img-$KVER" "$T/live/initrd.img"

log "Compressing root filesystem (squashfs, zstd)"
mksquashfs "$WORK/rootfs" "$T/live/filesystem.squashfs" \
	-noappend -comp zstd -Xcompression-level 19 -b 1M -wildcards \
	-e 'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*'

cp /usr/share/limine/limine-bios.sys /usr/share/limine/limine-bios-cd.bin \
	/usr/share/limine/limine-uefi-cd.bin "$T/boot/limine/"
cp /usr/share/limine/BOOTX64.EFI "$T/EFI/BOOT/"
cp "$HERE/limine.conf" "$T/boot/limine/limine.conf"
if [[ -f $WORK/rootfs/usr/share/shellos/limine-wallpaper.png ]]; then
	cp "$WORK/rootfs/usr/share/shellos/limine-wallpaper.png" "$T/shellos/wallpaper.png"
else
	sed -i '/^wallpaper:/d' "$T/boot/limine/limine.conf"
fi

log "Writing $ISO"
xorriso -as mkisofs -R -r -J -V SHELLOS \
	-b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table \
	-hfsplus -apm-block-size 2048 \
	--efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image \
	--protective-msdos-label "$T" -o "$ISO"
limine bios-install "$ISO"
(cd "$OUTDIR" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256")
log "Done: $ISO ($(du -h "$ISO" | cut -f1))"
