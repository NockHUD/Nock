## 2.0.0

The 2.0 line is the release now, on Anniversary and on the WoW Forever
beta from one file. Everything below is new since 1.1.10; the two alpha
entries in CHANGELOG.md on GitHub carry the detail. The 1.1.x file stays
on CurseForge for anyone who wants the old settings dialog back.

### Anniversary

- **A new settings window.** `/nock`, the minimap button and Interface →
  AddOns → Nock open Nock's own window: pages grouped as General, HUD &
  Bars, Alerts, Trackers and Utilities, tabs per page, every setting on a
  titled card with a one-line explanation. Simple / Advanced pill, live
  search across every page, preset strips on the warnings, HUD looks,
  trackers and helpers, scrolling dropdowns, and the old dialog kept
  behind a "Legacy dialog" button.
- **Guided setup.** The first-run wizard reveals Nock one page at a time
  and lets you drag only that page's frames; a replay highlights instead.
  Edit focus singles out one frame while unlocked.
- **Profiles you can share.** Profiles → Sharing exports your whole setup
  as one string and imports another player's into a new profile; bundled
  starter profiles apply the same way. `/nock share export | import |
  apply <key>`.
- **PvP mode** (Off / On / Auto for battlegrounds and arenas) puts the
  raid furniture away and adds the escape-trinket nag and a PvP debuff
  set; the **incoming CC alert** shows FD! with the cast counting down
  when a Fear, Polymorph, Seduction, Mind Control or Roots is cast at you.
- **Aggro warning** (on by default): a red starburst at screen centre
  while a mob is on you, with a cue.
- **Skin controls.** Font style (none / outline / thick), text shadow,
  countdown offsets for the buff row's numbers, the cooldown grid's own
  font size and a whole-second cooldown switch. Defaults keep the
  reference look; "Reset skin to reference look" restores it.
- **Utilities → General.** Auto repair, sell greys, the glow switch, and a
  Camera & world card: fog on/off, the game's hidden camera following
  style, and the max camera zoom with Near and Far presets, live on the
  game's own settings.
- **Also:** weave sound cues, the React position strip and the sapper
  whisper (all experimental, off), buff tracker and Misdirection panel
  show-when rules, clip ticks can be hidden, the Leviathan tranq entry,
  shorter warning titles, and the legacy Shot Bars look and the V3
  medallion removed.

### WoW Forever (beta)

**Work in progress.** The Forever side of this release is unfinished and
grows with the beta; it ships so early testers can run it, not because it
is done.

Nock now loads on the WoW Forever beta as the same addon: one download,
one profile, one settings window. Forever is a different client under
the hood (most combat numbers are hidden from addons while you fight), so
this is a trimmed Nock, built from what the client still tells us. Expect
rough edges; the Anniversary version is unchanged by any of this.

- **One HUD.** The React look only, renamed "Nock HUD": Auto Shot bar
  driven by the client's own swing events, melee bar, cast bar, mana bar
  with the tick spark, a four-zone range strip (melee, dead zone, sweet
  spot, out of range), the aggro row, aspect and Hunter's Mark corner
  icons, and the cooldown grid with a Multi-Shot + Aimed Shot pair tile.
  A spell-queue mark on the Auto Shot bar replaces the wind-up model:
  there is no clip band to model on Forever, so no clip ticks, brackets
  or delay readout.
- **Buff row.** Your own short buffs and procs (Rapid Fire, Quick Shots,
  Elune's Grace, ...) are drawn by the client itself, in combat too, with
  a bare-second countdown; Mend Pet, Feed Pet and the pet's happiness face
  sit on a smaller line above it.
- **Warnings.** Ammo low, pet dead, no pet in combat, pet unhappy, pet HP
  low (decided by the client and faded in on its own, so it has no sound
  and sits last in the row), not attacking, not in range, pet not
  attacking.
- **Spoken range cues.** Short voice clips when your target changes zone:
  dead zone, melee, in range, out of range, each with its own switch,
  sound and gate (solo, party, raid). Off outside raids by default;
  Alerts → Sounds → Range.
- **Look.** A new display face, LEMON MILK (bundled with the author's
  permission), as the Forever default for the HUD numbers and the warning
  labels, with new Skin controls that also exist on Anniversary: font
  style, text shadow, countdown offsets, a separate cooldown-grid font
  size and whole-second cooldown countdowns. "Reset skin to reference
  look" returns to the Forever baseline on Forever.
- **Utilities → General.** Auto repair, sell greys, the glow switch, and a
  new Camera & world card: fog on/off, the game's hidden camera following
  style, and the max camera zoom with Near and Far presets.
- **Not on Forever (yet or ever).** Rotation coaching and the practice
  mode, weave binds and the garment autopilot, the helpers row, the
  buff/debuff/Misdirection trackers, the mailbox and shopping tools, the
  Steam Tonk guard, PvP mode, the Auto Shot cast bar and the Blizzard
  cast-bar hide. Some of these will follow as the character levels and
  the client shows what it allows; others have no subject on Forever.
- **Known.** Saved settings do not always survive a full client
  restart on the beta (a client bug, not Nock's); `/reload` is fine.
  Mend Pet cast in combat does not stamp its tile (the cast bar shows
  it). For anything else, `/nock probe` opens a report you can paste
  into an issue.
