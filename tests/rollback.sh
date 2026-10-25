#!/usr/bin/env bash
# Regression test for shellos-limine-update + shellos-rollback on a real
# btrfs filesystem (loop device) holding a minimal trixie root in @.
#
#   sudo tests/rollback.sh
#
# Checks that a rollback produces a menu booting @ with the snapshot's
# kernel, that the new @ has the snapshot's content, and that failures
# (snapshot creation, menu update) leave a bootable original @ behind.
# Environment: DEBIAN_KEYRING if the host lacks the trixie archive keys,
# LIMINE_EFI (default /usr/share/limine/BOOTX64.EFI).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
SBIN="$REPO/packages/shellos-boot/root/usr/sbin"
LIMINE_EFI="${LIMINE_EFI:-/usr/share/limine/BOOTX64.EFI}"
WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/shellos-rollback-test.XXXXXX")"
FAILS=0

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 2; }
[[ -f $LIMINE_EFI ]] || { echo "missing $LIMINE_EFI (install limine)" >&2; exit 2; }

pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }
check() { # description, command...
	local d="$1"; shift
	if "$@"; then pass "$d"; else fail "$d"; fi
}

# Everything runs in a private mount namespace, so nothing leaks to the host
# even if the test dies half way; the loop device is released on exit.
if [[ -z ${SHELLOS_TEST_NS:-} ]]; then
	trap 'rm -rf --one-file-system "${WORK:?}"' EXIT
	SHELLOS_TEST_NS=1 WORK="$WORK" unshare -m --propagation private "$0" "$@"
	exit $?
fi

IMG="$WORK/disk.img"
truncate -s 3G "$IMG"
LOOP="$(losetup --find --show "$IMG")"
trap 'umount -R "$WORK/top" "$WORK/root" 2>/dev/null; losetup -d "$LOOP"' EXIT
mkfs.btrfs -q "$LOOP"
UUID="$(blkid -s UUID -o value "$LOOP")"
mkdir -p "$WORK/top" "$WORK/root"
mount "$LOOP" "$WORK/top"
T="$WORK/top"
btrfs -q subvolume create "$T/@"
btrfs -q subvolume create "$T/@snapshots"

echo "==> bootstrapping a minimal trixie root into @"
SIGN=""
[[ -n ${DEBIAN_KEYRING:-} ]] && {
	install -m644 "$(readlink -f "$DEBIAN_KEYRING")" "$WORK/keyring.gpg"
	SIGN="[signed-by=$WORK/keyring.gpg] "
}
mmdebstrap --quiet --mode=root --variant=minbase \
	--include=btrfs-progs,util-linux,mount,findutils,diffutils \
	trixie "$T/@" "deb ${SIGN}http://deb.debian.org/debian trixie main"

install -m755 "$SBIN/shellos-limine-update" "$SBIN/shellos-rollback" "$T/@/usr/sbin/"
install -Dm644 "$LIMINE_EFI" "$T/@/usr/share/limine/BOOTX64.EFI"
printf 'SHELLOS_CMDLINE="quiet"\nSHELLOS_SAFE_CMDLINE=""\n' > "$T/@/etc/default/shellos-boot"
mkdir -p "$T/@/boot/efi" "$T/@/.snapshots"

add_kernel() { # root version
	echo "kernel $2" > "$1/boot/vmlinuz-$2"
	echo "initrd $2" > "$1/boot/initrd.img-$2"
	mkdir -p "$1/lib/modules/$2"
}
add_kernel "$T/@" 6.18.1-shellos
echo baseline > "$T/@/etc/marker"

# Snapper-layout snapshot 1 of the baseline system.
mkdir -p "$T/@snapshots/1"
btrfs -q subvolume snapshot -r "$T/@" "$T/@snapshots/1/snapshot"
cat > "$T/@snapshots/1/info.xml" <<'EOF'
<?xml version="1.0"?>
<snapshot>
  <type>single</type>
  <num>1</num>
  <date>2026-10-25 10:00:00</date>
  <description>baseline</description>
</snapshot>
EOF

# The live system moves on: new kernel, changed marker.
add_kernel "$T/@" 6.18.2-shellos
echo changed > "$T/@/etc/marker"

