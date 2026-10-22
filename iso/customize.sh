#!/usr/bin/env bash
# mmdebstrap customize hook: $1 is the root filesystem being built.
# Configures apt sources for the installed system, zsh as the default shell,
# and the live session (user "shell", COSMIC autologin).
set -euo pipefail
ROOT="$1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
in_root() { chroot "$ROOT" "$@"; }

# --- apt sources for the installed system ------------------------------------
rm -f "$ROOT/etc/apt/sources.list"
install -Dm644 "$HERE/keys/packages.mozilla.org.asc" "$ROOT/etc/apt/keyrings/packages.mozilla.org.asc"
cat > "$ROOT/etc/apt/sources.list.d/debian.sources" <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
cat > "$ROOT/etc/apt/sources.list.d/mozilla.sources" <<'EOF'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
EOF
# ShellOS's own repo (kernel, COSMIC, shellos-*), once its key is published.
if [[ -f $HERE/keys/shellos-archive.asc ]]; then
	install -Dm644 "$HERE/keys/shellos-archive.asc" "$ROOT/etc/apt/keyrings/shellos-archive.asc"
	cat > "$ROOT/etc/apt/sources.list.d/shellos.sources" <<EOF
Types: deb
URIs: ${SHELLOS_APT_URL:-https://sahil-mpatki.github.io/Shell/apt}
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/shellos-archive.asc
EOF
	# Prefer ShellOS builds over anything with the same name elsewhere.
	cat > "$ROOT/etc/apt/preferences.d/shellos" <<'EOF'
Package: *
Pin: origin sahil-mpatki.github.io
Pin-Priority: 900
EOF
fi

# --- zsh for every new user ----------------------------------------------------
sed -i 's|^#\?DSHELL=.*|DSHELL=/bin/zsh|' "$ROOT/etc/adduser.conf"
sed -i 's|^#\? *SHELL=.*|SHELL=/bin/zsh|' "$ROOT/etc/default/useradd"

echo shellos > "$ROOT/etc/hostname"

# --- live session ------------------------------------------------------------
# Everything below is removed by the installer (shellprocess_bootloader.conf).
mkdir -p "$ROOT/etc/live/config.conf.d"
cat > "$ROOT/etc/live/config.conf.d/shellos.conf" <<'EOF'
LIVE_HOSTNAME="shellos"
LIVE_USERNAME="shell"
LIVE_USER_FULLNAME="ShellOS Live"
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev powerdev scanner bluetooth sudo render"
EOF
if [[ -f $ROOT/etc/greetd/cosmic-greeter.toml ]]; then
	sed '/^\[default_session\]/i [initial_session]\ncommand = "start-cosmic"\nuser = "shell"\n' \
		"$ROOT/etc/greetd/cosmic-greeter.toml" > "$ROOT/etc/greetd/shellos-live.toml"
	mkdir -p "$ROOT/etc/systemd/system/cosmic-greeter.service.d"
	cat > "$ROOT/etc/systemd/system/cosmic-greeter.service.d/shellos-live.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=greetd --config /etc/greetd/shellos-live.toml
EOF
	# cosmic-greeter is the display manager.
	ln -sf /usr/lib/systemd/system/cosmic-greeter.service \
		"$ROOT/etc/systemd/system/display-manager.service"
fi
if [[ -f $ROOT/usr/share/applications/shellos-install.desktop ]]; then
	install -Dm644 "$ROOT/usr/share/applications/shellos-install.desktop" \
		"$ROOT/etc/skel/Desktop/shellos-install.desktop"
fi

# --- initramfs with live-boot + plymouth theme -----------------------------------
# bindeb-pkg kernels don't depend on initramfs-tools, so on a fresh bootstrap
# dpkg may configure the kernel first and no initrd gets made. Create any
# that are missing, then refresh the rest.
for k in "$ROOT"/boot/vmlinuz-*; do
	v="${k##*/vmlinuz-}"
	[[ -f $ROOT/boot/initrd.img-$v ]] || in_root update-initramfs -c -k "$v"
done
in_root update-initramfs -u -k all

# --- shrink ------------------------------------------------------------------
in_root apt-get clean
rm -rf "$ROOT"/var/lib/apt/lists/* "$ROOT"/var/log/*.log "$ROOT"/tmp/*
: > "$ROOT/etc/machine-id"
rm -f "$ROOT/var/lib/dbus/machine-id"
