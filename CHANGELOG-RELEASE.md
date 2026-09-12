## 2.0.0-alpha.1

- **Alpha of the 2.0 line.** Everything below is new since 1.1.x and not all
  of it has been seen on a real raid night. Report anything odd on the
  CurseForge page or the GitHub issues; the stable 1.1.x file stays the
  default download until 2.0.0 ships.
- **Guided setup.** The first-run wizard now reveals Nock one step at a time:
  the screen starts empty, each page puts its own frames on it (HUD, then
  warnings, then trackers, then helpers) and only that page's frames can be
  dragged, with the first one already selected. Earlier frames stay where you
  put them. The wizard window docks to the right edge, drags, and remembers
  its spot. A replay from Settings (`Run setup wizard`) shows everything and
  highlights each page's frames instead; `Guided walkthrough` (or
  `/nock wizard guided`) runs the step-by-step version again. A new
  Helpers & alerts page switches on the helpers row, the eating/drinking pill,
  the retry timer and the PvP tag, and the aggro flash joined the Warnings
  page.
- **Edit focus.** While frames are unlocked, clicking a frame in the element
  list singles it out: everything else hides until you click that row again
  (or lock). Rows stay listed, so you can hop from one frame to the next.

- **A new settings window.** `/nock`, the minimap button and Interface → AddOns
  → Nock now open Nock's own window instead of the stock addon dialog: a
  sidebar of pages grouped as General, HUD & Bars, Alerts, Trackers and
  Utilities, tabs per page, and every setting on a titled card with an icon
  and a one-line explanation. The window is draggable by its title band,
  scales in four steps (General → Frames → Settings window), remembers its
  spot per profile, and closes on Escape. The old dialog stays reachable from
  the AddOns panel's "Legacy dialog" button.
- **Simple and Advanced.** A pill under the search box picks how much you see.
  Simple keeps switches, pickers, keys and the headline numbers; Advanced adds
  colours, opacities, textures, fonts, sizes and offsets. The footer counts
  what a page hides. Your choice is kept per profile.
- **Search.** Two characters in the box find settings by name, explanation,
  card, tab or page, with a hit count per page in the sidebar. Results are
  live controls grouped per card; the card's title is a link back to its
  page, Enter opens the first hit, Escape clears. Advanced settings are found
  in Simple mode too, marked ADV, and opening one shows that page in Advanced
  for the visit.
- **Presets.** Warnings (Quiet / Raid night / Everything), each HUD look
  (Compact or Lean or Minimal / Full), the buff and debuff trackers and the
  Helpers row carry a preset strip at the top of their first tab. A tick
  marks the one you are on, the tooltip lists what each turns on and off, and
  a HUD preset switches to that look first. Every minimal HUD keeps its cast
  bar; the Full looks leave the eWS brackets and lane icons off; no warnings
  preset switches on the experimental Slammer button.
- **Every page redrawn.** Tables for per-bar backgrounds, tick colours and
  tracker panels; the cooldown-grid rows as side-by-side cards with one pill
  per spell (position, icon, name, toggle, up/down/remove) and a "+" to add;
  bar order as pills; the Shopping list as one table plus a form for custom
  items; Mailbox recipients, tank names, zones and custom spell IDs as chips;
  Weave Bind's macros behind Quick fill Default / Natty / Clever; Cast Bar
  split into Bar and Look; the Totem Tracker as a Classic HUD tab.