# Mount it the way an installed ShellOS system is mounted, then chroot.
R="$WORK/root"
mount_root() {
	mount -o subvol=@ "$LOOP" "$R"
	mount -o subvol=@snapshots "$LOOP" "$R/.snapshots"
	mount -t tmpfs -o size=64m esp "$R/boot/efi"
	mount -t proc proc "$R/proc"
	mount --rbind /dev "$R/dev"
	mount -t tmpfs run "$R/run"
	echo "BOOT_IMAGE=/vmlinuz root=UUID=$UUID rw rootflags=subvol=@" > "$WORK/cmdline"
	mount --bind "$WORK/cmdline" "$R/proc/cmdline"
}
in_root() { chroot "$R" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin "$@"; }
conf() { cat "$R/boot/efi/EFI/shellos/limine.conf"; }
first_entry() { conf | sed -n '/^\/ShellOS$/,/^$/p'; }
mount_root

echo "==> menu on the running system"
in_root shellos-limine-update >/dev/null
check "menu boots @"                   grep -q 'rootflags=subvol=@ ' <(first_entry)
check "menu boots the newest kernel"   grep -q '6.18.2-shellos/vmlinuz' <(first_entry)
check "snapshot 1 listed with its kernel" grep -q 'shellos/6.18.1-shellos/vmlinuz' <(conf | sed -n '/^\/\/#1 /,/^$/p')

echo "==> failure: snapshot creation fails (e.g. ENOSPC)"
mkdir -p "$R/usr/local/sbin"
printf '#!/bin/sh\n[ "$1 $2" = "subvolume snapshot" ] && { echo "ENOSPC" >&2; exit 1; }\nexec /usr/bin/btrfs "$@"\n' \
	> "$R/usr/local/sbin/btrfs"
chmod +x "$R/usr/local/sbin/btrfs"
if echo y | chroot "$R" env -i PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin shellos-rollback 1 >/dev/null 2>&1; then
	fail "rollback reported success despite snapshot failure"
else
	pass "rollback reports the snapshot failure"
fi
check "@ still present and unchanged"  grep -qx changed "$T/@/etc/marker"
check "no stray rollback subvolumes"   bash -c '! ls -d "$1"/@rollback-* "$1"/@.rollback-new-* 2>/dev/null' _ "$T"
rm "$R/usr/local/sbin/btrfs"

echo "==> failure: menu update fails after the swap"
printf '#!/bin/sh\necho "ESP full" >&2\nexit 1\n' > "$R/usr/local/sbin/shellos-limine-update"
chmod +x "$R/usr/local/sbin/shellos-limine-update"
if echo y | chroot "$R" env -i PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin shellos-rollback 1 >/dev/null 2>&1; then
	fail "rollback reported success despite menu failure"
else
	pass "rollback reports the menu failure"
fi
check "original @ restored"            grep -qx changed "$T/@/etc/marker"
check "no half-done @rollback-* left"  bash -c '! ls -d "$1"/@rollback-* 2>/dev/null' _ "$T"
rm "$R/usr/local/sbin/shellos-limine-update"
for s in "$T"/@.rollback-new-*; do [[ -e $s ]] && btrfs -q subvolume delete "$s"; done

echo "==> rollback to snapshot 1"
if echo y | in_root shellos-rollback 1 >"$WORK/rollback.log" 2>&1; then
	pass "rollback succeeds"
else
	fail "rollback succeeds"; cat "$WORK/rollback.log"
fi
check "new @ holds the snapshot (marker baseline)" grep -qx baseline "$T/@/etc/marker"
check "old root kept as @rollback-*"   bash -c 'grep -qx changed "$1"/@rollback-*/etc/marker' _ "$T"
check "running root is now @rollback-* (as on a live system)" \
	grep -q 'subvol=/@rollback-' <(findmnt -no OPTIONS "$R")
check "menu still boots @, not @rollback-*" grep -q 'rootflags=subvol=@ ' <(first_entry)
check "menu boots the snapshot's kernel" grep -q '6.18.1-shellos/vmlinuz' <(first_entry)
check "no menu entry targets @rollback-*" bash -c '! grep -q "subvol=@rollback" "$1"' _ "$R/boot/efi/EFI/shellos/limine.conf"

echo "==> kernel hook after rollback, before reboot"
in_root shellos-limine-update >/dev/null
check "menu unchanged by a later hook run" grep -q 'rootflags=subvol=@ ' <(first_entry)

echo
if (( FAILS )); then
	echo "rollback test: $FAILS failure(s)"; conf; exit 1
fi
echo "rollback test: OK"
