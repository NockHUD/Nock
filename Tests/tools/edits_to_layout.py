#!/usr/bin/env python3
"""Tests/tools/edits_to_layout.py - the design canvas' per-page edits (edits/<page>.json) -> Config/OptionsLayoutData.lua.

Usage: python Tests/tools/edits_to_layout.py <edits dir>
The Lua file is data only; Config/OptionsLayout.lua applies it onto the built options table at load time
(header cards, row order, renames, one-liners, and the walker's side-table metadata: icon, actions, table,
form, stack, segments, advanced).
"""
import glob, json, os, sys, re

ADDON = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ADDON, "Config", "OptionsLayoutData.lua")

# canvas glyph name -> Media/Icons/<name>.tga
GLYPH = {"ruler": "ruler", "clock": "clock", "arrows-h": "expand", "square": "square", "shape-square": "square", "palette": "palette",
         "bell": "bell", "bolt": "bolt", "sparkles": "sparkle", "sparkle": "sparkle", "plus": "plus", "circle-signal": "signal",
         "expand": "expand", "list": "stack", "stack": "stack", "layers": "layers", "text": "text", "t-shirt": "shirt", "lock": "lock",
         "wrench": "wrench", "grid": "grid", "pill": "pill", "eye-off": "eyeoff", "utensils": "utensils", "envelope": "envelope",
         "triangle-warning": "warn", "play": "play", "keyboard-4": "keyboard", "shield-check": "shield", "cart-shopping": "cart", "style": "style"}
# canvas spell name -> Constants.SpellID key, or a literal id / item id
SPELL = {"ASPECT_OF_THE_HAWK": 13165, "ASPECT_OF_THE_VIPER": 34074, "SNOWBALL": {"item": 17202}}

# Rule 2 renames for pages the canvas did not regroup (applied by key, anywhere it exists).
GLOBAL_RENAME = {
    "showAutoShotBar": "Auto Shot bar", "showMeleeBar": "Melee swing timer", "showGcdBar": "GCD bar", "showManaBar": "Mana bar",
    "showRotation": "Rotation display", "rotationHelperEnabled": "Rotation helper", "showWindupMark": "Wind-up mark",
    "editGridShow": "Grid while unlocked", "showAutoShotCast": "Auto Shot in cast bar", "castBarNonCombatCasts": "Non-combat casts",
    "backgroundEnabled": "Background", "masterToggle": None, "consumeBannerEnabled": "Pill while eating or drinking",
    "playerEnabled": "Player buffs panel", "petEnabled": "Pet buffs panel", "raidOnly": "Raids only", "trackerEnabled": "Tracker section",
    "clickerEnabled": "Tank buttons", "showCompleted": "Stocked items too", "repairEnabled": "Repair reminder", "weaveBindEnabled": "Weave bind",
    "tonkDialEnabled": "Countdown dial", "practiceToast": "Toast", "practiceTimelineOkMarks": "OK marks too",
    "releaseBarEnabled": "Retry-Timer", "fluffyShowAutoShotCast": "Auto Shot wind-up as a cast", "shotBarsShowMulti": "Multi-Shot window",
    "shotBarsShowArcane": "Arcane Shot window", "shotBarsShowRaptor": "Melee weave lane", "autoShotDelayEnabled": "Auto Shot delay (experimental)",
    "activePreview": "Preview: light every tile", "forceShaman": "Panel with no shaman", "hudEnabled": "HUD",
    "rb_en_weave": "Weave stage", "shotBarsShowHelper": "Next-action helper row",
}
# The same key means different things on different pages: renamed by full path.
PATH_RENAME = {
    "hud.classic.rotation.masterToggle": "Rotation display",
    "alerts.warnings.masterToggle": "Warnings panel",
    "alerts.helpers.tabSettings.masterToggle": "Helpers panel",
}
# Inputs that are lists of names / IDs: drawn as chips with an add field.
CHIPS = ["recipients", "tankList", "zones", "customPlayer", "customPet", "custom"]
# Selects with a handful of values: drawn as a segmented button group instead of a dropdown.
SEGMENTED = ["settingsScale", "pvpMode"]


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_icon(icon):
    if not icon: return None
    if icon.get("glyph"):
        g = GLYPH.get(icon["glyph"])
        if not g: raise SystemExit("no Media glyph for canvas glyph %r" % icon["glyph"])
        return '{ glyph = %s }' % lua_str(g)
    if icon.get("spell"):
        v = SPELL.get(icon["spell"], "C." + icon["spell"])
        if isinstance(v, dict): return '{ item = %d }' % v["item"]
        if isinstance(v, int): return '{ spell = %d }' % v
        return '{ spell = %s }' % v
    return None


