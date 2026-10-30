# ShellOS

A personal Linux distribution built on **Debian 13 (trixie)** for one machine:
a 12th–14th gen Intel Core i5 desktop, with the desktop(s) of your choice.

* **Kernel**: Linux 6.18 LTS, Clang ThinLTO, `-march=alderlake`, BORE +
  sched_ext (LAVD), the NAP neural idle governor, and a **profile-guided
  rebuild loop (AutoFDO + Propeller) driven by how you use your machine**.
  See [docs/KERNEL.md](docs/KERNEL.md).
* **Memory**: zram with lz4 → zstd idle recompression, MGLRU thrash
  protection, and `shellos-senpai`, a pressure-driven proactive reclaimer
  modelled on Meta's TMO.
* **Boot**: Limine with a branded menu, safe mode, older kernels and bootable
  **Btrfs/Snapper snapshots**, plus one-command rollback.
* **Desktops**: pick any of COSMIC, Pantheon (elementary OS), GNOME, KDE
  Plasma, Hyprland, i3, dwm and bspwm in the installer; switch at the login
  screen. COSMIC and Pantheon are rebuilt natively for trixie, and the tiling
  WMs come ShellOS-configured with shared keys. Dark with a teal accent.
  zsh + starship, Alacritty, Firefox (Mozilla repo), Flatpak/Flathub,
  Distrobox. See [docs/DESKTOPS.md](docs/DESKTOPS.md).
* **Install**: live ISO (COSMIC) + Calamares.

Every decision and who made it: [docs/DECISIONS.md](docs/DECISIONS.md).
First-time setup: [docs/SETUP.md](docs/SETUP.md).
Try it in a VM first: [docs/VM.md](docs/VM.md) (`vm/shellos-vm live`).

## Layout

```
kernel/            6.18 LTS: version, -march, patches, config fragment, build.sh, profiles/
packages/
  shellos-tuning/        sysctl, udev, zram, MGLRU/THP, shellos-senpai (C)
  shellos-boot/          Limine ESP sync + menu, snapshot overlay, rollback, installer hook
  shellos-branding/      os-release, logo/wallpaper generator, Plymouth, COSMIC defaults
  shellos-kernel-tools/  shellos-kernel-profile (AutoFDO/Propeller collection)
  shellos-desktop/       base + shellos-de-* desktop metapackages, WM configs, shellos-desktops
  shellos-installer/     Calamares settings and branding
  limine/ scx/ autofdo/  upstream sources packaged for trixie
  cosmic/                COSMIC epoch rebuild (System76's packaging, pinned commits)
  pantheon/              Pantheon rebuild (elementary's packaging, pinned commits)
  shellos-dwm/ adw-gtk3/ dwm with the ShellOS config; libadwaita look for GTK3
iso/               mmdebstrap → squashfs → Limine hybrid ISO
vm/                QEMU/KVM runner (live, install, boot) + headless smoke test
scripts/           apt repo publishing, CI helpers
.github/workflows/ lint, kernel, packages, tools, cosmic, pantheon, publish (Pages), desktops, iso
```

## Building locally

Everything builds in a Debian trixie environment as root (or in CI):

```sh
kernel/build.sh --install-deps && kernel/build.sh     # → out/kernel/*.deb
kernel/build.sh --check                               # patches + config + compile patched code
packages/limine/build.sh                              # → out/packages/
packages/cosmic/build.sh cosmic-comp                  # one COSMIC component
iso/build.sh desktop                                  # → out/iso/*.iso
```
