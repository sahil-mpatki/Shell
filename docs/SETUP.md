# Bringing ShellOS up

One-time setup on GitHub, then the build runs itself.

## 1. Make the repo public

**Settings → General → Danger Zone → Change visibility → Public.**
GitHub Pages (the apt repo) is free only for public repos.

## 2. Turn on Pages from Actions

**Settings → Pages → Build and deployment → Source: GitHub Actions.**

## 3. Create the apt signing key (on your own machine)

```sh
gpg --quick-gen-key "ShellOS Archive <161210761+sahil-mpatki@users.noreply.github.com>" ed25519 sign never
gpg --armor --export-secret-keys "ShellOS Archive" > shellos-archive.key
```

Leave the passphrase empty (CI signs non-interactively), or remove it later
with `gpg --passwd`. Then add it as a secret:

**Settings → Secrets and variables → Actions → New repository secret**
* Name: `SHELLOS_APT_SIGNING_KEY`
* Value: the full contents of `shellos-archive.key`

Delete the exported file afterwards. The public half is published
automatically at `https://sahil-mpatki.github.io/Shell/apt/shellos-archive.asc`.

## 4. Run the builds

**Actions** tab, then *Run workflow* on each of:

| Workflow | What | Rough time on a free runner |
|---|---|---|
| `packages` | shellos-* packages + Limine | ~5 min |
| `tools` | sched_ext schedulers, AutoFDO tools | 20 min / ~2 h |
| `cosmic` | 27 COSMIC components in parallel | ~1 h |
| `kernel` | the ShellOS kernel | ~4–5 h |

Each one triggers `publish`, which rebuilds the apt repo. When all four have
published, run **`iso`** (it also runs weekly). The ISO appears under
**Releases**.

## 5. Install

Try it in a VM first: [VM.md](VM.md). Then write the ISO to a USB stick and boot it (disable Secure Boot in firmware):

```sh
sudo dd if=shellos-desktop-YYYYMMDD-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

The live session logs in automatically. Run **Install ShellOS** from the
desktop. The installer erases the chosen disk and lays it out as GPT with a
1 GiB ESP and Btrfs subvolumes, then installs Limine.

## 6. Make the kernel yours (personal PGO)

After a few days of normal use:

```sh
git clone https://github.com/sahil-mpatki/Shell ~/src/Shell
shellos-kernel-profile -r ~/src/Shell      # samples ~10 min, then commits
git -C ~/src/Shell push
```

CI builds `…-shellos-afdo`. `sudo apt upgrade` and reboot. Run the same
command again for the Propeller stage (`…-shellos-afdo-prop`). See
[KERNEL.md](KERNEL.md#1-personal-profile-guided-optimisation-autofdo--propeller).

## Everyday operations

| Task | Command |
|---|---|
| Update everything | `sudo apt update && sudo apt full-upgrade` |
| Take a snapshot | `sudo snapper create -d "before X"` (apt also snapshots automatically) |
| Boot an old snapshot | pick it under **Snapshots** in the Limine menu |
| Keep that snapshot | `sudo shellos-rollback N`, then reboot |
| Kernel command line | edit `/etc/default/shellos-boot`, then `sudo shellos-limine-update` |
| Switch CPU scheduler | edit `/etc/default/shellos-scx`, then `sudo systemctl restart shellos-scx` |
| BORE only (no sched_ext) | `sudo systemctl disable --now shellos-scx` |
| Idle governor live | `echo teo \| sudo tee /sys/devices/system/cpu/cpuidle/current_governor` |