- **Alerts → Sounds.** Every cue on one page, one tab per family: the
  dead-zone enter/leave cues (moved from Classic HUD → Range Finder, they fire
  in every look), the six warning sound pickers with previews (mirrored from
  the warnings' own pages) and the Well Fed chime.
- **Use this look.** Each HUD's overview page gets a button that switches the
  HUD to that look, next to the look picker.
- **Buff tracker and Misdirection panel can hide themselves.** Each gets a
  Show-when card: hide while rested (an inn or a city), hide when not in a
  group, and which group types bring it back (dungeon group, raid group). An
  unlocked panel always shows so you can place it. Everything off by default.
- **Sapper column: whisper the next hunter** (Experimental, off). After your
  own MD + Sapper opener, the hunter after you in the group's hunter list by
  name gets a whisper that they are next; the last wraps to the first. Only
  your own opener, so each hunter passes the rotation along.
- **Removed: the legacy Shot Bars look.** The pre-1.0.14 multi-lane bar and
  its "Use legacy Shot Bars" switch are gone; everyone gets the single-lane
  bar with the GCD shade and clip ticks. Removed: the experimental V3
  medallion (`/nock v3`, its Experimental page and the wizard's Medallion
  card).
- **Aggro warning** (Alerts → Aggro, on by default). A red starburst pulses at
  screen centre while a mob is on you (threat status: tanking), with a cue
  the moment it happens. The cue is Auto: WeakAuras' Power Auras "aggro" clip
  if you have that addon installed, else the game's text-to-speech saying
  "Aggro", else a sound you pick, else the raid-warning kit; each tier can
  also be forced. Nock ships no clip and no art of its own: the flash is the
  client's starburst and both the texture and the sound file are paths you
  can point anywhere. Drag the flash while frames are unlocked; a Reset puts
  it back; a Preview shows the art for three seconds. "Only in a group" is
  on by default: solo, everything you fight is on you.
- **React position strip** (Experimental, off). A thin two-segment strip
  welded under the React range bar: the left half lights while Auto Shot is
  usable (RANGED), the right half while you are in melee (MELEE), straight
  from the range probes, so you still know where you stand while the bar
  says RESYNC. Dark with no target; 10 px with RANGED / MELEE labels by
  default (2 to 14 px, labels from 9), and every colour is yours to set. The rows below shift
  down by its height.
- **Weave sound cues** (Alerts → Sounds → Weaving, off). A sound when your
  Raptor Strike lands and one when Windfury grants extra attacks, each with
  its own pick and preview, on the dead-zone output channel. Nock ships a
  lightsaber-ignition clip as the Windfury pick ("Nock Windfury" in any
  sound picker); the switch stays off until you turn it on.
- The settings window's dropdown lists scroll: a long list (every shared
  sound or font) shows fourteen rows at a time, the mouse wheel moves it,
  it opens on your current pick and a thin thumb on the right shows where
  you are. Before, a long list was cut off at the bottom and could not be
  scrolled.
- **PvP mode** (new sidebar section PvP). Off, On, or Auto for battlegrounds
  and arenas; `/nock pvp` toggles it and a small PVP tag on screen says it is
  on. While it is on: the Misdirection tracker (and its sapper column) goes
  away, the raid-only warnings stay quiet (boss marks, DO NOT RELEASE,
  Slammer, Ripper, Devilsaur Tooth, Karabor neck, the garment gate, drums,
  lust cooldowns, sapper AoE), the aggro flash is off, the live weave macro
  loses its Movement Pad backpedal line, and the PvP escape trinkets stop
  counting as a bad trinket. A new warning nags there instead when one sits
  in your bags with neither slot holding it. The target debuff grid gets its own
  PvP set (Serpent Sting and the scorpid pet's poison join the catalog, off
  outside the mode) and a filter that only lists debuffs a class in your
  party or raid can apply. Every one of those is its own switch; the buff
  tracker and the helper row stay by default.
- **Incoming CC alert** (PvP mode). A hostile you can see starts casting
  Fear, Polymorph, Seduction, Mind Control or Entangling Roots at you: the
  warnings row shows FD! with the cast counting down and a sound plays once,
  so you can Feign Death before it lands. The spells sit in a table, icon,
  sound, preview and switch per row, and an add line puts your own spell in
  with its own sound. The stock sound is the ringing phone WeakAuras
  registers ("Phone"); without it a row is silent until you pick another.
- `/nock classic`, `/nock react` and `/nock fluffy` now set that look
  outright instead of toggling back to Classic. The Setup Check's
  SpellQueueWindow row offers 200 ms and the 400 ms default; the 100 ms
  button is gone.
- **Utilities → General.** Three baseline switches, all off: auto repair at a
  repair vendor (own money, cost printed), sell every grey item at any vendor
  (a few at a time, total printed), and remove the full-screen glow (the
  ffxGlow CVar, also the drunk blur) at login.
- Seven long warning titles are shorter on their settings tiles (the on-screen
  squares are unchanged). Interface 20506.
