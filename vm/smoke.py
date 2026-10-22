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
    text = (work / "limine.conf").read_text()
    text = re.sub(r"^timeout:.*$", "timeout: 1", text, count=1, flags=re.M)
    text = re.sub(r"^(\s*cmdline:.*)$", r"\1 console=tty0 console=ttyS0,115200",
                  text, count=1, flags=re.M)
    (work / "limine.conf").write_text(text)
    out = work / "smoke.iso"
    subprocess.run(
        # A SORRY about the hybrid MBR layout is harmless for a UEFI test boot.
        ["xorriso", "-return_with", "FAILURE", "32",
         "-indev", str(iso), "-outdev", str(out), "-boot_image", "any",
         "replay", "-map", str(work / "limine.conf"), "/boot/limine/limine.conf"],
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


def checks(sh):
    """(name, required, passed, detail) for each check."""
    results = []

    def check(name, cmd, ok=lambda rc, out: rc == 0, required=True):
        rc, out = sh.run(cmd)
        passed = rc is not None and ok(rc, out)
        results.append((name, required, passed, out.splitlines()[-1] if out else ""))
        return rc, out

    _, krel = sh.run("uname -r")
    ours = "shellos" in krel
    _, pkgs = sh.run("dpkg-query -W -f '${Package}\\n' cosmic-greeter scx-scheds calamares 2>/dev/null")
    desktop = "cosmic-greeter" in pkgs

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
    check("ShellOS kernel", "uname -r", lambda rc, o: "shellos" in o, required=False)
    if ours:
        check("BORE scheduler", "cat /proc/sys/kernel/sched_bore")
        # recomp_algorithm lists every algorithm; the selected one is [bracketed].
        check("zram zstd recompression", "grep '^#1:' /sys/block/zram0/recomp_algorithm",
              lambda rc, o: "[zstd]" in o)
        check("idle governor (NAP)", "cat /sys/devices/system/cpu/cpuidle/current_governor",
              lambda rc, o: o == "nap", required=False)  # VMs often expose no cpuidle states
    if "scx-scheds" in pkgs and ours:
        check("sched_ext running LAVD",
              "cat /sys/kernel/sched_ext/state /sys/kernel/sched_ext/root/ops 2>/dev/null | xargs",
              lambda rc, o: o.startswith("enabled") and "lavd" in o)
    if desktop:
        check("display manager active", "systemctl is-active display-manager")
        check("COSMIC session running", "pgrep -u shell -x cosmic-comp >/dev/null && echo yes",
              lambda rc, o: o == "yes")
        check("Firefox installed", "command -v firefox", required=False)
    if "calamares" in pkgs:
        check("installer present", "command -v shellos-install")
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("iso", type=Path)
    ap.add_argument("--timeout", type=int, default=0, help="seconds to reach login")
    ap.add_argument("--out", type=Path, default=Path("out/vm"))
    args = ap.parse_args()
    if not args.iso.exists():
        die(f"{args.iso} not found")
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
        ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            with open(args.out / "smoke-serial.log", "w") as log:
                sh = Serial(work / "serial.sock", log)
                print(f"smoke: booting {args.iso.name} ({'KVM' if kvm else 'emulated'}), "
                      f"waiting up to {timeout}s for login")
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
                if sh.run("dpkg -s cosmic-greeter >/dev/null 2>&1")[0] == 0:
                    time.sleep(20)  # let the autologin COSMIC session settle
                results = checks(sh)
                screen = args.out / "smoke-screen.png"
                with socket.socket(socket.AF_UNIX) as mon:
                    mon.connect(str(work / "monitor.sock"))
                    mon.sendall(f"screendump {screen} -f png\n".encode())
                    time.sleep(2)
        finally:
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
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
