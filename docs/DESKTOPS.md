# Desktops

The installer asks which desktops you want (tick any number). Each one is
listed on the shared login screen (COSMIC's greeter), so you pick per
login. COSMIC comes with the ISO; the others download during installation,
so that step needs a network connection.

| ID | Desktop | Source | Session |
|---|---|---|---|
| `cosmic` | COSMIC 1.11 | System76's packaging, rebuilt for trixie (`packages/cosmic`) | Wayland |
| `pantheon` | Pantheon (elementary OS 8) | elementary's sources + packaging, rebuilt for trixie (`packages/pantheon`) | X11 |
| `gnome` | GNOME 48, core (`gnome-core`) | Debian trixie | Wayland |
| `kde` | KDE Plasma 6, core (`kde-plasma-desktop`) | Debian trixie | Wayland |
| `hyprland` | Hyprland 0.55 | Debian trixie-backports (pinned to just its stack) | Wayland |
| `i3` | i3 4.24 | Debian trixie | X11 |
| `dwm` | dwm 6.5 | suckless, built with ShellOS's `config.h` (`packages/shellos-dwm`) | X11 |
| `bspwm` | bspwm 0.9 | Debian trixie | X11 |

## Changing your mind later

```sh
shellos-desktops list                 # * marks what's installed
sudo shellos-desktops add kde i3      # install more (needs network)
sudo shellos-desktops remove gnome    # remove some (at least one stays)
```

Adding a desktop also gives existing users its config files (never
overwriting yours). GNOME and KDE install their own login screens (GDM,
SDDM); `shellos-desktops` keeps the shared one in charge.

## The tiling window managers

Hyprland, i3, dwm and bspwm come configured in the ShellOS look (deep-sea
background, teal accent, JetBrains Mono) with the same core keys:

| Keys | Action |
|---|---|
| Super+Return | terminal (Alacritty) |
| Super+D | app launcher (fuzzel on Hyprland, rofi elsewhere) |
| Super+B | Firefox |
| Super+Q | close window |
| Super+1..9 / Super+Shift+1..9 | go to / move window to workspace |
| Super+H/J/K/L, arrows | focus (dwm: J/K cycle, H/L master size) |
| Super+Shift+H/J/K/L | move window (dwm: Super+Shift+Return promotes) |
| Super+F | fullscreen (dwm: monocle layout) |
| Super+Space | toggle floating |
| Super+Escape | lock screen |
| Super+Shift+E | log out |
| Print / Shift+Print | screenshot area to clipboard / full screen to ~/Pictures |

Configs live in your home directory, so edit them freely:

| Desktop | Files |
|---|---|
| Hyprland | `~/.config/hypr/hyprland.lua` (Hyprland 0.55 uses Lua), `hypridle.conf`, `hyprlock.conf`, `~/.config/waybar/`, `~/.config/mako/config`, `~/.config/fuzzel/fuzzel.ini` |
| i3 | `~/.config/i3/config`, `~/.config/i3status/config` |
| bspwm | `~/.config/bspwm/bspwmrc`, `~/.config/sxhkd/sxhkdrc`, `~/.config/polybar/config.ini` |
| dwm | compiled in: edit `packages/shellos-dwm/files/config.h` and rebuild |
| X11 WMs | `~/.config/rofi/`, `~/.config/dunst/dunstrc`, `~/.config/picom/picom.conf` |

Pristine copies are in `/etc/skel/.config/`.

## Testing

The `desktops` workflow installs each desktop in a fresh trixie container
exactly as the installer does (`shellos-desktops set ID`) and checks that
its login session exists, the shared login screen stays in charge, existing
users get the configs, Hyprland's and i3's configs parse, and i3, dwm and
bspwm start under Xvfb with their bars, notifications and compositor.
`scripts/test-desktop.sh ID` runs the same checks locally.
