#!/usr/bin/env python3
"""Headless boot test for a ShellOS ISO.

Boots the ISO under QEMU (UEFI, KVM when available) through the real Limine
menu, logs in to the live session over a serial console and checks that the
system came up the way ShellOS intends. Exit status 0 means every required
check passed.

    vm/smoke.py ISO [--timeout SECONDS] [--out DIR]

Needs qemu-system-x86_64, OVMF firmware and xorriso (to add a serial
console to a scratch copy of the ISO's boot menu; the ISO itself is untouched).
"""
import argparse
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

OVMF = [
    ("/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_VARS_4M.fd"),
    ("/usr/share/OVMF/OVMF_CODE.fd", "/usr/share/OVMF/OVMF_VARS.fd"),
    ("/usr/share/edk2/x64/OVMF_CODE.4m.fd", "/usr/share/edk2/x64/OVMF_VARS.4m.fd"),
    ("/usr/share/edk2/ovmf/OVMF_CODE.fd", "/usr/share/edk2/ovmf/OVMF_VARS.fd"),
    ("/usr/share/qemu/edk2-x86_64-code.fd", "/usr/share/qemu/edk2-i386-vars.fd"),
]
LIVE_USER, LIVE_PASSWORD = "shell", "live"  # live-config defaults
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def die(msg):
    sys.exit(f"smoke: {msg}")


def find_ovmf():
    for code, vars_ in OVMF:
        if os.path.exists(code) and os.path.exists(vars_):
            return code, vars_
    die("no OVMF/edk2 UEFI firmware found")


def serial_iso(iso, work):
    """Copy of the ISO whose first Limine entry also logs to ttyS0."""
    conf = subprocess.run(
        ["xorriso", "-osirrox", "on", "-indev", str(iso), "-extract",
         "/boot/limine/limine.conf", str(work / "limine.conf")],
        capture_output=True, text=True)
    if conf.returncode != 0:
        die(f"xorriso could not read the ISO:\n{conf.stderr}")
    # The extracted copy keeps the ISO's read-only mode; write a new file.
    text = (work / "limine.conf").read_text()
    text = re.sub(r"^timeout:.*$", "timeout: 1", text, count=1, flags=re.M)
    text = re.sub(r"^(\s*cmdline:.*)$", r"\1 console=tty0 console=ttyS0,115200",
                  text, count=1, flags=re.M)
    (work / "limine-smoke.conf").write_text(text)
    out = work / "smoke.iso"
    subprocess.run(
        # A SORRY about the hybrid MBR layout is harmless for a UEFI test boot.
        ["xorriso", "-return_with", "FAILURE", "32",
         "-indev", str(iso), "-outdev", str(out), "-boot_image", "any",
         "replay", "-map", str(work / "limine-smoke.conf"), "/boot/limine/limine.conf"],
        check=True, capture_output=True)
    return out


