"""Install the desktops picked on the "Desktops" page into the target.

Runs `shellos-desktops set <ids>` inside the target, before the user
account is created, so the new user gets the desktops' configs from
/etc/skel. Downloads need DNS inside the target, so the live session's
resolv.conf is lent to it for the duration.
"""
import os
import shutil

import libcalamares
from libcalamares.utils import check_target_env_call

KNOWN = ["cosmic", "pantheon", "gnome", "kde", "hyprland", "i3", "dwm", "bspwm"]


def pretty_name():
    return "Installing your desktops"


def selected():
    value = libcalamares.globalstorage.value("packagechooser_desktops") or ""
    if isinstance(value, (list, tuple)):
        ids = [str(v) for v in value]
    else:
        ids = str(value).split(",")
    ids = [i.strip() for i in ids if i.strip() in KNOWN]
    return ids or ["cosmic"]


def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("No target", "The target system is not mounted.")
    ids = selected()
    libcalamares.utils.debug("ShellOS desktops: " + " ".join(ids))

    resolv = os.path.join(root, "etc/resolv.conf")
    backup = resolv + ".shellos-install"
    lent = False
    if os.path.lexists(resolv):
        os.rename(resolv, backup)
    try:
        shutil.copyfile("/etc/resolv.conf", resolv)
        lent = True
    except OSError as e:
        libcalamares.utils.warning("no resolv.conf to lend the target: {}".format(e))

    try:
        check_target_env_call(["shellos-desktops", "set"] + ids)
    except Exception as e:
        return ("Could not install the desktops",
                "Installing {} failed ({}). Check the network connection "
                "and try again.".format(", ".join(ids), e))
    finally:
        if lent:
            os.remove(resolv)
        if os.path.lexists(backup):
            os.rename(backup, resolv)
    return None