def lua_table_spec(tbl):
    cols = ", ".join("{ " + ", ".join(lua_str(x) for x in col) + " }" for col in tbl["cols"])
    rows = []
    for label, spec in tbl["rows"]:
        if isinstance(spec, dict):
            cells = ", ".join("[%s] = %s" % (lua_str(k), lua_str(v) if isinstance(v, str) else "{ " + ", ".join(lua_str(x) for x in v) + " }") for k, v in spec.items())
            rows.append("{ %s, { %s } }" % (lua_str(label), cells))
        else:
            rows.append("{ %s, %s }" % (lua_str(label), lua_str(spec)))
    grid = (", grid = %d" % tbl["grid"]) if tbl.get("grid") else ""
    return "{ cols = { %s }, rows = { %s }%s }" % (cols, ", ".join(rows), grid)


def slug(name):
    s = re.sub(r"[^A-Za-z0-9]+", " ", name).strip().split(" ")
    return s[0].lower() + "".join(w.capitalize() for w in s[1:]) + "Card"


def main():
    edits_dir = sys.argv[1] if len(sys.argv) > 1 else "edits"
    out = ["-- Config/OptionsLayoutData.lua", "-- GENERATED by Tests/tools/edits_to_layout.py from the design canvas' edits; do not edit by hand.",
           "-- Per tab: header cards (name, icon, desc, rows in order, actions, table/form/stack/segments, advanced), renames and one-liners.",
           'local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")', "local C = Nock.Constants.SpellID", "local L = {}", "Nock.OptionsLayoutData = L", "",
           "L.GLOBAL_RENAME = {"]
    for k, v in GLOBAL_RENAME.items():
        if v: out.append("  %s = %s," % (k, lua_str(v)))
    out += ["}", "L.PATH_RENAME = {"]
    for k, v in PATH_RENAME.items(): out.append("  [%s] = %s," % (lua_str(k), lua_str(v)))
    out += ["}", "L.CHIPS = { " + ", ".join(lua_str(k) for k in CHIPS) + " }",
            "L.SEGMENTED = { " + ", ".join(lua_str(k) for k in SEGMENTED) + " }", "", "L.TABS = {"]
    for f in sorted(glob.glob(os.path.join(edits_dir, "*.json"))):
        e = json.load(open(f, encoding="utf-8"))
        page = e["page"]
        ren, dsc = e.get("rename", {}), e.get("desc", {})
        for tab in e.get("tabs", []):
            spec = e.get("byTab", {}).get(tab)
            if not spec: continue
            path = page if tab == "__self" else page + "." + tab
            out.append("  {")
            out.append("    path = %s," % lua_str(path))
            out.append("    cards = {")
            for i, cd in enumerate(spec["cards"]):
                fields = ["key = %s" % lua_str(slug(cd["name"])), "name = %s" % lua_str(cd["name"])]
                ic = lua_icon(cd.get("icon"))
                if ic: fields.append("icon = " + ic)
                if cd.get("desc"): fields.append("desc = %s" % lua_str(cd["desc"]))
                if cd.get("advanced"): fields.append("advanced = true")
                if cd.get("form"):
                    fields.append("form = { %s }" % ", ".join(lua_str(k) for k in (cd["form"] if isinstance(cd["form"], list) else cd["rows"])))
                if cd.get("stack"): fields.append("stack = true")
                if cd.get("actions"): fields.append("actions = { %s }" % ", ".join(lua_str(a) for a in cd["actions"]))
                if cd.get("table"): fields.append("table = " + lua_table_spec(cd["table"]))
                if cd.get("segments"):
                    sg = cd["segments"]
                    fields.append("segments = { label = %s, desc = %s, options = { %s } }" % (lua_str(sg["label"]), lua_str(sg.get("desc", "")),
                                  ", ".join("{ %s, %s%s }" % (lua_str(o[0]), lua_str(o[1]), (", " + lua_str(o[2])) if len(o) > 2 else "") for o in sg["options"])))
                fields.append("rows = { %s }" % ", ".join(lua_str(r) for r in cd["rows"]))
                out.append("      { " + ", ".join(fields) + " },")
            out.append("    },")
            if ren:
                out.append("    rename = { " + ", ".join("%s = %s" % (k, lua_str(v)) for k, v in ren.items() if v) + " },")
            if dsc:
                out.append("    desc = { " + ", ".join("%s = %s" % (k, lua_str(v)) for k, v in dsc.items()) + " },")
            out.append("  },")
    out += ["}", "", "return L", ""]
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