class Serial:
    def __init__(self, path, log):
        self.sock = socket.socket(socket.AF_UNIX)
        for _ in range(100):
            try:
                self.sock.connect(str(path))
                break
            except OSError:
                time.sleep(0.1)
        else:
            die("could not connect to the VM's serial console")
        self.sock.settimeout(0.5)
        self.buf = ""
        self.log = log

    def read(self):
        try:
            data = self.sock.recv(65536)
        except socket.timeout:
            return
        if data:
            text = data.decode(errors="replace")
            self.log.write(text)
            self.log.flush()
            self.buf += ANSI.sub("", text).replace("\r", "")

    def wait_for(self, pattern, timeout, flags=0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            m = re.search(pattern, self.buf, flags)
            if m:
                self.buf = self.buf[m.end():]
                return m
            self.read()
        return None

    def send(self, text):
        self.sock.sendall(text.encode())

    def run(self, cmd, timeout=60):
        """Run a shell command, return (rc, output)."""
        tag = f"@@{time.time_ns()}"
        self.send(f"echo {tag}B; {cmd}; echo {tag}E $?\r")
        m = self.wait_for(rf"{tag}B\n(.*?){tag}E (\d+)", timeout, re.S)
        if not m:
            return None, "(timed out)"
        return int(m.group(2)), m.group(1).strip()


PROFILES = ("desktop", "minimal", "diagnostic")
DESKTOP_PACKAGES = ("cosmic-session", "cosmic-greeter", "scx-scheds", "calamares",
                    "shellos-installer", "shellos-desktop", "firefox")


def profile_from_name(iso):
    """shellos-<profile>-DATE-amd64.iso; anything unrecognised needs --profile."""
    m = re.match(r"shellos-([a-z]+)-", iso.name)
    name = m and m.group(1)
    return {"smoketest": "diagnostic"}.get(name, name) if name in PROFILES + ("smoketest",) else None


def checks(sh, profile):
    """(name, required, passed, detail) for each check.

    What is required comes from the profile the ISO is supposed to be, never
    from whatever happens to be installed, so a desktop image missing COSMIC
    or booting the wrong kernel fails instead of skipping checks.
    """
    results = []
    release = profile != "diagnostic"

    def check(name, cmd, ok=lambda rc, out: rc == 0, required=True, timeout=60):
        rc, out = sh.run(cmd, timeout)
        passed = rc is not None and ok(rc, out)
        results.append((name, required, passed, out.splitlines()[-1] if out else ""))
        return rc, out

    check("os-release is ShellOS", ". /etc/os-release; echo $ID", lambda rc, o: o == "shellos")
    check("no failed systemd units", "systemctl --failed --no-legend --plain | awk '{print $1}' | xargs",
          lambda rc, o: o == "")
    check("ShellOS services active",
          "systemctl is-active shellos-senpai shellos-zram-recompress.timer shellos-limine-update.path | xargs",
          lambda rc, o: o == "active active active")
    check("swap is zram", "awk 'NR>1{print $1}' /proc/swaps", lambda rc, o: "/dev/zram" in o)
    check("sysctl tuning applied", "/usr/sbin/sysctl -n vm.swappiness net.ipv4.tcp_congestion_control | xargs",
          lambda rc, o: o == "180 bbr")
    check("MGLRU thrash protection", "cat /sys/kernel/mm/lru_gen/min_ttl_ms", lambda rc, o: o == "1000")
    # Every configured source must work (trust store, keys, URLs); warnings
    # are failures here so a broken source can't hide behind a partial update.
    check("apt sources all reachable", "sudo -n apt-get -qq update --error-on=any && echo ok",
          lambda rc, o: rc == 0 and o.endswith("ok"), timeout=300)

    # Kernel: production images must run the ShellOS kernel and its features.
    check("ShellOS kernel", "uname -r", lambda rc, o: "shellos" in o, required=release)
    if release:
        check("BORE scheduler", "cat /proc/sys/kernel/sched_bore")
        # recomp_algorithm lists every algorithm; the selected one is [bracketed].
        check("zram zstd recompression", "grep -a '^#1:' /sys/block/zram0/recomp_algorithm",
              lambda rc, o: "[zstd]" in o)
        check("idle governor (NAP)", "cat /sys/devices/system/cpu/cpuidle/current_governor",
              lambda rc, o: o == "nap", required=False)  # VMs often expose no cpuidle states

    if profile == "desktop":
        check("desktop packages installed",
              "dpkg-query -W -f '${Package} ${db:Status-Abbrev}\\n' " + " ".join(DESKTOP_PACKAGES)
              + " 2>&1 | awk '$2 != \"ii\"' | xargs",
              lambda rc, o: rc == 0 and o == "")
        check("sched_ext running LAVD",
              "cat /sys/kernel/sched_ext/state /sys/kernel/sched_ext/root/ops 2>/dev/null | xargs",
              lambda rc, o: o.startswith("enabled") and "lavd" in o)
        check("display manager active", "systemctl is-active display-manager")
        check("COSMIC session running", "pgrep -u shell -x cosmic-comp >/dev/null && echo yes",
              lambda rc, o: o == "yes")
        check("installer launcher present", "command -v shellos-install calamares | wc -l",
              lambda rc, o: o == "2")
        check("Firefox installed", "command -v firefox")
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("iso", type=Path)
    ap.add_argument("--timeout", type=int, default=0, help="seconds to reach login")
    ap.add_argument("--out", type=Path, default=Path("out/vm"))
    ap.add_argument("--profile", choices=PROFILES,
                    help="what the ISO must be (default: from its file name); "
                         "'diagnostic' relaxes kernel checks and is never releasable")
    args = ap.parse_args()
    if not args.iso.exists():
        die(f"{args.iso} not found")
    profile = args.profile or profile_from_name(args.iso)
    if not profile:
        die(f"can't tell the profile from {args.iso.name}; pass --profile")
    for tool in ("qemu-system-x86_64", "xorriso"):
        if not shutil.which(tool):
            die(f"missing {tool}")
    args.out.mkdir(parents=True, exist_ok=True)
    code, vars_tpl = find_ovmf()
    kvm = os.access("/dev/kvm", os.W_OK) and os.environ.get("VM_KVM") != "off"
    timeout = args.timeout or (300 if kvm else 1500)

    with tempfile.TemporaryDirectory(prefix="shellos-smoke-") as tmp:
        work = Path(tmp)
        iso = serial_iso(args.iso, work)
        shutil.copy(vars_tpl, work / "vars.fd")
        qemu = subprocess.Popen([
            "qemu-system-x86_64", "-machine", "q35",
            *(["-accel", "kvm", "-cpu", "host"] if kvm else ["-accel", "tcg", "-cpu", "max"]),
            "-smp", "4", "-m", "6G",
            "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
            "-drive", f"if=pflash,format=raw,file={work / 'vars.fd'}",
            "-cdrom", str(iso), "-boot", "d",
            "-display", "none", "-vga", "none", "-device", "virtio-vga",
            "-nic", "user,model=virtio-net-pci",
            "-chardev", f"socket,id=ser,path={work / 'serial.sock'},server=on,wait=off",
            "-serial", "chardev:ser",
            "-monitor", f"unix:{work / 'monitor.sock'},server,nowait",
        ], stdout=subprocess.DEVNULL, stderr=open(args.out / "qemu-stderr.log", "w"))
        screen = args.out / "smoke-screen.png"
        try:
            with open(args.out / "smoke-serial.log", "w") as log:
                sh = Serial(work / "serial.sock", log)
                print(f"smoke: booting {args.iso.name} as profile '{profile}' "
                      f"({'KVM' if kvm else 'emulated'}), waiting up to {timeout}s for login")
                if not sh.wait_for(r"login: ?", timeout):
                    die(f"no login prompt; see {args.out / 'smoke-serial.log'}")
                sh.send(f"{LIVE_USER}\r")
                sh.wait_for(r"Password:", 30)
                sh.send(f"{LIVE_PASSWORD}\r")
                time.sleep(5)
                # Plain bash, no prompt colours. "q" dismisses zsh's first-run
                # wizard on images without a ~/.zshrc (and is harmless otherwise).
                sh.send("q\r")
                time.sleep(2)
                sh.send("exec env PS1='$ ' TERM=dumb bash --norc --noprofile\r")
                time.sleep(2)
                sh.read()
                sh.buf = ""
                sh.run("sudo -n true")  # warm up sudo; checks run as the live user
                if profile == "desktop":
                    time.sleep(20)  # let the autologin COSMIC session settle
                results = checks(sh, profile)
        finally:
            # Evidence even when the boot or login failed part way.
            try:
                with socket.socket(socket.AF_UNIX) as mon:
                    mon.connect(str(work / "monitor.sock"))
                    mon.sendall(f"screendump {screen} -f png\n".encode())
                    time.sleep(2)
            except OSError:
                pass
            qemu.terminate()
            try:
                qemu.wait(10)
            except subprocess.TimeoutExpired:
                qemu.kill()

    width = max(len(r[0]) for r in results)
    failed = 0
    for name, required, passed, detail in results:
        status = "PASS" if passed else ("FAIL" if required else "warn")
        failed += required and not passed
        print(f"  {status}  {name:<{width}}  {detail}")
    if screen.exists():
        print(f"smoke: screenshot {screen}")
    print(f"smoke: {'OK' if not failed else f'{failed} required check(s) failed'}")
    if profile == "diagnostic":
        print("smoke: diagnostic profile -- relaxed kernel checks, NOT RELEASABLE")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
