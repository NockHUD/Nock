# Nock

A combat HUD for Hunters on **TBC Classic Anniversary** realms (Burning Crusade
2.5.x). Nock measures your Auto Shot live, tells you exactly when a cast will
clip it and when it is free, and turns the whole ranged/melee weave into
something you can see — and practise out of combat against your own rotation.

## What it does

- **Swing timer that knows the wind-up.** Auto Shot has a haste-scaled wind-up
  that sits inside the weapon cycle; Nock measures it from the combat log
  instead of assuming 0.5 s, and draws the clip band as what it really is — a
  band, with a free queue window at the end of every cycle.
- **Rotation advice** for the Steady / Multi / Arcane cadences (`1:1`,
  `5:5:1:1`, the French rotations, weaves) with one clip deadline shared by
  every view, plus scrolling Shot Bars in the style of Fluffy Hunter Bars.
- **Weave bind and coach.** A press/release weave key (importable from
  Grounded), a range finder with reach-aware zones, a retry grid for the
  re-arm, and a live weave log (A-W / W-A / T).
- **Weave practice.** A workbench with a stage, lessons, a drill ladder, a
  scenario catalog, a replay you can scrub, and an expert combat log — graded
  against the rotation notation, at your own haste.
- **Cooldowns, procs, pet, Misdirection**, buff and debuff trackers, totem and
  mana bars, a React-style compact HUD mode, and a Classic layout — every frame
  movable, every panel skinnable through SharedMedia.
- **Warnings** that are worth a sound: quiver low, wrong trinket, pet training
  points, keybind conflicts, and boss-specific ones (Anetheron Sleep vs the
  Slammer, Teron's ghosts, the teleporter ALT-F4 countdown, Steam Tonk guard).
- **Setup wizard** (`/nock wizard`) and a setup check that catches the common
  misconfigurations, plus a shopping list for consumables before a raid.

## Install

1. Download the latest release zip from the Releases page (or from
   CurseForge) and extract it so you have
   `World of Warcraft/_anniversary_/Interface/AddOns/Nock/Nock.toc`.
2. Log in on a Hunter and run `/nock wizard`.

Requires the Anniversary TBC client (Interface 20505+). All libraries (Ace3,
LibSharedMedia, LibDBIcon, …) are embedded; nothing else is needed.
[SharedMedia](https://www.curseforge.com/wow/addons/sharedmedia) and
[FojjiCore](https://www.curseforge.com/wow/addons/fojjicore) are optional for
extra fonts, textures and sounds.

## Commands

| Command | What it does |
|---|---|
| `/nock` | Open the settings |
| `/nock wizard` | Run the setup wizard again |
| `/nock unlock` / `/nock lock` | Move and resize the frames |
| `/nock practice` | Open the weave-practice workbench |
| `/nock setup` | Setup check |
| `/nock diag` | Diagnostics in a copyable box (paste it into a bug report) |
| `/nock reset` | Reset frame positions |

## Bug reports

Open an issue with the output of `/nock diag`, what you expected and what you
saw. A screenshot or a short clip of the HUD helps more than a description.

## Development

Lua 5.1 on Ace3. The engines (rotation, clip band, practice planner and
grader, boss engines) are pure and covered by a headless test suite under
`Tests/` that runs on standalone LuaJIT:

```
luajit Tests/clip_threshold_test.lua
```

In-game verification on a training dummy is the final gate for anything that
touches timing.

## Licence and credits

Nock's own code is released under the [WTFPL](LICENSE). The Shot Bars view is
inspired by Fluffy Hunter Bars by fluffymoo4kra; the weave log follows Ishri's
Weave Time Tracker; the weave bind idea comes from Grounded by Gello. Embedded
libraries, the fonts and the icon set keep their own licences — see
[ATTRIBUTION.md](ATTRIBUTION.md).
