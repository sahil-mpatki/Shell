#!/usr/bin/env bash
# Install one ShellOS desktop the way the installer does, then check it.
#
#   scripts/test-desktop.sh ID      (as root in a fresh debian:trixie container)
#
# ID: cosmic pantheon gnome kde hyprland i3 dwm bspwm. Uses the published
# ShellOS repo ($SHELLOS_APT_URL). Checks: the package installs, its login
# session is listed with a runnable command, the shared login screen stays
# the display manager, an existing user gets the configs, configs parse,
# and the X11 window managers actually start (under Xvfb).
# `check && pass || fail` is intended: pass() always succeeds.
# shellcheck disable=SC2015
set -euo pipefail

ID="${1:?usage: test-desktop.sh ID}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLOS_APT_URL="${SHELLOS_APT_URL:-https://sahil-mpatki.github.io/Shell/apt}"
export DEBIAN_FRONTEND=noninteractive
FAILED=0

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=1; }

# --- a ShellOS-like system --------------------------------------------------------
log "Setting up apt sources"
# ShellOS uses all of Debian's components (firmware, microcode, Intel media
# driver); the debian:trixie image enables only main.
sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' \
	/etc/apt/sources.list.d/debian.sources
grep -q non-free-firmware /etc/apt/sources.list.d/debian.sources
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg
install -Dm644 "$REPO/iso/keys/packages.mozilla.org.asc" /etc/apt/keyrings/packages.mozilla.org.asc
curl -fsSL "$SHELLOS_APT_URL/shellos-archive.asc" -o /etc/apt/keyrings/shellos-archive.asc
cat > /etc/apt/sources.list.d/shellos-test.sources <<EOF
Types: deb
URIs: $SHELLOS_APT_URL
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/shellos-archive.asc

Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
EOF
printf 'Package: *\nPin: origin sahil-mpatki.github.io\nPin-Priority: 900\n' > /etc/apt/preferences.d/shellos
apt-get update

log "Installing the ShellOS base with COSMIC (the live image's set)"
apt-get install -y shellos-desktop shellos-de-cosmic
useradd -m -s /bin/bash tester

log "shellos-desktops set $ID"
if shellos-desktops set "$ID"; then pass "shellos-desktops set $ID"; else fail "shellos-desktops set $ID"; fi

# --- checks ----------------------------------------------------------------------
log "Checking $ID"
dpkg-query -W -f '${db:Status-Abbrev}' "shellos-de-$ID" | grep -q '^ii' \
	&& pass "shellos-de-$ID installed" || fail "shellos-de-$ID not installed"
if [[ $ID != cosmic ]]; then
	! dpkg-query -W -f '${db:Status-Abbrev}' shellos-de-cosmic 2>/dev/null | grep -q '^ii' \
		&& pass "COSMIC removed (not chosen)" || fail "COSMIC still installed"
fi
[[ $(readlink /etc/systemd/system/display-manager.service) == */cosmic-greeter.service ]] \
	&& pass "login screen is cosmic-greeter" || fail "display-manager.service -> $(readlink /etc/systemd/system/display-manager.service)"

case "$ID" in
	cosmic)   session=/usr/share/wayland-sessions/cosmic.desktop ;;
	pantheon) session=/usr/share/xsessions/pantheon.desktop ;;
	gnome)    session=/usr/share/wayland-sessions/gnome.desktop ;;
	kde)      session=/usr/share/wayland-sessions/plasma.desktop ;;
	hyprland) session=/usr/share/wayland-sessions/hyprland.desktop ;;
	i3)       session=/usr/share/xsessions/i3.desktop ;;
	dwm)      session=/usr/share/xsessions/dwm.desktop ;;
	bspwm)    session=/usr/share/xsessions/bspwm.desktop ;;
esac
if [[ -f $session ]]; then
	exec_cmd="$(sed -n 's/^Exec=//p' "$session" | head -1)"
	bin="${exec_cmd%% *}"
	command -v "$bin" >/dev/null && pass "session $(basename "$session"): $exec_cmd" \
		|| fail "session command '$bin' not found"
else
	fail "no login session file $session"
fi

case "$ID" in
	hyprland)
		[[ -f /home/tester/.config/hypr/hyprland.lua ]] && pass "existing user got hyprland.lua" \
			|| fail "existing user has no hyprland.lua"
		out="$(XDG_RUNTIME_DIR="$(mktemp -d)" runuser -u tester -- Hyprland --verify-config \
			-c /home/tester/.config/hypr/hyprland.lua 2>&1 || true)"
		grep -q "config ok" <<<"$out" && pass "Hyprland config verifies" \
			|| { fail "Hyprland config"; echo "$out" | tail -5; }
		;;
	i3|bspwm|dwm)
		conf=/home/tester/.config/rofi/config.rasi
		[[ -O $conf || $(stat -c %U "$conf" 2>/dev/null) == tester ]] && pass "existing user got rofi config" \
			|| fail "existing user has no rofi config"
		;;
esac
if [[ $ID == i3 ]]; then
	out="$(i3 -C -c /home/tester/.config/i3/config 2>&1)"
	[[ -z $out ]] && pass "i3 config parses" || { fail "i3 config"; echo "$out" | head -5; }
fi

# X11 window managers: start the real session as the test user under Xvfb.
case "$ID" in
	i3)    start=(i3) ;;
	bspwm) start=(bspwm) ;;
	dwm)   start=(/usr/bin/shellos-dwm-session) ;;
	*)     start=() ;;
esac
if (( ${#start[@]} )); then
	apt-get install -y --no-install-recommends xvfb xauth dbus-x11 procps
	wm="$(basename "${start[0]}")"; [[ $wm == shellos-dwm-session ]] && wm=dwm
	runuser -u tester -- env HOME=/home/tester xvfb-run -a -s "-screen 0 1280x800x24" \
		dbus-run-session -- sh -c "${start[*]} & sleep 8; pgrep -u tester -x $wm >/dev/null && echo WM_RUNNING" \
		> /tmp/wm.log 2>&1 || true
	grep -q WM_RUNNING /tmp/wm.log && pass "$wm starts and stays up (Xvfb)" \
		|| { fail "$wm did not stay up"; tail -20 /tmp/wm.log; }
fi

exit "$FAILED"
