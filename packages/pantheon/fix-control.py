#!/usr/bin/env python3
"""Adapt elementary's debian/control (Ubuntu noble) to Debian trixie.

    fix-control.py debian/control

Rewrites dependency names in every relationship field. Each alternative is
matched on its package name only, so version constraints and arch
qualifiers survive a rename.
"""
import re
import sys

# Renamed or replaced in trixie (regex on the package name -> new name).
RENAME = [
    # elementary's packaging names the next wingpanel ABI before it ships;
    # the 8.0.x library is libwingpanel-dev (pkg-config "wingpanel").
    (r"libwingpanel-\d+-dev", "libwingpanel-dev"),
    (r"libgdk-pixbuf2\.0-dev", "libgdk-pixbuf-2.0-dev"),
    (r"policykit-1", "polkitd"),
    (r"wingpanel-indicator-bluetooth", "io.elementary.panel.bluetooth"),
]
# Gone from trixie with no replacement (the dependent feature degrades).
# aptdaemon: the locale plug used it to install language packs.
DROP = {"aptdaemon"}
# Mutter: trixie has 48 (libmutter-16); the sources support it even where
# the packaging list predates it.
MUTTER = re.compile(r"libmutter-\d+-dev")

FIELDS = re.compile(
    r"^(Build-Depends(?:-Arch|-Indep)?|Depends|Pre-Depends|Recommends|Suggests"
    r"|Conflicts|Breaks|Replaces|Provides):",
)


def rename(name):
    for pattern, new in RENAME:
        if re.fullmatch(pattern, name):
            return new
    return name


def fix_relation(value):
    groups = []
    for group in value.split(","):
        alts = []
        mutter = False
        for alt in group.split("|"):
            alt = alt.strip()
            if not alt:
                continue
            name = re.match(r"[^\s(\[:<]+", alt).group(0)
            if name in DROP:
                continue
            if MUTTER.fullmatch(name):
                mutter = True
                continue
            alts.append(rename(name) + alt[len(name):])
        if mutter:
            alts.insert(0, "libmutter-16-dev")
        if alts:
            groups.append(" | ".join(dict.fromkeys(alts)))
    return ",\n ".join(groups)


def main(path):
    lines = open(path).read().split("\n")
    out, i = [], 0
    while i < len(lines):
        m = FIELDS.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        value = lines[i][len(m.group(0)):]
        i += 1
        # Continuation lines, with comment lines allowed in between (they're
        # dropped: the field is rewritten as a whole).
        while i < len(lines) and (
            (lines[i][:1] in (" ", "\t") and lines[i].strip()) or lines[i].startswith("#")
        ):
            if not lines[i].startswith("#"):
                value += " " + lines[i].strip()
            i += 1
        relation = fix_relation(value)
        # meson projects look up systemd.pc, which trixie ships in systemd-dev.
        if m.group(1) == "Build-Depends" and not re.search(r"(^|[\s,])systemd-dev\b", relation):
            relation += ",\n systemd-dev"
        out.append(f"{m.group(1)}:\n {relation}")
    open(path, "w").write("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1])
