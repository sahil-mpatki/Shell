# Testing ShellOS in a VM

`vm/shellos-vm` runs ShellOS under QEMU with UEFI firmware (OVMF), so the VM
boots exactly like your PC: Limine, Plymouth, the installer, NVRAM boot
entries, Btrfs snapshots. Nothing is installed on your host.

## Host requirements

A Linux host with KVM (any modern distro):

```sh
# Debian/Ubuntu
sudo apt install qemu-system-x86 ovmf xorriso
# Fedora
sudo dnf install qemu-system-x86 edk2-ovmf xorriso
# Arch
sudo pacman -S qemu-desktop edk2-ovmf libisoburn

sudo usermod -aG kvm "$USER"    # then log out and back in
```

**CPU:** the ShellOS kernel is compiled for Alder Lake (`-march=alderlake`).
Under KVM the VM uses your real CPU, so the host should be a 12th-gen-or-newer
Intel or a recent AMD (Zen 3+). The script warns if needed instructions are
missing. `VM_KVM=off` emulates a capable CPU instead, which works anywhere
but is very slow.

## Get an ISO

Download it from the repo's **Releases** page (built by the `iso` workflow),
or build one yourself with `sudo iso/build.sh desktop`. The script picks the
newest `out/iso/*.iso` automatically, or you pass a path.

## Try it

```sh
vm/shellos-vm live  shellos-desktop-*.iso   # live session, nothing written anywhere
```

You land in COSMIC as the live user `shell` (password `live`).

## Install it, then boot the installed system

```sh
vm/shellos-vm install shellos-desktop-*.iso  # run "Install ShellOS", then power off
vm/shellos-vm boot                           # boots the VM disk through Limine
vm/shellos-vm reset                          # start over (deletes the VM disk)
```

On the installer's **Desktops** page, tick any of COSMIC, Pantheon, GNOME,
KDE Plasma, Hyprland, i3, dwm and bspwm; everything but COSMIC downloads
during the install (the VM has network through QEMU's user networking). Pick
one at the login screen. See [DESKTOPS.md](DESKTOPS.md).

The VM disk is a 40 GB sparse qcow2 on an NVMe controller (so the NVMe
I/O-scheduler rule is exercised), stored in `~/.local/share/shellos-vm/`
together with the VM's UEFI variables.

Things worth trying in the installed VM:

* `sudo snapper create -d test`, reboot, and the snapshot shows up under
  **Snapshots** in the Limine menu. Boot it, then `sudo shellos-rollback N`.
* **Safe mode** in the Limine menu (mitigations on, TEO, no sched_ext).
* `cat /sys/kernel/sched_ext/root/ops` should print `lavd`.
* `systemctl status shellos-senpai shellos-scx`, `swapon`, `zramctl`.

## Automated check

```sh
vm/shellos-vm smoke shellos-desktop-*.iso
```

This boots the ISO headless, logs in over a serial console and checks it
against its **profile** (taken from the file name, or `--profile`):
ShellOS identity, no failed units, zram swap, sysctl/MGLRU tuning, every
apt source reachable, and the ShellOS kernel with BORE and zstd
recompression. A `desktop` image must additionally have the COSMIC
packages, a running COSMIC session, LAVD active, the installer and Firefox:
missing pieces fail rather than being skipped. `--profile diagnostic`
relaxes the kernel checks for stock-kernel test images and is reported as
not releasable. It prints a
PASS/FAIL table, saves `out/vm/smoke-serial.log`, `out/vm/qemu-stderr.log`
and a screenshot `out/vm/smoke-screen.png` (also when the boot fails), and
exits non-zero on failure. The `iso` workflow
runs the same test on every ISO it builds.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `VM_RAM` | `8G` | memory |
| `VM_CPUS` | `4` | vCPUs |
| `VM_DISK_SIZE` | `40G` | disk size for new installs |
| `VM_DISPLAY` | `gtk` | `gtk`, `sdl` or `none` |
| `VM_GL` | `off` | `on` = virtio-gpu with host OpenGL (smoother COSMIC, needs working host GL) |
| `VM_KVM` | `auto` | `off` = pure emulation |
| `VM_AUDIO` | `none` | `pa` or `pipewire` for sound |
| `VM_DIR` | `~/.local/share/shellos-vm` | where the disk and UEFI vars live |

## What a VM can't tell you

* **NAP idle governor:** VMs usually expose no C-states, so it has nothing
  to choose between. Judge it on real hardware.
* **AutoFDO/Propeller profiling:** needs the real CPU's LBR, which KVM
  normally doesn't pass through. Profile on the PC.
* **Hybrid P/E-core behaviour of LAVD:** a VM's vCPUs all look identical.
