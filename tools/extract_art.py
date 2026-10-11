#!/usr/bin/env python3
"""Extract embedded base64 art from the Cursing Gnomes HTML build into PNGs.

Source: ~/workspace/build-staging/fix79/index.html (v0930.59)
Dest:   ~/workspace/godot-cursing-gnomes/assets/art/<category>/<key>.png
Also writes manifest.json: key -> {file, w, h, category, source}
"""
import base64, io, json, os, re, struct, sys

SRC = os.path.expanduser("~/workspace/build-staging/fix79/index.html")
DST = os.path.expanduser("~/workspace/godot-cursing-gnomes/assets/art")

CATEGORIES = {
    # container -> (start, end, category, key_format)
    "SPRITES54": (98208316, 99699342, None, "datauri"),   # per-key category
    "C58C_SPRITES": (1727187, 1785412, "animals", "datauri"),
    "C59_SPRITES": (1819284, 1883399, "fx", "datauri"),
    "LIVE62_ART": (100638619, 101392797, "ui", "datauri"),
    "F63_ART": (101497675, 106391136, "furniture", "datauri"),
    "UNDEAD_PORTRAITS": (106601030, 106663350, "portraits", "datauri"),
    "TEX_SPRITE_SRC": (17427903, 17427903 + 16377 * 1024, None, "rawb64"),
    "BOAT_SPRITE_SRC": (38718562, 38718562 + 162 * 1024, "boats", "rawb64"),
}

# SPRITES54 key -> category overrides
S54_CAT = {
    "units": re.compile(r"^(gnome|human|elf|ogre)_(worker|warrior|ranger|mage|kid|named)[0-9]*$|^(gnome|human|elf|ogre)_(worker|warrior|ranger|mage)_[mf][01]$"),
    "ui": re.compile(r"^(btn|clock|frame|panel|slot|tab|urges)$"),
    "tools": re.compile(r"^(tool_|carry_|mayor_explorer|c55_recovered_sprite$)"),
    "icons": re.compile(r"^icon_"),
}
TEX_CAT = {
    "buildings": re.compile(r"^bld_"),
    "walls": re.compile(r"^(wall_|gatehouse)"),
    "vehicles": re.compile(r"^veh_"),
    "animals": re.compile(r"^(boar|moose|lizard)$"),
    "trees": re.compile(r"^.*_tree$"),
    "units": re.compile(r"^(arty_|funky_)"),
}


def png_size(raw: bytes):
    if raw[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", raw[16:24])
        return w, h, "png"
    if raw[:2] == b"\xff\xd8":
        return 0, 0, "jpeg"
    if raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        return 0, 0, "webp"
    return 0, 0, "bin"


def main():
    with open(SRC, "rb") as f:
        data = f.read()
    print("source bytes:", len(data), flush=True)
    manifest = {}
    total = 0

    datauri_pat = re.compile(
        rb'[\"\']?([A-Za-z_0-9]+)[\"\']?\s*:\s*[\"\']data:image/(?:png|jpeg|webp);base64,([A-Za-z0-9+/=\s]+?)[\"\']')
    rawb64_pat = re.compile(
        rb'\n\s*([A-Za-z_0-9]+)\s*:\s*\'([A-Za-z0-9+/=\s]{100,}?)\'')

    def emit(key, b64, category, source):
        nonlocal total
        b64 = re.sub(rb"\s+", b"", b64)
        try:
            raw = base64.b64decode(b64)
        except Exception as e:
            print("  DECODE FAIL", key, e)
            return
        w, h, kind = png_size(raw)
        ext = {"png": "png", "jpeg": "jpg", "webp": "webp"}.get(kind, "bin")
        catdir = os.path.join(DST, category)
        os.makedirs(catdir, exist_ok=True)
        # unique filename
        fname = "%s.%s" % (key, ext)
        i = 2
        while os.path.exists(os.path.join(catdir, fname)):
            fname = "%s_%d.%s" % (key, i, ext)
            i += 1
        with open(os.path.join(catdir, fname), "wb") as f:
            f.write(raw)
        manifest[key] = {"file": "assets/art/%s/%s" % (category, fname),
                         "w": w, "h": h, "kind": kind,
                         "category": category, "source": source}
        total += 1

    def categorize(container, key):
        if container == "SPRITES54":
            for cat, pat in S54_CAT.items():
                if pat.match(key):
                    return cat
            return "units_misc"
        if container == "TEX_SPRITE_SRC":
            for cat, pat in TEX_CAT.items():
                if pat.match(key):
                    return cat
            return "misc"
        return CATEGORIES[container][2]

    for container, (s, e, _cat, fmt) in CATEGORIES.items():
        region = data[s:e]
        pat = datauri_pat if fmt == "datauri" else rawb64_pat
        n = 0
        for m in pat.finditer(region):
            key = m.group(1).decode()
            b64 = m.group(2)
            emit(key, b64, categorize(container, key), container)
            n += 1
        print("%s: %d images" % (container, n), flush=True)

    # SPRITES54.jobtags array (13 job-tag icons)
    s = 98208316
    jm = re.search(rb"jobtags\s*:\s*\[([^\]]+)\]", data[s:s + 200000])
    if jm:
        arr = jm.group(1).decode()
        parts = re.findall(r"data:image/png;base64,([A-Za-z0-9+/=\s]+)", arr)
        for i, b64 in enumerate(parts):
            emit("jobtag%d" % i, b64.encode(), "jobtags", "SPRITES54.jobtags")
        print("jobtags: %d" % len(parts), flush=True)

    # NPC_PORTRAITS webp arrays: { human: [...], ... }
    s = 85615227
    e = data.find(b"\n};", s)
    preg = data[s:e]
    for fm in re.finditer(rb"([a-z]+)\s*:\s*\[([^\]]+)\]", preg):
        faction = fm.group(1).decode()
        arr = fm.group(2).decode()
        parts = re.findall(r"([A-Za-z0-9+/=]{200,})", arr)
        for i, b64 in enumerate(parts):
            emit("portrait_%s_%d" % (faction, i), b64.encode(),
                 "portraits", "NPC_PORTRAITS")
        print("NPC_PORTRAITS.%s: %d" % (faction, len(parts)), flush=True)

    # CG_LOAD_SPLASHES jpeg array
    sm = re.search(rb"CG_LOAD_SPLASHES\s*=\s*\[([^\]]+)\]",
                   data[107576028 - 200:107576028 + 3000000])
    if sm:
        arr = sm.group(1).decode()
        parts = re.findall(r"([A-Za-z0-9+/=]{500,})", arr)
        for i, b64 in enumerate(parts):
            emit("splash_%d" % i, b64.encode(), "splash", "CG_LOAD_SPLASHES")
        print("splashes: %d" % len(parts), flush=True)

    with open(os.path.join(DST, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print("TOTAL:", total, "->", DST, flush=True)


if __name__ == "__main__":
    main()
