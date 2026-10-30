# ShellOS decision log

Every choice that shaped ShellOS, who made it, and why. "Owner" means a
choice made directly; "delegated" marks choices handed off to the build
work, or engineering details that follow from an owner choice.

## Foundations

| # | Decision | Choice | By |
|---|---|---|---|
| 1 | Base | **Debian** | owner |
| 2 | Release | **Trixie (13, stable)** | owner |
| 3 | Hardware | x86_64 desktop/laptop, **Intel Core i5 12th–14th gen** (Alder/Raptor Lake), Intel graphics | owner |
| 4 | Deliverable | **Live ISO + installer** | owner |
| 5 | Init | **systemd** | owner |
| 6 | Name | **ShellOS** (`ID=shellos`, `ID_LIKE=debian`) | owner |

## Kernel

| # | Decision | Choice | By |
|---|---|---|---|
| 7 | Kernel | **Custom-compiled**, latest LTS (**6.18**) | owner |
| 8 | Config base | **Debian's 6.18 config**, then ShellOS fragment | owner |
| 9 | Tweaks | 1000 Hz + full preemption, CPU-optimised build, BORE/EEVDF | owner |
| 10 | Research optimisations | delegated: *"innovate… incorporate state-of-the-art research"* | owner → delegated |
| 10a | ↳ Toolchain | Clang ThinLTO + **AutoFDO + Propeller personal PGO loop** | owner (from proposed options) |
| 10b | ↳ Scheduler | EEVDF + **BORE 7.0** + **POC selector** + **sched_ext/scx_lavd** | delegated |
| 10c | ↳ Idle | **NAP neural governor** default, TEO in safe mode | owner |
| 10d | ↳ Memory | MGLRU min_ttl, zram lz4→zstd recompression, **TMO-style shellos-senpai** | delegated |
| 10e | ↳ Net/IO | BBR + fq, per-device I/O schedulers | delegated |
| 11 | `-march` | **alderlake** (CI can't use `native`) | owner (CPU gen) |
| 12 | CPU mitigations | **`mitigations=off`** (safe mode turns them back on) | owner |
| 13 | Firmware | **non-free firmware included** | owner |
| 14 | Secure Boot | **off** | owner |

Details and citations: [KERNEL.md](KERNEL.md).

## Boot & storage

| # | Decision | Choice | By |
|---|---|---|---|
| 15 | Bootloader | **Limine** (12.9.4, built from source; not in Debian) | owner |
| 16 | Live ISO boot | also Limine (built with mmdebstrap + xorriso instead of live-build, which only supports GRUB/syslinux) | delegated, following 15 |
| 17 | Filesystem | **Btrfs + Snapper**: `@ @home @snapshots @log @cache`, zstd:1 | owner |
| 18 | Snapshot boot | Limine menu lists snapshots, booted read-only with a RAM overlay. `shellos-rollback N` makes one permanent | delegated, following 15+17 |
| 19 | Boot splash | **Plymouth** (ShellOS breathing-spiral theme) | owner |
| 20 | Swap | **zram (zstd) + systemd-oomd** (no hibernation) | owner |

## Desktop & apps

| # | Decision | Choice | By |
|---|---|---|---|
| 21 | Desktop | **COSMIC** (epoch 1.11.0) | owner |
| 22 | COSMIC source | **Rebuilt from System76's packaging as native trixie .debs** | owner |
| 23 | Installer | **Calamares** (ShellOS branding and config) | owner |
| 24 | Identity | set in installer. Live session: user `shell`, host `shellos` | owner |
| 25 | Shell | **zsh** (+ autosuggestions, syntax highlighting, starship) | owner |
| 26 | Terminal | **Alacritty** (Super+T patched to open it) | owner |
| 27 | Browser | **Firefox from Mozilla's apt repo** | owner |
| 28 | Extra apps | **Flatpak + Flathub, Distrobox + Podman** | owner |
| 29 | Look | **dark, minimal, teal `#2EC4B6`**, geometric spiral-shell logo | owner |
| 35 | More desktops | **Pantheon, GNOME, KDE, Hyprland, i3, dwm, bspwm**, chosen in the installer | owner |
| 36 | Getting them | **downloaded during install** (ISO stays COSMIC-only) | owner |
| 37 | How many | **several, picked at a shared login screen** (COSMIC's greeter) | owner |
| 38 | Tiling WMs | **ShellOS-configured**, same keys across all four | owner |
| 39 | GNOME / KDE | **core** (`gnome-core`, `kde-plasma-desktop`) | owner |
| 40 | Pantheon source | elementary OS 8 releases + elementary's packaging, rebuilt for trixie | delegated, following 35 |
| 41 | Hyprland source | Debian trixie-backports (0.55), pinned to just its own stack | delegated, following 35 |
| 42 | GTK3 theme | **adw-gtk3** packaged, so GTK3 apps match COSMIC | owner |
| 43 | Kernel headers | `linux-libc-dev` from the kernel build is **not** published | owner |

## Infrastructure

| # | Decision | Choice | By |
|---|---|---|---|
| 30 | Build & hosting | **GitHub Actions + signed apt repo on GitHub Pages** | owner |
| 31 | Repo visibility | **public** (free Pages for the apt repo) | owner |
| 32 | Kernel debug symbols | GitHub Releases (too big for Pages) | delegated, following 30 |
| 33 | VM testing | QEMU/KVM + OVMF runner and a headless smoke test (also run in CI) | owner |
| 34 | Privacy | no credentials, assistant identity or personal email in the repo; GitHub no-reply address for authorship | owner |

## Open questions (ask when they come up)

* Disk encryption (LUKS) wasn't discussed. The Plymouth theme already has a
  password prompt if you want it later.
* Rebuild COSMIC automatically on new epochs, or bump by hand?
