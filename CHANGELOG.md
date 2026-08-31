# Nock — Changelog

A combat HUD for Hunters on TBC Classic Anniversary realms.

## 1.1.6

- **Cast bar after weaves, fixed twice** (thank you to everyone who reported
  the 1.1.5 regression!). First: a Steady Shot cancelled by the weave
  step-in could leave a ghost cast behind that swallowed the bar for the
  rest of the cycle — the bar now double-checks the client one frame later,
  so a real cancel clears instantly while button-spamming still can't hide
  a running cast. Second: after the weave, the Auto Shot wind-up bar could
  be born already full and just fade out — a weave re-arm starts its
  wind-up almost exactly on the predicted shot, and the bar anchored to
  that prediction however close it was. The wind-up always takes its full
  haste-scaled time (about 0.5s divided by your haste), so the bar now
  refuses an implausibly short span and fills over the real wind-up again,
  while normal turret cycles keep ending the bar exactly as the arrow
  leaves.

## 1.1.5

- **FluffyHUD — a third HUD mode.** `/nock fluffy` (or the HUD mode picker):
  a compact flat stack — a cast bar that appears only while something casts,
  the React-style converging Auto Shot bar with clip ticks and the full set
  of auto-bar options (notation, delay readout, brackets, GCD divider, fill
  direction), the shot-window lanes as two rows (ranged windows and the
  melee weave lane), the range finder, and an opt-in cooldown icon row
  welded under the stack. Its own options branch (Size & Elements, Cooldown
  Grid, Buff Row, Skin) and a card in the setup wizard.
- **The Fluffy cooldown row is editable.** Same editor as the React grid —
  hide, reorder, remove, add anything the engine tracks, plus custom
  entries. The default row is Kill Command, both trinkets, Raptor Strike,
  your spec cooldown and Rapid Fire (trinket idea: TeamSpeakUser — thanks!).
- **Restyle the active-state highlight.** People asked to tone down the blue
  borders that light up a cooldown tile while its proc or buff is running.
  Every HUD now has its own "Active highlight" block on its Cooldown Grid
  settings: style (highlight border / animated action-button glow / none),
  border color, thickness, and whether it hangs over the tile's edges or
  stays inside them. A "Preview: light every tile" toggle shows the look
  live while you dial it in (session-only, pauses in combat). The Kill
  Command tile's own proc-glow toggle still wins on that slot.
- **Auto Shot bars survive mid-fight haste changes.** Dummy-verified over
  three logging rounds: this client never re-times an Auto Shot already
  scheduled — a Rapid Fire, Bloodlust or trinket proc (or their fall-off)
  mid-cycle applies from the *next* shot, except that the wind-up itself
  runs at the current speed. The swing bars now model exactly that, so the
  bar reaches full as the arrow leaves even when haste flips mid-cycle.
  `/nock swinglog` records a fight's shots, releases and speed edges into a
  copyable log if you want to check it yourself.
- **Karabor Medallion warning.** Wearing the Black Temple quest neck
  (either Medallion of Karabor) inside the raid shows a red warning square —
  except around Mother Shahraz, where its Shadow Resistance is wanted: the
  warning stands down when she is seen alive and returns once she dies so
  you remember to swap the real neck back in. Ships on; Warnings → Gear.
- **Cast bar: spamming the button no longer hides the bar.** A re-press of
  a spell already being cast (a mount, Steady Shot) fired failure events
  that took the running cast's bar down at half way. The bar now re-checks
  the client before clearing — a real cancel or interrupt still clears it.
- **React bar tick marks sit on the pixel grid.** Breakpoint ticks and
  dividers snap to physical pixels, so they render crisp at any UI scale.

## 1.1.4

- **Raid memory fixed.** Nock could climb to ~100 MB in a 25-man (Black
  Temple report — thank you!). The cause: on this client every aura read
  allocates ~2 KB whatever the API, and a dozen modules were walking your
  buffs, your pet's and the boss's debuffs ten times a second. Auras now
  live in one shared store that updates only when something actually
  changes, and every module reads it — measured idle churn dropped ~40x
  and a full raid night sits at a few MB instead of a hundred.
- **Less busywork everywhere.** Cooldown probes that allocated every frame
  are event-driven or read from tracked state; the buff/debuff trackers do
  nothing while switched off; the pre-pull Helpers panel and several
  warning checks stopped re-scanning things that hadn't changed; entering
  or leaving combat no longer re-applies every font and texture.
- **A performance panel.** `/nock profile show` (or Options → General →
  *Performance panel*): a small draggable readout of all addons' vs Nock's
  CPU and memory, with a **Capture** button that records what Nock spends
  and allocates per module for up to 60 s and opens the report in a
  copyable window. `/nock profile cpu on` (plus a `/reload`) enables the
  client's per-addon CPU accounting for the CPU cells.
- **Credit where due:** the Movement Pad backpedal and shirt/tabard
  swapping techniques that Weave Bind implements were discovered by
  **Joosy** of the Hunter Discord (Joosiest @ Dreamscythe) — now credited
  in the Weave Bind panel and ATTRIBUTION.md.

## 1.1.3

- **Edit-mode grid.** `/nock unlock` now draws a raster behind every frame
  (lines every 16 units from the screen centre, the centre cross brighter) and
  a small control bar at the top of the screen — drag it anywhere: raster
  size (4–64), grid on/off, **Snap** (off / on release / while dragging, where
  a green ghost outline shows where the frame will land), **Snap by** (nearest
  edge or centre per axis, or the top-left corner) and a Lock button. Snapping
  is off by default; while it is on, a nudge-pad step is one raster. The same
  switches sit in Options → General beside Lock/Unlock.
- The Cooldown Grid's *Reference-WA extras* header is now *Glows & tints*.

## 1.1.2

- **React HUD: five reference-WA extras, all off by default** (React HUD →
  Cooldown Grid → *Glows & tints*). **Kill Command proc glow** puts the
  animated action-button glow on the KC tile while the proc is up (the static
  border stays the default). **Kill Command glow on the action bar** lights the
  real bar button(s) holding Kill Command — or a macro casting it — while the
  proc is up; Blizzard bars, Dominos, Bartender4 and ElvUI are found, it works
  in combat, and it is not tied to the HUD mode. **Out of range** tints a grid
  tile whose spell cannot reach the target, per spell like the WA — shots in the
  dead zone or beyond max range, Raptor Strike outside melee — as a red tint or
  greyed out; item tiles are never tinted. And the rest of that WA's icon
  conditions as two more toggles: **Dim while unavailable** (on cooldown or
  not usable → greyed at 60 %) and **No mana: blue**. The Kill Command proc is
  read the way the WA reads it — the spell usable, off cooldown, and a live pet
  (the client reports Kill Command usable with no pet out).

## 1.1.1

- **Licence.** Nock is released under the WTFPL (`LICENSE`); the source lives
  at https://github.com/NockHUD/Nock. `ATTRIBUTION.md` now reads as it should
  have: the Shot Bars are Nock's own implementation *inspired by* Fluffy
  Hunter Bars, not a derivative of its code, so no NonCommercial term applies.
- **Ripper countdown: a "Wrong debuff?" card.** A small card under the
  numeral for the whole cast, so the plan is read before the ALT F4 moment.
  Its text follows your engineering specialization: Gnomish — the World
  Enlarger clears the small debuff for another try; Goblin — an arena
  skirmish resets your debuffs; unspecialized — the pitch for the Enlarger.
- **Practice: pages lay out right on smaller screens.** On a 1080p screen
  the Keys page could build while the window was being rescaled to fit, and
  its two columns landed on top of each other; every page now sizes off the
  workbench's own width.
- **Slammer button: remove the drunk effect.** A checkbox on the Anetheron
  Slammer warning that is the `ffxGlow` console variable itself: ticked sets
  it to 0 (no drunk blur), unticked sets it to 1. It reads the live value, so
  it shows ticked if you already run `ffxGlow 0`.
- **Slammer button: the stand-down reads `WINDOW CLOSED`** (was `SLEEP IN`)
  over its countdown, and the cover-margin slider runs 1.3–3 s in 0.1 s
  steps (default still 2 s).

## 1.1.0

The practice release. `/nock practice` grew from a graded drill into a
workbench that teaches the rotation — a stage, a lesson, a ladder, a replay
— and alongside it: the Anetheron Slammer button, the Grounded weave-key
import, the Ripper countdown and a batch of HUD fixes. Everything under this
heading is new since 1.0.27; the practice panel, picker and review described
towards the end of the list are the pieces the workbench now hosts.

- **Practice: the workbench.** Practice opens one window in its own skin
  (black ground, the hunter's green as the only accent, three shipped
  fonts): a rail on the left — Stage, Scenarios, Ladder, Lesson, Keys, Style
  — and the toolbar over the stage (scenario picker, state chip, fight
  clock, streak, metronome, Lesson / Focus / Expert / Start). **Focus** pulls
  the stage alone onto the HUD for a fight; **Expert** drops the stage and
  keeps two panels — a combat log of what you actually did (MOVE / AUTO /
  CAST / MELEE / CD lanes, the buff row to click procs up, the scenario
  picker in its head) and the weave log. Both have keybinds and slash forms
  (`/nock practice focus|expert`). The window caps its own scale to fit the
  screen; the practice scale slider reaches 3.0. Closing the window (X,
  Esc) leaves practice. The fight review stays behind an OFF switch
  (`practiceReviewEnabled`) while its verdicts are tuned.
- **Practice: every note is judged.** Each press against the paper gets one
  verdict — PERFECT / GOOD / LATE / CLIP / MISSED / OFF — with a running
  streak and a best streak, and the grade is built on *cycles on paper*: how
  many auto-to-auto cycles held every note the rotation asked for and
  nothing extra. The old "vs paper" damage percentage is gone. A clip the
  paper itself schedules (5:5:1:1 waits behind its own Multi) is amber and
  never a fault; only a clip your hands caused paints the auto red.
- **Practice: the stage.** One row per ability the paper uses — its icon,
  its name and the key you have it bound to (`NO KEY` in red) — scrolling
  past a NOW column; the next press wears a `NEXT <key>` chip, the weave row
  carries an amber move-in ramp from the release, a four-dot metronome
  ticks the auto and the weave gap. Notes keep their identity through haste
  changes (they glide, never blink). Nine style levers under Practice →
  Colours & style, and a Style page that previews them live with a ghost
  hunter. `/nock practice demo` runs that ghost on any paper.
- **Practice: one oracle.** The medallion, the stage's NEXT and the coach
  line read one plan. The planner puts the paper on the hand's clock: a
  press inside the wind-up is queued to the release, a paper that clips by
  design clips where the paper clips, the release a weave lands on belongs
  to the weave (weave → Arcane, never Arcane → weave), a shot never starts
  inside a weave's walk and a weave never walks inside a cast. A paper that
  clips by design or asks a knife-edge weave says so — an amber C / W on its
  Scenarios card, a banner under the lesson, the ARMED coach line.
- **Practice: replay.** Stop opens the stopped fight for scrubbing: the
  wheel over the stage (Shift 2 s, Ctrl 0.05 s, Alt = next delayed auto), a
  transport over the coach row (skip / prev clip / play / next clip / skip,
  a track with a marker per delayed auto), `/nock practice replay`. The
  whole HUD scrubs with it — swing bar, cast bar, cooldowns, range bar, the
  medallion — so a clip can be read off the real frames.
- **Practice: Lesson and ladder.** The Lesson page draws the paper's whole
  period — every wind-up, release, cast, instant, weave and wait — over
  five narration steps (wind-up start, Steady deadline, weave gap) with
  `Play slowly` / `Play`, and beside them the Drop: notes falling onto
  keycaps that are your real binds. The Ladder is ten rungs on three tracks
  — TURRET (beat, multi, arcane, french), WEAVE (weave-beat, -out, -shot,
  -full), MASTERY (rhythm, opener) — each the rung under it plus one more
  thing, one-minute attempts graded against the rung's pass line, nothing
  locked. `/nock practice lesson|ladder`, `ladder reset`.
- **Practice: Scenarios, at your haste.** The Scenarios page is an
  accordion — Turret / Weave / Mine / Drills + ladder / Free play, one box
  open at a time. A paper drill runs at your own measured haste when it
  lies in the rotation's bracket, and the basic papers (1:1, 1:2, 2:3, 2:5)
  carry a Multi whenever it is off cooldown, as rotationtools intends. A
  paper drill rolls no crit, so no Kill Command window appears that the
  paper never stated (`kc=on` in a script keeps it).
- **Practice: the Keys page and proc keys.** The weave key first (with the
  Grounded import beside it), then every rotation key as detected on your
  bars with a capture button to override it, then PROC KEYS — Lust, Drums,
  Pot, DST, RF, QS — practice-only binds that pop the proc from the
  keyboard. The buff tiles cycle: one click pops it, two hold it for the
  fight, three (or right-click) clear it; QS's right button toggles its
  roll.
- **Practice: the weave log.** A small panel, one row per weave — Ishri's
  numbers (A-W: last ranged cast ends → melee hit; W-A: hit → next ranged
  cast starts; T, coloured by his steps) with the verdict's icon, a FAILED
  row in red when a weave landed no hit. The toolbar's Log button shows it
  in practice; `/nock weavelog panel` (Options → Weave Bind) shows the live
  one in real fights.
- **Practice: Options is five tabs.** Practice / Opener / Keys / Advanced /
  Colours & style instead of 89 controls on one scroll, an EXPERIMENTAL
  line at the top, and Start practice from Options closes Options.
- **Weave Bind: the weave-key dialog and the Grounded import.** A paper that
  weaves, graded with no weave key, now says so everywhere (the ARMED line,
  a red K on the card, the lesson banner) and the toolbar carries a **Set
  weave key** / **Import weave key** button that opens a two-step dialog:
  your macros (Default / Clever / Natty / From Grounded, the wizard's own
  cards), then your key. Users of Grounded (Gello) can move their weave bind
  into Nock in one click — key and both macro bodies, Grounded's copy
  removed so the key is Nock's at once, with Undo, and a separate Disable
  Grounded step (reloads the UI) once it holds nothing. Offered on the
  wizard's weave-macro page, in Setup Check, under Options → Weave Bind and
  on the Keys page.
- **Weave Bind: the release re-arm, and honest flips.** With the Snowball
  poke gated behind a garment, the release macro gets `/startattack` gated
  the other way round, so the attack state is re-checked whichever garment
  you wear; stock macros are upgraded once at login, custom ones are never
  touched. Flipping the garment (Shirt / Tabard) or the direction now
  rewrites every bracket in both bodies — including imported ones — instead
  of leaving a stale `[equipped:Shirt]` behind.
- **Warnings: the Anetheron Slammer button — EXPERIMENTAL, off by default.**
  A boss warning you click: a secure button that drinks a Sulfuron Slammer
  (the Midsummer drink whose burn breaks Anetheron's Sleep) — `CLICK NOW`
  in red when the Sleep window opens (16 s after engage / 16.5 s after each
  Sleep, the PTR-tested numbers of the "Sleep & Slam" WeakAura), a cast bar
  along the icon's edge when the boss shows one, `COVERED` in green while
  the burn will outlast the landing, a Glass chime at the window and an air
  horn at a cast you are not covered for. Shown while Anetheron is in view
  or the fight runs (secure frames cannot appear mid-combat). `/nock
  slammer test|cast|sim [secs]|off`. Warnings → Boss; test it on a real
  pull before trusting it. The shopping list's curated restock gains 20
  Slammers. (`Modules/SlammerEngine.lua`, `Modules/SlammerWatch.lua`,
  `UI/Frame_SlammerButton.lua`.)

- **Warnings: the Ripper / Transporter ALT F4 countdown.** Casting the
  Dimensional Ripper - Area 52 or the Ultrasafe Transporter: Toshley's
  Station puts big centre-screen text up: the whole seconds (9 … 1) down to a
  moment just before the cast ends, then a red pulsing **ALT F4** at that
  moment. Close the client
  right there and you keep the trinket's side effect (a bigger character is a
  real help in a raid) without the trip. Nock only counts — it never closes
  anything. The lead (1 s by default), the text size and an optional sound at
  the flip are under Warnings → You; unlock frames to place it.
  `/nock ripper test [secs]` runs a fake cast, `/nock ripper off` ends it,
  `/nock ripper` dumps what the watcher resolved. On by default — it only ever
  triggers on those two trinkets' casts. (`Modules/RipperEngine.lua`,
  `Modules/RipperWatch.lua`, `UI/Frame_RipperCountdown.lua`;
  `Tests/ripper_engine_test.lua`.)
- **Warnings: quiver almost empty.** A red square with your ammo's icon and
  the count when the arrows (or bullets) physically IN your quiver or ammo
  pouch drop below the threshold (400 by default, slider 50-2000) — a
  different number from the info row's arrow counter and the shopping list's
  ammo total, which add the stacks in your regular bags and your arrow makers'
  charges. In and out of combat. No quiver equipped, no warning.
  (`Modules/Warnings.lua`.)
- **Shopping list: show stocked items, and Fel Mana.** A tick in the panel's
  top-left corner (also Options → Shopping → "Show stocked items too") lists
  every tracked item, the stocked ones greyed with a green count, so the panel
  doubles as an inventory check. The mana-potion line now also counts Fel Mana
  Potions. (`Modules/ShoppingList.lua`, `UI/Frame_ShoppingList.lua`,
  `Core/Constants.lua`.)
- **Debuff tracker: Scorpid Sting and Insect Swarm, and an order.** Both
  mitigation debuffs are in the preset list, OFF until you switch them on
  ("Restore preset defaults" puts them back off). Every tracked debuff —
  presets and your custom ones — now has Up / Down buttons in Options, plus a
  "Reset order". (`Modules/DebuffTracker.lua`, `Core/Constants.lua`,
  `Config/Options.lua`.)
- **Classic HUD: the Spec cooldown row hides when you don't have the spell.**
  Readiness / Silencing Shot / Bestial Wrath is picked by your most-pointed
  talent tab; a hunter without the 41-point talent used to see it anyway, ready.
  The row is now dropped from both grids while the spell is unknown, and the
  Classic grid finally rebuilds on a respec. (`Modules/Cooldowns.lua`,
  `UI/Frame_ReactCooldowns.lua`.)
- **React proc row: pet Frenzy, a MOVE IN alert, and nothing important lost on
  a boss pull.** The pet's Frenzy proc has a slot (its own toggle under React →
  Buff rows) — and a mode: *Missing on bosses* (the default) keeps the slot
  there for the whole fight while a raid boss is targeted, bright while Frenzy
  is up, greyed while down and MISSING once it has been down 2 seconds (a
  dropped proc, not the gap between two); on trash and in dungeons it shows
  when up. *When up* and *Missing always* are the other two. Needs the Frenzy
  talent and a live pet. A live target outside Auto Shot range shows a greyed Auto Shot
  icon labelled MOVE IN (toggle `movein`; works at a dummy too). And the row —
  ten slots, anything past that dropped — now fills alerts → Windfury → pet →
  your own procs, so a Lust + Drums + RF + trinkets pull drops a trinket proc
  instead of Windfury or the Grace alert, which is what "missing on bosses"
  was. (`UI/Frame_ReactBuffs.lua`.)
- **Classic HUD: the Buff Row.** The React proc row — procs, utility buffs,
  Windfury, the pet's Frenzy, MOVE IN — floats above the Classic HUD too, in
  the React look: just above the cast bar by default, draggable anywhere when
  unlocked (or via its nudge pad; the pad's reset puts it back), HUD-relative
  so it follows the HUD's scale and drags (Layout → HUD elements → Buff row,
  on by default; its own scale under Per-element scaling).
  Its settings live on a new **Classic HUD → Buff Row** page that is the same
  page as React HUD → Buff Row: one implementation, one set of profile keys,
  so a change on either side is the other's. Only the on/off switch, the
  placement and the scale are per HUD mode. (`UI/Frame_ReactBuffs.lua`,
  `UI/HUD.lua`, `Config/Options.lua`.)
- **Unlocked frames say their name.** While the HUD is unlocked every movable
  frame — the HUD box, each row, the cast bar, the buff row, the medallion,
  the Misdirection panel, the trackers, the shopping list, the side panels,
  the corner icons — wears a small green name tag in its corner, so a
  screenshot of an unlocked layout says which panel is which even when they
  overlap. Rows are named in plain words (Rotation, Swing Timers, Cooldown
  Grid, …). (`UI/EditMode.lua`, `UI/HUD.lua`.)
- **Minimap icon.** The Nock mark on the minimap: left-click opens the
  settings, right-click locks / unlocks all frames. General → "Minimap icon"
  or `/nock minimap` hides it. (`Core/Minimap.lua`.)
- **"Hide out of combat" — two refinements.** Practice mode keeps the HUD up
  whatever the switch says. And the same switch now also hides the buff
  tracker and the Misdirection panel while you are RESTED (an inn, a city) —
  not merely out of combat, where both are wanted between pulls.
  (`Core/State.lua`, `UI/HUD.lua`, `UI/Frame_BuffTracker.lua`,
  `UI/Frame_Misdirect.lua`.)

- **Practice: movable panel and review window, `/nock practice reset`.** The
  practice panel and the fight review now drag by their title bar whenever no
  fight is running — locked only while a fight is on — regardless of the
  global lock, since these are tools rather than HUD chrome. The review window
  rides above the panel and the HUD (HIGH strata, toplevel); the panel is
  toplevel too. `/nock practice reset` re-centres both windows and drops
  their saved positions. (`Modules/Practice.lua`, `UI/Frame_Practice.lua`,
  `UI/Frame_PracticeTimeline.lua`.)

- **Practice: the conveyor.** Three lanes — SHOTS, WEAVE, PROCS — scroll
  smoothly right to left past a fixed gold hit line (30% of the lane width by
  default): shot blocks sized to their own cast time, a weave band that
  appears once the swing is ready, and proc icons with their remaining time.
  A clip turns the crossing auto red as it hits the line, with the verdict
  toast anchored right there. Docked, it's a strip built into the practice
  panel; the panel's Undock/Dock button pops it into its own movable window
  at the timeline width, dragged by its lane-label gutter whenever no fight
  runs. New Options under Utilities → Practice → Conveyor & review: speed
  (px/s), past and lookahead seconds, hit line position, and the docked
  toggle (flips live via `NOCK_PRACTICE_DOCK_CHANGED`).
  (`UI/Frame_PracticeConveyor.lua`, `Core/PracticeTimeline.lua` `T.Strip`,
  `UI/Frame_Practice.lua`, `Config/Options.lua`, `Config/Defaults.lua`.)

- **Practice: scenario catalog and picker.** `Practice.BuildCatalog` turns
  every turret bracket from `Rotations/Profiles.lua` and every weave
  notation into a 60 s paper drill with its haste pinned (`lock=`/`ews=`)
  and its procs HELD to match the notation each drill claims — so the
  rotation can't rename itself mid-drill — alongside the built-in proc
  scripts, your own scenarios and Free play (no auto-stop, procs roll live).
  A scenario whose name a paper drill or script already owns is dropped with
  an error rather than silently shadowed, and a weave notation with no
  drill mapping is skipped the same way. `/nock practice scenarios` (also
  wired to the panel's scenario card) opens a window listing the whole
  catalog as cards in five groups, current pick gold-bordered, Free play and
  "+ New..." dashed; a card click sets the scenario and closes,
  "+ New..." jumps to Options. The scenario DSL keeps `hold=` (pin a proc up
  without rolling it) and `len=0` (open-ended, i.e. Free play) from earlier
  tasks. (`Modules/Practice.lua`, `UI/Frame_PracticeScenarios.lua`,
  `Config/Defaults.lua`.)

- **Practice: icon proc palette.** The five text proc buttons and the QS
  checkbox are now seven React icon tiles — RF, Lust, Drums, DST, Pot, QS,
  KC — captioned underneath, desaturated while down, each with a Cooldown
  child that sweeps backwards for a proc's remaining duration and forwards
  for its cooldown; KC takes no clicks since only a crit opens its window.
  In a paper drill the tiles stay visible but inert and read "locked" since
  the scenario pins the haste. The per-slot cooldown swipe sits on its own
  text-layer child (the `textLayer` pattern from `UI/Widgets.lua` /
  `UI/Frame_PetStatus.lua`) so it no longer paints over the slot's own time
  and label text. (`UI/Frame_Practice.lua`, `Modules/Practice.lua`.)

- **Practice: panel restyle.** The practice panel is rebuilt at 560 px on
  the current visual system: a title bar (grip, gold PRACTICE, a state chip
  — READY / FIGHT m:ss / FIGHT OVER — and an eWS/notation/latency info
  chip, then Start/Stop, Review and leave), a scenario card that opens the
  picker (swatch, name, sub-line, change chip) beside the NOW/NEXT slots and
  a fit/wait hint line, the conveyor strip, five stat tiles (auto/GCD
  efficiency, clips, weaves, kill command), the proc palette, and a footer
  with the keys summary and Keys/Options/Undock buttons. The old recent-press
  tile strip, plain score/footwork/status lines and the scenario dropdown are
  gone — the conveyor and the tiles carry what they showed.
  (`UI/Frame_Practice.lua`, `Modules/Practice.lua` `CurrentCatalogItem`.)

- **Practice: review restyle, letter grade, live mode removed.** The fight
  review window is rebuilt the same way: a title bar (grip, gold FIGHT
  REVIEW, a chip naming the fight on screen — scenario, length, seed, an
  infinity sign for Free play — and an eWS/notation/latency chip, then Copy
  report and close), a grade block (a 95%+ A down to an F, with a plus for
  the top third of a band) beside six stat tiles (auto/GCD efficiency,
  clips, weaves, kill command, opener), and fault rows whose verdict is now
  a severity chip (bad/warn/good) instead of coloured text, with the Top fix
  in a gold-bordered box. Copy report carries the grade. Live mode — the
  playhead, the lookahead ribbon, and the `practiceTimelineLive` /
  `Lookahead` / `Head` options — is gone; the conveyor is the live surface
  now. (`UI/Frame_PracticeTimeline.lua`, `Modules/PracticeGrader.lua`
  `G.Grade`, `Modules/Practice.lua`.)

- **Practice mode (phase 2, turret drills).** `/nock practice` runs a
  simulated fight on your real HUD: no target, no casts. Your Steady /
  Multi / Arcane keys drive a simulated hunter (swing grid, wind-up, clip
  band, GCD, spell queue, your live latency) and a toast grades every press
  — CLIP, LATE, STEADY WON'T FIT, CATCH-UP MULTI MISSED, GOOD — with a
  scorecard on Stop fight (auto/GCD efficiency, clips, damage vs the paper
  rotation). Keys fall back to your real buttons the moment combat starts.
  Settings under Utilities → Practice. Weaving, procs, scenarios and the
  fight timeline are next. The panel now guides the drill — NOW/NEXT icons
  from the rotation engine, a strip of your last presses tinted by verdict,
  a live score line — and mashing a key is never a fault (mashing the spell
  already casting is ignored; only a different key pressed too early counts).
  The weave key stands down while practice is on — it stays bound and runs an
  empty macro, so a mob that pulls mid-drill hands it straight back (weave
  drills come in the next phase). `/nock practice keys` dumps what
  key detection saw, and the options key fields capture the combo you
  press. (`Core/PracticeModel.lua`, `Modules/PracticeEngine.lua`,
  `Modules/PracticeGrader.lua`, `Modules/Practice.lua`,
  `UI/Frame_Practice.lua`; live producers yield on `state.sim.active`.)

- **Practice mode (phases 4–5): procs, scenarios, Kill Command, opener,
  timeline.** Haste now moves during a drill, cooldowns are graded like the
  shot keys, and a timeline lets you walk the fight back. Broken out below.

- **Practice: procs and scenarios.** Panel buttons for RF, Lust (Bloodlust),
  Drums, DST (Dragonspine Trophy) and Pot (Haste Potion), plus a Quick Shots
  toggle, fire the same haste sources a real fight would. A scenario
  dropdown picks one of five built-ins (Clean French, Rapid Fire at 5 s,
  RF + Quick Shots, Lust + RF + Drums, Raid pull) or a scenario typed into
  Options in the DSL `Name: rf@5 lust@20 drums@20 dst@30 pot@21 qs@5
  ews=2.17 lock=5:5:1:1 len=90 qs=off` — procs at seconds, `ews`/`lock` pin
  the speed or notation, `len` auto-stops the fight, `qs=off` disables the
  roll. A seeded RNG (`Seed` in Options) makes Quick Shots rolls and crits
  repeatable, so two attempts at the same seed and scenario differ only in
  what you pressed. (`Modules/PracticeEngine.lua`, `Modules/Practice.lua`,
  `UI/Frame_Practice.lua`.)

- **Practice: Kill Command windows.** Any crit — auto, Steady, Multi or a
  melee hit, rolled on the same seeded RNG at your live crit chances —
  opens a 5 s Kill Command window. The tracked cooldown slot glows while a
  window is open, and the report/scorecard gains `KC: windows n · used m`.
  (`Modules/PracticeEngine.lua`, `Modules/PracticeGrader.lua`,
  `Modules/Practice.lua`.)

- **Practice: cooldown keys and opener grading.** Rapid Fire, Bestial
  Wrath/spec, both trinket slots (`/use 13` / `/use 14`), Drums and the
  Haste Potion are taken over the same way the shot keys are, each with its
  own Options key field. The opener now grades against a selectable anchor
  — pull, Bloodlust, Drums, Haste Potion or Rapid Fire — checking each
  listed cooldown against it; a cooldown fired before the anchor lands is
  called `EARLY` rather than credited. The report's `Opener (anchor): …`
  line marks Steady timing, Multi-on-pull and every cooldown.
  (`Modules/PracticeEngine.lua`, `Modules/PracticeGrader.lua`,
  `Modules/Practice.lua`.)

- **Practice: per-haste-window scorecard.** The scorecard now cuts a
  window per haste state, each with the expected notation next to the one
  you actually played, its own auto/GCD efficiency, and paper damage for
  that window — the haste-adaptation grade the phase-4/5 design asked for.
  (`Modules/PracticeGrader.lua`, `Modules/Practice.lua`.)

- **Practice: report Analysis block.** `/nock practice report`'s copybox
  now opens with a `scenario/seed` header and gains an Analysis block: a
  `Top fix` line (fault code, count, cost, advice) followed by each fault's
  you did / expected / cost. (`Modules/Practice.lua`.)

- **Practice: timeline window.** `/nock practice timeline`, a panel
  button, or Stop fight (auto-opens) brings up a window with five lanes —
  paper, auto, cast, melee, procs — painted with spell icons, verdict marks
  with You did/Expected tooltips, and expected-cast ghosts. Analysis rows
  below the lanes jump the view to the fault when clicked; Copy report
  opens a copybox with the plain-text report. A live-scrolling mode (Live
  in Options → Timeline) keeps a playhead and a lookahead ribbon on every
  lane while a fight runs, tunable alongside px/s, width and the ✓-marks
  toggle. (`UI/Frame_PracticeTimeline.lua`, `Modules/Practice.lua`.)

- **Practice: Options — Procs & scenarios / Opener / Timeline.** Three new
  sections under Utilities → Practice: Procs & scenarios (Quick Shots
  toggle, seed, scenario dropdown, custom-scenario editbox), Opener (anchor,
  opener GCD count, opener Steady cast time, per-cooldown checkboxes) and
  Timeline (px/s, width, live, lookahead, playhead position, ✓ marks), plus
  six new cooldown key fields (Rapid Fire, Bestial Wrath/spec, Trinket 1,
  Trinket 2, Drums of Battle, Haste Potion). (`Config/Options.lua`.)

- **Practice: the auto bar holds through a clip.** A Steady fired into the
  clip band used to re-anchor the auto bar to the pushed shot the moment the
  cast began — a jump back of the whole overlap. The bar now fills to the
  grid and sits full as a held shot until the late auto fires, exactly as
  live (`Nock.AutoSwingLive` treats a practice fight as combat).
  (`Core/State.lua`, `Modules/PracticeEngine.lua`.)

- **Practice: `/startattack` is range-aware.** A `/startattack` in a
  Steady/Arcane macro used to switch the sim's auto to melee mode on every
  press (Arcane spam "reset" the timer; after one weave the autos died). As
  live, at range it now starts Auto Shot (never re-basing a running grid) and
  only inside melee reach — or on a held weave key — starts the melee auto.
  `/stopattack`, Raptor and the poke still count only on the weave key
  (`/nock practice keys` lists them as `(weave-only)`).
  (`Modules/PracticeEngine.lua`, `Modules/Practice.lua`.)

- **Practice: no dead sliver between melee and Auto Shot.** The sim's Auto
  Shot minimum was 5.01 yd against a 5.0 yd melee reach, so one backpedal
  tick could park you at 5.00–5.01 — painted PERFECT, but unshootable — where
  a wind-up stuck forever and every Steady queued behind it ("auto just
  stops"). Minimum is now the melee reach, as live. A weave held before the
  first auto no longer reports a nonsense WEAVE SLOW budget.
  (`Core/Constants.lua`, `Modules/PracticeEngine.lua`.)

- **Practice: stepping in no longer kills the auto.** Entering melee without
  the weave key pauses the shot (too close) and it resumes on the way out;
  it used to disarm the auto outright, blanking the auto bar and the weave
  lane until the next Steady re-armed it. Only `/startattack` switches the
  auto to melee. (`Modules/PracticeEngine.lua`.)

- **Practice: Arcane never touches the auto timer.** An instant no longer
  counts as a cast for the clip rule (it used to push a wind-up that had not
  started), fires at once even inside the wind-up when the GCD is free, and
  a shot press during a weave hold no longer re-arms the auto — only
  `!Auto Shot` switches the auto back to ranged (and switches the melee auto
  off). Spamming Arcane mid-weave used to reset the grid.
  (`Modules/PracticeEngine.lua`.)

- **Practice assumes the Snowball poke.** A `[noequipped:Shirt]`-gated
  `/use Snowball` line used to be resolved against the shirt you practise
  in, silently dropping the poke from the drill. The sim now strips garment
  gates and grades the boss-fight macro. (`Modules/Practice.lua`.)

- **Practice: `/startattack` inside melee swings at once.** Without a
  Snowball poke the sim always waited for the server's 0.5 s re-check from
  the moment you stepped in, so a key pressed inside melee and a quick
  backpedal never landed. Starting the attack from inside range swings
  immediately, as live; the pulse applies only when you start attacking from
  outside and walk in. The first auto of a fight is no longer measured
  against a grid that did not exist yet. (`Modules/PracticeEngine.lua`.)

- **Practice grades the way-out weave fairly.** Stepping into melee before
  the key no longer closes the weave window (it read as WEAVE MISSED), a
  weave begun inside melee gets a zero step-in leg instead of none, and
  DEAD ZONE now means "still inside when the auto's wind-up wanted to
  start" rather than "a Steady no longer fits" — the gap you weave in.
  `/nock practice debug` captures every engine event; `/nock practice
  debuglog` opens them in a copybox. (`Modules/PracticeEngine.lua`,
  `Modules/Practice.lua`.)

- **Practice credits fast weaves on the way out.** The sim applied your weave
  key with your live latency but moved you instantly, so a poke-and-backpedal
  weave found you already out of melee and nothing landed. The engine now
  judges melee the way the server does — against where you were when the
  press was made — so a hit earned inside melee lands even after you've
  backed out. (`Modules/PracticeEngine.lua`.)

- **Practice footwork is speed-only.** The weave drill no longer tracks a
  target position or your facing (the geometry anchor put the virtual target
  behind you). Running closes, backpedalling retreats, standing holds —
  nothing moves you but your keys, so the bar stops the instant you do. The
  bar is your pixel finder: creep until the thumb sits on the melee divider,
  then a tap forward is in and a tap back is out, exactly the pixel weave you
  do live. (`Modules/PracticeEngine.lua` `Reckon`, `Modules/Practice.lua`.)

- **Practice range bar reads the real distance.** The drill maps its known
  distance straight onto the bar (same states and border values as the live
  glide, continuous everywhere), so the thumb moves smoothly with your feet
  and never snaps or RESYNCs. Past 10 yd it
  resolves the finding ladder from the virtual distance (with your Hawk Eye
  / Scatter rungs) instead of going blank. (`Core/PracticeModel.lua`
  `RangeProg`/`LadderBracket`, `Modules/Practice.lua`.)

- **Practice keeps your auto-backpedal.** With a "Clever" weave macro
  (`/click MovePadBackward` in both bodies) the weave key now still runs the
  Movement Pad step-out during a drill — hold backs you out, release stops
  you — while the attack lines stay simulated. The button runs practice
  bodies (`Core/WeaveMacro.lua` `PracticeBody`) instead of an empty macro;
  key-only footwork runs nothing, as before. (`Modules/WeaveBind.lua`.)

- **Practice mode (phase 3, weaving).** The drill now models the melee
  weave. A virtual target stands `Start distance` yards out at the pull,
  and either your real footwork (`UnitPosition`, or dead-reckoning off your
  run/backpedal speed where that's unavailable) or the engine's own timer
  ("Weave key only" footwork) carries you toward and away from it. Hold
  your real weave key to step in — the sim reads your actual Weave Bind
  macro to know whether the hold presses Raptor Strike or just melee
  attacks, so it lands a Raptor hit (off cooldown) or a plain white hit at
  the swing's own instant, and charges the same re-arm cost for an early
  release that the live retry grid does. Five new verdicts: WEAVE ✓, WEAVE
  SLOW (a leg over the slow-leg threshold), WEAVE MISSED (a free window
  with no weave), RE-ARM (an early release), DEAD ZONE (still in melee
  past the point a Steady would fit). The panel gained a footwork caption
  and weave counts on the score line; new settings under Utilities →
  Practice → Weave (footwork, start distance, step time, melee/re-arm
  retry pulses, slow-leg threshold). `/nock practice pos` dumps the sim's
  read on your position for troubleshooting. (`Modules/PracticeEngine.lua`,
  `Modules/PracticeGrader.lua`, `Modules/Practice.lua`,
  `UI/Frame_Practice.lua`, `Config/Options.lua`.)

## 1.0.27

- **Every classic bar's background is now colourable.** The track behind each
  bar -- the part that shows through wherever the fill hasn't reached -- was
  hardcoded to black with a black 1px edge, which is why the classic HUD read
  as a stack of black boxes. The Auto Shot, Melee and GCD bars (Classic HUD ->
  Swing Bars), the mana bar, the range finder, the Shot Bars timeline (Classic
  HUD -> Shot Bars) and the cast bar each gained their own **Bar background**
  block: fill colour + opacity and border colour + opacity. Per bar, not
  global, so you can leave the ones you like alone. Defaults reproduce the old
  look exactly, so nothing changes until you touch one. Note the cast bar now
  has two blocks -- *Background* skins the panel around the icon and bar,
  *Bar background* skins the bar itself.

- **Bar mark widths are now real screen pixels, and the marks are pixel-snapped.**
  A "pixel" in `SetWidth` is a logical unit the UI scale multiplies into actual
  screen pixels, and the two diverge hard: at a UI scale of 0.5333 (1440p on
  the 768-line default) a 2-logical-pixel tick is only 1.07 real pixels. That
  is why every mark on the Auto Shot bar rendered as the same dim hairline no
  matter what width it was given, and why they appeared to change width once
  you started shooting -- the measured swing duration and wind-up replace the
  seeded ones, moving every mark to a different fractional offset, where a
  solid quad straddles two pixel columns at half brightness each. Widths are
  now specified in device pixels and converted through the bar's effective
  scale, and mark positions are snapped so the quad's edges land on device
  pixel boundaries. Applies to both the React and classic Auto Shot bars, and
  re-applies automatically when the effective scale changes.

- **Every mark on the React Auto Shot bar is now styleable.** The Steady clip
  tick, the Multi clip tick, the wind-up commit landmark and the eWS brackets
  each gained a width and a colour under React HUD -> Skin, joining the GCD
  divider and the gold fill. Defaults reproduce the reference constants
  exactly, so nothing changes until you touch one, and all of them are in
  "Reset skin to reference look". These are React-scoped keys: the classic HUD
  keeps its own clip tick colours, so the two HUDs can be styled apart.
- **The classic Auto Shot bar's clip ticks gained widths too.** It already had
  colour control for its three ticks but no width; `clipTickSteadyWidth` /
  `clipTickMultiWidth` / `clipTickWindupWidth` sit beside those colours, each
  defaulting to the hardcoded 2px.
- **The React bar legend now shows your colours, not the reference ones.**
  Three of its swatches were hardcoded because the tick colours used to be
  fixed constants; they follow the profile now, and the miniature's ticks
  follow your configured widths as well.

- **GCD divider on the React Auto Shot bar (off by default).** The reference
  WeakAura draws the global cooldown onto the swing bar as a moving divider;
  Nock can now do the same. It is not a threshold like the red/orange clip
  ticks — it runs the GCD's *own* progress across the bar the way the gold
  fill runs the swing, and it follows the Auto Shot bar's fill direction:
  Converge puts one purple line in from each edge, left/right a single line
  from the fill's origin edge. Nothing is drawn while you're off the GCD.
  Switch it on under React HUD → Bars; width and colour live under Skin.
  (`UI/Frame_ReactCluster.lua`, `UI/Widgets.lua`, `UI/AceGUI_BarLegends.lua`,
  config.)
- **The auto bar's marks now share one projection.** The "fraction of the
  cycle → point on the bar" arithmetic existed twice in
  `Frame_ReactCluster.lua` (the clip/wind-up pair and the eWS brackets) and
  the GCD divider would have made three. It is now `Nock.UI.ReactAxisPoint`,
  used by all of them and covered by `Tests/react_gcd_divider_test.lua` — the
  same lesson the clip threshold taught.

- **The React buff row can be moved.** It was welded above the cluster with no
  way to shift it; it is now freely placeable, dragged by its edit border while
  unlocked or nudged a pixel at a time from the pad. Resetting the pad re-welds
  it to the default position above the cluster, where it still lifts itself
  around the cast bar.

- **Helpers panel overhaul — buffs are now matched by spell ID.** The old
  matcher compared aura *names*, which quietly never worked for several
  helpers: a scroll's aura is named just "Agility" / "Strength" (not "Scroll
  of Agility"), so both scroll reminders were stuck on "missing" forever no
  matter what you drank. Elixir auras have the same problem — they use short
  names like "Major Agility" and "Greater Armor", not the item names. Every
  ID now lives in a new `Core/ConsumeData.lua` and is matched by ID across all
  ranks.
- **Three more ID bugs fell out of verifying that list against Wowhead.** The
  Undead reminder checked your bags for item 12404 believing it was the
  Consecrated Sharpening Stone — that's the plain Dense stone; the consecrated
  one is 23122, which was sitting in the *regular* stone list. Gift of Arthas
  was tracked by 11374, which is the disease it procs onto whoever hits you,
  not the buff you wear (11371). And four of the seven tracked "hunter foods"
  were the wrong items — three of them plain vendor food that grants no Well
  Fed buff at all, and one (31672) Mok'Nathal Shortribs rather than the Spicy
  Hot Talbuk it was labelled as.
- **Food and pet food both got wider and more accurate.** The food list now
  leads with Ravager Dog (+40 attack power — the actual hunter food, which
  wasn't tracked at all) and includes Spicy Hot Talbuk, Grilled Mudfish,
  Spicy Crawdad and Fisherman's Feast. Pet food now also recognises Sporeling
  Snack alongside Kibler's Bits, so the badge is labelled "Pet food". Your
  pet's food aura is named "Well Fed" exactly like your own, which is one more
  thing name matching could never have separated.
- **New "expiring soon" state.** A buff that's still up but under a
  configurable threshold (default 5 minutes) now surfaces in colour with a
  countdown, instead of staying invisible until it falls off mid-pull. Set the
  threshold to 0 for the old missing-only behavior.
- **The panel is a proper floating panel now.** Drag it while unlocked, nudge
  it a pixel at a time, and it keeps its position per profile. It carries the
  standard Background block (fill + LSM border) and icon size / gap / scale
  sliders. Since it's hidden outside instances and in combat, unlocking shows
  a preview row so there's actually something to grab.
- **New `/nock helpers` diagnostic.** Dumps every gate verdict, each helper's
  status, which tracked buff IDs are on you, and which tracked items are in
  your bags — so a helper that disagrees with reality names its own bug.
  (`Core/ConsumeData.lua`, `Modules/Helpers.lua`, `UI/Frame_Helpers.lua`,
  config; guarded by `Tests/consume_data_test.lua` and
  `Tests/helpers_engine_test.lua`.)

## 1.0.26

- **Free placement is now Classic-only.** The free layout toggle leaked into
  the React look, scattering the React cluster and cooldown strip to stale
  positions and tearing their seam apart. React now always uses its grid;
  saved free positions survive untouched for switching back to Classic. In
  free layout the classic HUD's backdrop box is hidden entirely (it no longer
  eats clicks), and the pet-status, repair and totem panels become
  independently placeable — transient panels hold a preview open while
  unlocked so they can be dragged. Guarded by `Tests/free_layout_test.lua`.

- **"Hide Blizzard's cast bar" toggle** in the shared cast bar settings
  (General → Cast bar and Classic HUD → Cast Bar, off by default). Hides the
  default player cast bar so only Nock's shows. Turning it back off restores
  the default bar live where the client allows; otherwise a chat note asks
  for a /reload. (`Modules/CastBar.lua`, `Config/Options.lua`,
  `Config/Defaults.lua`.)

- **Classic cast bar: padding, background and border settings.** Classic HUD →
  Cast Bar grows a Padding slider (the inset between the panel edge and the
  icon/bar — the panel resizes with it) and the same "Background" block the
  floating panels got: fill color + opacity, LibSharedMedia border style with
  thickness, color and opacity. Defaults reproduce the previous hardcoded
  look. Heads-up in the border tooltip: the panel sits flush against the HUD
  box, so a thick border breaks that seamless join. Guarded by
  `Tests/options_tree_test.lua`. (`UI/Frame_CastBar.lua`,
  `Config/Options.lua`, `Config/Defaults.lua`.)

- **The HUD Background section moved from General to HUD & Bars → Classic
  HUD.** The backdrop box only exists in the classic look (React draws no box
  — its styling is the React → Skin subtab), so its settings now live with
  that look. Same keys, nothing resets; a note on the page points React users
  at Skin.

- **Per-panel background styling for the classic floating panels.** The
  Misdirection tracker, Buff Tracker (both grids), Debuff Tracker, and
  Shopping List each get a "Background" section on their own options tab with
  the same depth as the HUD's Background page: fill color + opacity, and a
  LibSharedMedia border style with thickness, color and opacity. Defaults
  reproduce each panel's previous hardcoded look (the debuff grid stays
  invisible until you style it); the green unlock outline still always wins
  while repositioning. The MD tracker's existing background-opacity setting
  carries over — its border no longer auto-fades with the fill, it has its
  own opacity slider now. Guarded by `Tests/options_tree_test.lua`.
  (`UI/Widgets.lua` `ApplyUserPanelStyle`, the four panel frames,
  `Config/Options.lua` `panelStyleArgs`, `Config/Defaults.lua`.)

- **Experimental: Retry-Timer** (Experimental → Retry-Timer, off by default,
  both HUD looks). A weave-release timing bar glued under the HUD while the
  weave key is held: after `/cast !Auto Shot` the client re-checks on a ~0.5s
  pulse counted from your press (Aerthax's "retry grid", Classic Hunter
  Discord 2022), so a release mid-recharge delays the shot by up to half a
  second — unless it lands on a green free notch (exactly 0.5s/1.0s before
  ready) or anywhere after ready. The bar draws the cost boxes reddening
  toward each notch, the latency-shifted free zone, a sweeping playhead and a
  color-coded "+0.32" cost readout, and dims once a release is free. Height,
  readout and notches are configurable; preview while unlocked. For the
  trial period "Always show (testing)" ships ON — the bar stays on screen
  whenever the Retry-Timer is enabled, even between swings; turn it off for
  hold-only.
- **The Retry-Timer answers "did my !Auto Shot press register?"** — a status
  chip on its left edge: green FIRING while the wind-up runs (the shot is
  committed, nothing can clip it), AUTO ON when auto-repeat is armed (the
  press landed), neutral MELEE while the toggle is off mid-hold (expected —
  /startattack switched you), and a blinking red AUTO OFF when the toggle is
  dead in combat with no hold — the state that loses a whole swing cycle. The
  chip stays visible in always-show mode so a cancelled auto-repeat can't
  hide.
  Driven by START/STOP_AUTOREPEAT_SPELL and the measured wind-up; guarded by
  `Tests/release_arm_test.lua`.
  (`UI/Frame_ReleaseBar.lua`, `Core/State.lua`, `Core/Core.lua`,
  `Core/Constants.lua`, config.)
- **The model is unverified on Anniversary, so it ships with its own gate:**
  `/nock weavelog` (any mode) now prints `release->auto predicted +Xms,
  measured +Yms` for every weave — predicted is the new shared
  `Nock.ReleaseCost` sawtooth, measured is the swing timer's real `autoDelay`
  for that shot. If the pairs track on a dummy, the bar's promise holds; if
  not, the experiment stays off. Guarded by `Tests/release_cost_test.lua`.
  (`Modules/WeaveBind.lua`.)

- **`/nock weavelog report`** — every weavelog line is also captured (with a
  session-relative timestamp, 500-line cap keeping the newest) and the report
  command exports the whole session to the copyable text window with a
  context header (version, eWS, wind-up, latency). Works during or after a
  session; starting a new one resets the buffer. (`Modules/WeaveBind.lua`,
  `Core/Core.lua`, `Tests/weavelog_report_test.lua`.)

## 1.0.25

- **Settings reorganized: HUD & Bars now splits into Classic HUD and React
  HUD.** The active look is marked "(active)" in the list, and the HUD & Bars
  landing page carries the look picker. Where did things go?
  - Layout, Swing Bars, Mana Bar, Range Finder, Cooldown Grid → Classic HUD.
  - Rotation → Classic HUD → Shot Bars (same settings, honest name).
  - The React HUD page is now six subtabs: Size & Elements, Bars, Range Bar,
    Cooldown Grid, Buff Row, Skin.
- **Shared settings now show up in every home that needs them** (same setting,
  multiple doors): the HUD look picker (General, HUD & Bars, React), the weave
  engine tunables (Classic → Shot Bars and React → Bars), non-combat casts
  (General, Classic → Cast Bar, React → Size & Elements), and custom cooldown
  entries (both grid pages — one list, editable from either side).
- **New: Classic HUD → Cast Bar page** — the classic cast-bar settings in one
  place, behavior and styling together.
  (`Config/Options.lua`, `Tests/options_tree_test.lua`.)
- **`/nock diag` now opens in the copyable text window** (like `/nock fonts`)
  instead of printing to chat, so the whole report pastes back in one Ctrl+C.
  (`Core/Core.lua`.)
- **Classic cast bar and swing bars are now styleable.** Classic HUD → Cast
  Bar gains a styling section: bar height (icon and panel resize with it), its
  own LSM texture, fill color, and a spell-icon toggle (off stretches the bar
  full width). Swing Bars gains fill color pickers for the Auto Shot and melee
  bars plus the three clip-tick colors (Steady clip, Multi clip, wind-up
  mark). Defaults reproduce the original look exactly. (`Config/Options.lua`,
  `Config/Defaults.lua`, `UI/Frame_CastBar.lua`, `UI/Frame_SwingTimers.lua`.)
- **Experimental split into sub-pages** — V3 Medallion (icon + countdown
  dial), Sapper Column, Zoomed Weave Bar — one experiment per page instead of
  one scroll. (`Config/Options.lua`, `Tests/options_tree_test.lua`.)
- **Warnings page reorganized into themed sub-pages.** Instead of one endless
  scroll, the sidebar under Warnings now lists Appearance & Preview plus five
  themed pages — You, Pet, Combat, Gear & Binds, Boss — each a short list of
  the familiar warning boxes. Warnings carry their category in the catalog, so
  new ones file themselves (unknown categories land under "Other" rather than
  disappearing). Helpers keeps its short flat list. (`Config/Options.lua`,
  `Modules/Warnings.lua`, `Tests/options_tree_test.lua`.)

## 1.0.24

- **The React Hunter's Mark icon names the hunter who cast it.** With several
  hunters on one boss, "is the mark up" was only half the question — the other
  half is whose it is and whether anyone is going to refresh it. The caster's
  name now sits along the bottom of the icon, under the countdown. Nothing is
  shown when the client won't name the caster (a hunter outside your group, or
  one who has moved out of range), so an unlabelled mark means "unknown", never
  "unowned". No new setting: the corner icons are already opt-in on the React
  HUD tab. (`Modules/Auras.lua`, `UI/Frame_ReactCorners.lua`, `UI/Widgets.lua`,
  `Core/State.lua`.)
- **Steam Tonk settling delay: 0.50s floor, default and minimum.** 0.40s was
  inherited from the community WeakAura, and it is a gamble — it sits close
  enough to the transform landing that one bad frame or latency spike welds you
  in place for the rest of the pull. The slider now stops at 0.50s, that is the
  shipped default, and **existing profiles set below it are raised on login**
  rather than grandfathered. Anything you have set at 0.50s or higher is left
  exactly where it is. (`Core/Constants.lua`, `Core/State.lua`, `Core/Core.lua`,
  `Modules/TonkGuard.lua`, `UI/Frame_TonkDial.lua`, config.)
- **Fixed: the React HUD tab ending at "Bar texture", with every setting below
  it missing.** Nock's texture and font dropdowns were being drawn by a library
  Nock doesn't ship — it only exists if some *other* addon supplies it, at
  whatever version that addon froze, and ElvUI is the one people kept hitting
  this through. Old copies of it error the moment you open a media dropdown,
  and every copy mistook the React Font row's "Reference (built-in)" label for
  a font filename. Either fault aborts the options panel mid-build, and
  everything below the point of failure then silently never appears — which is
  all you could see from the outside. Nock now always draws its own media
  dropdowns, and the "Reference (built-in)" / "Inherit (global)" rows can no
  longer be mistaken for a file, on every dropdown rather than just the one
  that broke. **Your saved settings are untouched — nothing needs re-picking.**
  (`Config/Options.lua`, `UI/AceGUI_LSMDropdown.lua`,
  `Tests/options_lsm_values_test.lua`.)
- **New `/nock diag`.** Reports which widget is drawing the media dropdowns and
  at what version, alongside the AceGUI and LibSharedMedia state. An options
  panel that stops halfway is silent by nature — if it ever happens again, this
  turns the report into one line. (`Core/Core.lua`, `UI/AceGUI_LSMDropdown.lua`.)

## 1.0.23

- **DO NOT RELEASE — the wipe-with-lust banner.** When you lie dead with the
  Sated/Exhaustion debuff still on you (the raid burned Bloodlust/Heroism
  this attempt), the boss-mark centre banner reads DO NOT RELEASE with the
  Sated icon, until you release, get resurrected, or the debuff runs out.
  Same banner, position and size as the Teron/Archimonde alert; boss marks
  keep priority. On by default (it can only ever appear while you're dead
  after a lusted attempt); toggle on the Warnings tab. `/nock norelease`, or
  the "Preview DO NOT RELEASE banner" button in the Warnings tab's Preview
  section, holds the banner open for 5 seconds so it can be placed without
  wiping (the sample-squares demo can't show it — it isn't a square).
  (`Modules/Warnings.lua`, `UI/Frame_BossBanner.lua`, `Core/State.lua`,
  `Core/Core.lua`, `Core/Constants.lua`, config.)
- **Devilsaur Tooth warning (off by default).** For carriers of the Un'Goro
  quest trinket: an amber square when a boss is targeted, the tooth is
  equipped, your pet is alive, and the pet's guaranteed crit (Primal
  Instinct, the buff the trinket's Use loads onto the pet until its next
  crit consumes it) is not up. Deliberately ignores the trinket's 2-minute
  cooldown — the warning means the crit isn't loaded, whether or not you can
  re-pop yet. Enable on the Warnings tab. The tooth also joins the
  wrong-trinket warning's default ID list (pop it pre-pull, swap a real
  trinket in; delist it in the Options box if you deliberately wear it) —
  note AceDB never re-delivers a changed default, so profiles that already
  edited that list keep theirs and must add 19992 by hand.
  (`Modules/Warnings.lua`, `Core/Constants.lua`, config,
  `Tests/wrong_trinket_ids_test.lua`.)
- **React range bar: the centre divider is yours now.** The melee-boundary
  tick in the middle of the React HUD's range bar gets a width slider
  (1-8px) and a colour picker on the React HUD tab → Skin, reference look
  1px white as before. Both participate in "Reset skin to reference look".
  (`UI/Frame_ReactCluster.lua`, config, `Tests/options_tree_test.lua`.)

## 1.0.22

- **Zoomed weave bar (experimental, idea by Erda).** New toggle on the
  Experimental tab (off by default; applies to the classic Range Finder and
  the React range bar alike). It crops the glide view: the outer part of each
  side is shaven off and the middle stretched across the full bar — same
  layout, same centered melee-boundary tick, but every step moves the bar
  further, so it reads faster and more directly. A zoom-level slider picks
  the magnification (1.5x-8x, default 2x = 25% shaven per side; 4x shows only
  the middle quarter). Beyond the zoom window the fill pegs empty/full. The
  40-8yd finding ladder is unchanged. One shared mapping in the range engine
  (`Nock.RangeEngine.ZoomFill`), LuaJIT-tested.
  (`Modules/RangeEngine.lua`, `UI/Frame_RangeFinder.lua`,
  `UI/Frame_ReactCluster.lua`, config, `Tests/range_engine_test.lua`.)

## 1.0.21

- **The Misdirection panel: charges, background, title.** Three additions,
  all defaulting to the current look:
  - **Remaining MD charges (3→1) on the active row's icon**, buff-stack
    style. The tracker was already reading the caster's Misdirection buff to
    detect the early three-shots fade — it now keeps the stack count it used
    to throw away. Only readable for grouped hunters the roster can inspect;
    when the client reports no count, no number renders.
  - **Background opacity slider** (Misdirection tab → Panel). Default 0.85 =
    the shared panel backdrop, exactly as today; the panel's outer border
    fades with it, so 0 leaves only the rows — no floating black outline. The
    green unlock border stays full-strength (you still need to find the panel
    to drag it). The old auto-pulse stays gone — this is a static,
    user-chosen alpha.
  - **"MISDIRECTION title" toggle.** Off hides the header and gives its
    height back to the panel; safe to flip in combat (the resize defers to
    the next out-of-combat tick, like every other MD geometry change).
  (`Modules/Misdirection.lua`, `UI/Frame_Misdirect.lua`, `Core/State.lua`,
  config.)
- **Rotation labels can carry a custom color.** The Rotation tab's rename
  section gains a color swatch per notation (teal "French", anyone?), applied
  everywhere the label renders — the React notation, the classic Auto Shot
  bar and the Shot Bars — always keyed on the built-in notation, so renames
  and colors compose. "Reset all colors" returns every site to its own
  default. (`Rotations/Profiles.lua` `DisplayColor`, the three label views,
  `Modules/ShotPredictor.lua`, config, `Tests/profiles_display_test.lua`.)
- **The React mana bar text is configurable.** React HUD tab → "Mana bar
  text": percent (the reference look, default), the actual value, both, or
  nothing — same formatter the classic mana bar uses.
  (`UI/Frame_ReactCluster.lua`, `UI/Widgets.lua` shared `FormatManaText`,
  `Tests/mana_format_test.lua`.)
- **The React HUD accepts your bar texture, font and font size.** React HUD
  tab → Skin gains React-scoped "Bar texture" and "Font" pickers
  (LibSharedMedia) plus a "Font size" slider (reference 9; all React text
  shifts together, keeping its proportions), everything defaulting to the
  fixed reference skin, exactly as before. They restyle the cluster fills, the glued cast bar, and the buff-row
  and corner-icon text; the chosen font also takes over the cooldown grid,
  which follows the classic HUD's global Font while the picker sits on
  Reference (that was the one React text that already obeyed the global
  option — the inconsistency is now a rule). Separate from the classic HUD's
  global Bar texture / Font on purpose; "Reset skin" restores Reference.
  (`UI/Widgets.lua`, `UI/Frame_ReactCluster.lua`, `UI/Frame_ReactCastBar.lua`,
  `UI/Frame_ReactBuffs.lua`, `UI/Frame_ReactCooldowns.lua`, config.)
- **The React cluster's bars can be re-ordered.** React HUD tab → Bar order:
  Up/Down per bar (Auto Shot / melee / range / mana), reset restores the
  reference stack. The cast bar keeps gluing to whatever ends up on top, the
  buff row above that; hidden bars keep costing zero height. Stored order
  self-heals through a sanitizer, so a damaged profile value can't wedge the
  layout. (`UI/Frame_ReactCluster.lua`, `UI/Widgets.lua`, `Config/Options.lua`,
  `Tests/react_order_test.lua`.)
- **The React corner icons (Aspect / Hunter's Mark) are movable in
  `/nock unlock`.** Drag one wherever you like, or click it for the nudge pad;
  the border turns green while unlocked to say it's grabbable. Positions are
  saved per icon and stay cluster-relative, so a moved icon still follows the
  HUD, scales with it, and vanishes in classic mode. The pad's reset re-welds
  the icon to its mirrored corner (the X/Y sliders keep driving un-moved
  icons). (`UI/Frame_ReactCorners.lua`, `Config/Defaults.lua`.)
- **The React proc row previews itself in `/nock unlock`.** The row is
  invisible whenever nothing procs — exactly when you're laying out the HUD —
  so while unlocked it now shows three placeholder procs (Rapid Fire, Quick
  Shots, Bloodlust) inside a green frame marking its footprint.
  (`UI/Frame_ReactBuffs.lua`.)
- **The turret rotation label now understands haste procs.** It used to be a
  raw effective-weapon-speed bracket lookup, which the 12-second Improved Hawk
  proc often fails to move across a bracket edge — at base eWS 2.17 the proc
  only reaches 1.89, still inside "5:5:1:1", so "5:6:1:1" never appeared (and
  on slightly slower gear it appeared by accident). The resolver now divides
  the known proc multipliers (Quick Shots ×1.15, Rapid Fire ×1.40,
  Bloodlust/Heroism ×1.30) back out to find your STATIC tier, and on
  no-static-haste gear answers from the rotationtools proc ladder: Hawk proc →
  "5:6:1:1" (Long French), Rapid Fire + Hawk or + Bloodlust → "5:9:1:1"
  (Skipping), all of it stacked → "2:5". Without a proc up nothing changes,
  and your custom label names apply to the proc labels like any other.
  (`Rotations/Profiles.lua`, `Core/Core.lua`, `Tests/turret_resolver_test.lua`.)
- **Bestial Wrath now shows in the React proc row.** The buff lives on the
  pet, not the player (the player only carries an aura when talented The Beast
  Within), and the pet scan matched three utility names by localized name only —
  Bestial Wrath is now matched on the pet by exact spell ID (19574), so Big Red
  pops an icon with its duration like any other proc.
  (`UI/Frame_ReactBuffs.lua`.)
- **PvP trinkets now trigger the "Wrong trinket equipped" warning out of the
  box.** The warning only checked the editable ID list, whose seed was Riding
  Crop and Carrot on a Stick — the PvP insignias the help text advertised were
  never in it. Every TBC-era PvP escape trinket (Insignia and Medallion of the
  Alliance/Horde, all 28 class/faction variants, Wowhead-verified) now ships as
  a built-in family that is unioned with your list, so it also reaches profiles
  whose ID list was edited before this fix. Your own additions keep working
  unchanged. (`Core/Constants.lua`, `Modules/Warnings.lua`,
  `Tests/wrong_trinket_ids_test.lua`.)
- **Archimonde's Air Burst joins the Feign Death banner, and the warning is now
  "Boss mark" rather than Teron's alone.** The 1.7-second cast (spell 32014)
  ends in a knockback, and it is the landing that kills you — Feign Death saves
  it. Same banner, same position, same cue as Teron's Shadow of Death: one
  warning that fires whenever a boss aims its single-target mark at you.
  - **Archimonde's fallback is gated on the cast; Teron's still isn't, and that
    difference is the point.** Teron stands still and marks one person, so
    "he is looking at me" is evidence on its own — gating it behind
    `SPELL_CAST_START` would make it useless in exactly the case it exists for
    (a client that logs no destination). Archimonde is tanked, and fear and
    doomfires move his target all fight, so his check only counts while an Air
    Burst is actually in flight. He is confirmed by NPC id (17968) out of a
    nameplate or your target, same as Teron (22871).
  - With Feign Death on cooldown the banner reads `AIR BURST - NO FD`, so the
    two mechanics stay distinguishable at the moment you can't answer either.
  - **Each boss has its own on/off switch** under Warnings → Boss mark; they
    share the banner, its size and position, and the sound.
  - `/nock bossmark` now dumps both encounters — what the last cast of each
    spell carried and what the unit lookup can see. `/nock bossmark test`
    previews it, and `/nock bossmark test archimonde` picks the encounter.
    `/nock teron` still works.
  - **Your 1.0.20 settings carry over.** The profile keys were renamed
    (`warnTeronMarkEnabled` → `warnBossMarkEnabled`, and the banner's size,
    position and sound with them); a one-shot migration copies the stored values
    forward, so a banner you have already dragged into place stays there.
  (`Modules/BossMarkEngine.lua`, `Modules/BossMarkWatch.lua`,
  `UI/Frame_BossBanner.lua` — all renamed from their `Teron*` originals —
  `Modules/Warnings.lua`, `Core/State.lua`, `Core/Core.lua`,
  `Core/Constants.lua`, `Config/Defaults.lua`, `Nock.toc`,
  `Tests/boss_mark_engine_test.lua`.)
- Neither encounter has been seen by this code yet, which is why both detection
  paths ship for both bosses and why the diagnostic exists.
- Thanks to **Erda, Haanpaa and Predern** for the bug reports and feature
  requests behind this round — the proc-row and rotation-label fixes, the
  React styling asks and the Misdirection panel tweaks all came from their
  feedback.

## 1.0.20

- **Teron Gorefiend: a full-screen FEIGN DEATH NOW when Shadow of Death is
  aimed at you.** Feign Death *during* the 1.5-second cast makes it fail
  outright — you never take the debuff, never become a ghost, and he doesn't try
  again for ~30 seconds. The window is short enough that a 44px square in a row
  of twelve is no use, so this alert gets its own large banner at screen centre
  and is the only cue in Nock that defaults to audible.
  - **Two independent detections.** The combat log naming you as the target of
    Shadow of Death (spell 40251) is the certain one. As a fallback, Nock also
    watches whether Teron's own unit target is you — found by NPC id (22871)
    from his nameplate or your target, so no other boss can raise it. The
    fallback is deliberately *not* gated behind the cast event; if this client
    logs no target for that cast, gating it there would leave you with nothing.
  - **A cast the log says is aimed at someone else silences the fallback** for
    the length of that cast, so you are not warned on all five casts.
  - Feign Death on cooldown? The banner reads `MARKED - NO FD` instead — it will
    not tell you to press something you can't.
  - Drag it while frames are unlocked (it holds itself open there, so a banner
    that only exists for two seconds can still be placed), or nudge it with the
    pad. `/nock teron test` previews the banner and the sound.
  - The cue defaults to **Air Horn**, which comes from DBM's or BigWigs' media
    library — Nock ships no audio. Without one of those installed it falls back
    to the client's raid-warning sound rather than warning you silently.
  (`Modules/TeronEngine.lua` (new), `Modules/TeronWatch.lua` (new),
  `UI/Frame_TeronBanner.lua` (new), `Modules/Warnings.lua`, `Core/State.lua`,
  `Core/Constants.lua`, `Config/Defaults.lua`, `Tests/teron_engine_test.lua` (new).)
- **The Steam Tonk now steps you out in combat too — the thing 1.0.18 said was
  impossible.** Use the tonk from any button you like, on its own, with no
  `/cancelaura` anywhere near it. Nock gets you out a settling delay later,
  whether or not you are in a fight.
  - **Credit for the mechanism goes to Big Chungus in the Classic Hunter
    Discord.** The tonk is a *charmed creature*, not a buff you happen to be
    wearing — which is why `Call Pet` refuses with "You already control a
    charmed creature" while you are in it. Dismiss the creature and the
    transform goes with it, and pet control, unlike every aura-cancel function
    on this client, is not blocked in combat. 1.0.18 established the charm and
    then spent its whole investigation attacking the *aura*, concluded (truly)
    that no addon can cancel an aura in combat, and quietly promoted that into
    the false claim that nothing could exit the tonk in combat.
  - **The hold key is gone**, and so is the HOLD / RELEASE cue. Both existed
    only because a human finger was the sole available source of the delay. If
    you had the key enabled, it releases back to whatever you had bound before,
    exactly as disabling it always did. A plain two-line macro (`/use [nopet]
    Call Pet` then `/cast [pet]Steam Tonk Controller`) does the press half if
    you want it.
  - **A countdown dial replaces the cue**: the tonk's own icon with a radial
    sweep running down to the moment you step out, so it is never a surprise.
    Movable and resizable like every other Nock frame, and it can be turned off
    without changing anything about the exit itself.
  - The Settings page lost two thirds of its controls along with the key: a
    switch, the settling delay, and the dial.
  - `/nock tonk` no longer refuses in combat, because there is nothing left for
    it to refuse.
  (`Modules/TonkGuard.lua`, `UI/Frame_TonkDial.lua`, `Modules/TonkBind.lua` and
  `UI/Frame_TonkCue.lua` removed, `Modules/BindCheck.lua`, `Modules/Warnings.lua`,
  `Modules/Onboarding.lua`, `Core/Core.lua`, `Core/State.lua`,
  `UI/AceGUI_BarLegends.lua`, `Config/Defaults.lua`, `Config/Options.lua`,
  `Tests/bind_conflict_test.lua`, `Tests/onboarding_test.lua`.)
- **The Snowball poke and its garment gate are now switches, in the wizard and
  in the settings.** They were always just lines in the weave macro; now you
  don't have to know that to use them.
  - **A new "The Snowball trick" step in the setup wizard**, right after the
    macro-shape cards, explaining *why* the poke is there: a Snowball is free
    and off the global cooldown, so throwing one as you step in forces the
    server to update where you are standing — and the white auto-attack you
    weaved for lands instead of being eaten as out of range.
  - **"Only for bosses" gates the poke behind your shirt or tabard**, so trash
    pulls and questing don't burn the stack. Shirt or tabard, and either
    direction (fires while it's off — the shipped convention — or while it's
    on). Only the poke is gated: Raptor Strike and `/startattack` always fire.
  - **The same four switches sit above the macro boxes in Weave Bind.** They
    read their position out of the stored macro text and write straight back to
    it, so hand-editing the box moves the switches and vice versa — there is no
    second copy of the setting to drift.
  - Picking "Default" on the macro-shapes page now keeps your poke and gate
    answers and strips only the auto-backpedal line, so the two pages can't
    undo each other.
  - **Wizard switch rows now grow to fit their explanation.** They advanced by a
    fixed height, which only ever looked right because every description so far
    happened to fit one line; a longer one ran under the next row's label.
  (`Core/WeaveMacro.lua` (new), `Modules/Onboarding.lua`, `UI/Frame_Onboarding.lua`,
  `Config/Options.lua`, `Core/Constants.lua`, `Tests/weave_macro_test.lua` (new).)

## 1.0.19

- **The Misdirection panel can now track Sapper Charges too, and call out the
  MD + Sapper opener.** Experimental and off by default — turn it on under
  Experimental → Sapper column.
  - **A sapper square on every row**, tanks and hunters alike, next to the
    existing icon. Your own square is read from the item itself, so it is
    exact. Everyone else's is combat-log evidence: a square only lights up once
    you have actually *seen* that person use one, and someone who saps out of
    log range — or before you zoned in — reads as ready when they are not. A
    dim square means "no evidence they're an engineer", not "ready". Goblin and
    Super Sapper Charge share one 5-minute cooldown, and the square knows it.
  - **The opener gets announced to raid chat** — `Sapper + MD -> Tank` — when a
    sapper goes off inside that hunter's own 30-second Misdirection window. A
    sapper with no MD behind it says nothing. By default it announces for every
    hunter in the group, which means a raid with three Nock users posts the
    line three times; switch to "Only me" if that gets noisy.
  - **An orange speaker button on each hunter row** calls that hunter out as
    next up in the MD + Sapper rotation, for running the opener as a set order.
  - The two extra columns cost row width. At the default 200px the name gets
    cramped — widen it under Trackers → Misdirection → Row width.
  (`Modules/SapperTracker.lua`, `UI/Frame_Misdirect.lua`, `Modules/Misdirection.lua`,
  `Core/Constants.lua`, `Config/Options.lua`, `Tests/sapper_test.lua`.)
- **The Steam Tonk hold key's two macros are now editable in Settings.** The
  press and release edges each run a macro body, and until now those were fixed
  — you could pick the key but not change what it did. Both are now text boxes
  under Utility → Steam Tonk, with a reset button back to the tested pair. Nock
  refuses a `/cancelaura` on the *press* edge, since that is the same-frame
  cancel that welds you in the first place, and the release box explains why its
  `[combat]` gate matters: out of combat the automatic cancel already owns the
  exit, and letting both fire is its own way to get stuck. Edits made mid-fight
  are stored and applied the moment combat ends — the client locks the secure
  attributes a bound key uses. (`Config/Options.lua`.)
- **The clip-zone safety margin is gone.** The slider and its three presets
  ("Cautious", "Some slack", "None") let you pad the clip tick with extra
  leeway, and every non-zero value moved the tick *away* from the truth: since
  1.0.17 the tick already includes the Auto Shot wind-up as a real term measured
  from your own shots, which is the only thing the margin was ever standing in
  for. The ticks are now cast time + measured wind-up + your latency, full stop,
  and a value left over in an existing profile is cleared on login rather than
  quietly skewing the bars. (`Config/Options.lua`, `Core/State.lua`,
  `Modules/ShotPredictor.lua`, `Core/Core.lua`, `Config/Defaults.lua`.)
- **Misdirection tracking is lighter and no longer silently switchable off.**
  It used to skip its combat-log work entirely when the panel was hidden, which
  would have killed the sapper announce for anyone with the tracker section
  off, and it rebuilt a table per hunter on every frame. It now publishes
  regardless of what is on screen, at 10Hz instead of every frame, reusing its
  rows. (`Modules/Misdirection.lua`.)

## 1.0.18

- **Nock now tells you when one of its keybinds has taken over a key you were
  already using.** The Weave Bind and the Steam Tonk hold key both claim their
  key as a *priority override*, which means Nock silently wins it: whatever was
  on that key — an action-bar spell, a macro, another addon's button, a normal
  game binding — just stops happening for as long as the feature is on, and
  comes back the moment you disable it or clear the key. Nothing said so.
  - **Under each key picker in Settings**, a live line now names what the key
    currently does, or confirms in green that it is free.
  - **A warning square out of combat** when an enabled bind is sitting on a key
    that actually does something, naming the Nock key and showing the icon of
    the action being suppressed. A key bound to an *empty* action-bar slot costs
    you nothing and never raises it. Out of combat only — bindings are locked
    mid-fight, so there is nothing to do about it then. Turn it off under
    Alerts → Warnings.
  - **Both Nock keys set to the same key is now caught** and flagged red. Only
    one of the two can own it and the other silently does nothing at all;
    nothing detected that before.
  - Nock still never edits your bindings. It only looks and reports.
  - `/nock binds` prints what each key resolves to.
  (`Modules/BindCheck.lua`, `Modules/Warnings.lua`, `Config/Options.lua`,
  `Core/State.lua`, `Core/Core.lua`, `Tests/bind_conflict_test.lua`.)
- **The Lust warning no longer tells you to pop a trinket you can't pop.** With
  a passive proc trinket equipped — Dragonspine Trophy, Tsunami Talisman — the
  "Pop RF+T1+T2" nag named its slot anyway: an equipped trinket with no
  cooldown to report reads as permanently ready, and the check only asked
  whether *something* was in the slot. It now asks whether that something has a
  **Use:** effect, so a proc trinket is left out of both the warning text and
  the spoken trinket-chain cue. `/nock trinkets` prints what each slot resolved
  to. (`Modules/Cooldowns.lua`, `Modules/Warnings.lua`, `Core/Core.lua`,
  `Tests/trinket_onuse_test.lua`.)
- **The Steam Tonk no longer gets you stuck.** Hunters use the Steam Tonk
  Controller to save a pet from a boss mechanic — transforming dismisses it, and
  stepping out lets you re-summon at full health with Call Pet. The obvious
  one-button macro cancels the transform in the same frame it requests it and
  the client regularly ends up welded: unable to move or cast until combat ends.
  It turns out the cancel is sent *before* the cast is even transmitted, so it
  is out of order rather than merely early. **Delete any
  `/cancelaura Steam Tonk Controller` line from your tonk macro.**
  - **Out of combat Nock cancels it for you**, 0.40s after it lands, and frees
    you the moment combat ends if you tonked mid-fight.
  - **In combat it can't** — this client blocks addons from cancelling auras
    there, and no amount of cleverness gets around it. So there's an optional
    **hold key**: press casts the tonk, release cancels it, and your hold is the
    delay. Off by default; set it under **Utilities → Steam Tonk**.
  - **A HOLD / RELEASE cue** in the middle of the screen shows when letting go
    is safe — amber while it would weld you, green once it won't. Combat only,
    and it drags and resizes like every other Nock frame.
  - A very fast release can still weld you and nothing can prevent that: secure
    code has no clock, so nothing is able to measure your hold and refuse it.
    The cue is the mitigation.
  - `/nock tonkdebug` traces the whole cycle if you ever need to report one.
  (`Modules/TonkGuard.lua`, `Modules/TonkEngine.lua`, `Modules/TonkBind.lua`,
  `UI/Frame_TonkCue.lua`, `Modules/Auras.lua`, config, onboarding.)
- **Nudge pads for placing frames exactly.** Unlock the HUD and click any
  movable Nock frame — the HUD box, a free-layout row, the medallion,
  misdirection panel, buff or debuff tracker, totem tracker or shopping list —
  and a small four-way pad appears beside it. Clicking a different frame moves
  the pad to that one, so only ever one pad is on screen.
  One click moves the frame a unit; shift-click moves
  ten; hold an arrow to repeat. The centre button resets that frame to its
  default position, and hovering the pad reads out the frame's current x/y, so
  two panels can be aligned to matching numbers instead of by eye. Dragging is
  unchanged. Free-layout rows only get a pad in free layout — in grid mode the
  cascading layout owns their position. The misdirection panel can't be moved
  during combat (it parents secure click-cast buttons); its pad says so.
- **The cast bar can be placed on its own in free layout.** It used to be welded
  to the HUD box's top edge by two anchors, which is what made it stretch to the
  box width and read as one piece with it — so it moved only when the box did.
  In free placement it now drags and nudges independently, at a fixed width.
  Grid mode is untouched: the bar stays welded there, as before. Nothing moves
  until you move it, and **Reset element positions** (or the pad's reset button)
  welds it back. While you are unlocked in free placement the bar stays on
  screen showing a placeholder, since it is otherwise visible only mid-cast —
  there would be nothing to grab.
- **Lock / Unlock HUD buttons on the Layout page.** The same global lock as
  General → Lock all frames, put on the page you are actually on while placing
  things.
- **React HUD: optional aspect and Hunter's Mark corner icons.** Parity with the
  reference WeakAura, which flanks its cluster with the active aspect (top-left)
  and Hunter's Mark (top-right). Both are purely informational — no glow, no
  pulse — and both ship **off**: Nock's Aspect warning already covers the first,
  in combat only and at center screen. Toggles live on the React HUD tab under
  Elements, with size and offset sliders under Skin; the setup wizard offers
  them once on a React run, badged NOT RECOMMENDED. (`UI/Frame_ReactCorners.lua`,
  `UI/Widgets.lua`, `UI/Frame_ReactBuffs.lua`, `Modules/Onboarding.lua`,
  `UI/Frame_Onboarding.lua`, config.)

## 1.0.17

- **The Shot Bars melee weave lane is resizable.** A new **Melee lane height
  (px)** slider sits under the existing bar-height slider (Rotation → Shot
  timing bars). The weave strip used to be a fixed 4px no matter how tall you
  made the bar — every extra pixel went to the ranged lane — which left the
  two-tone green/white weave state hard to read. Its pixels come out of the
  ranged lane, so the overall bar height never changes and nothing below it on
  the HUD moves. Defaults to 4, so your bar looks exactly as it did. The legacy
  Shot Bars keep their proportional split and ignore the slider.
- **The rotation text label works on the simplified Shot Bars again.** The
  **Rotation text label** toggle only ever did anything on the legacy bar — the
  simplified bar dropped the notation unconditionally, a leftover from when it
  was an off-by-default experiment, so the toggle sat there enabled and inert
  once simplified became the default. The toggle now decides in both modes; if
  you preferred the geometry-only look, switch it off.
- **One lock for everything.** The per-panel lock toggles (Misdirection, buff
  and debuff trackers, shopping list) are gone; a **Lock all frames** /
  **Unlock all frames** button pair at the top of General — and `/nock lock` /
  `/nock unlock` — now locks or unlocks every movable Nock frame at once,
  including the medallion and free-layout rows. The button matching your
  current state is greyed out, so the pair doubles as the state readout and
  never shifts under your cursor. If you had left some frames unlocked, they start locked after this
  update: one `/nock unlock` frees everything again. Switching profiles now
  also re-applies every panel's position and lock state immediately (previously
  they kept the old profile's placement until a `/reload`).
- **The setup wizard handles locking for you.** Frames unlock the moment the
  wizard opens, so you can drag everything into place while previewing; closing
  it any way (the **Lock & finish** button, Skip, X or Esc) locks them again.
  The wizard can now also be re-run from **General → Run setup wizard** — the
  button its finish page always promised.
- **Boss Garment gets its own settings section.** The shirt/tabard autopilot
  toggles moved out of Weave Bind into a dedicated section (same settings, new
  home) with a proper explanation of how the macro conditionals drive it.
- **The settings tree is reorganised into families.** Instead of 19 flat tabs,
  the sidebar now reads General / HUD & Bars / Alerts / Trackers / Utilities /
  Experimental / Profiles, with each feature one level down. General now uses
  subtabs (HUD look / Visibility / Background / Cast bar / Media / Setup
  Check) with the lock, wizard, scale and reset controls always visible above
  them; Layout and Rotation are regrouped into titled sections instead of one
  long scroll. Every setting kept its place in the profile — nothing to
  reconfigure.
- **Fixed: the Auto Shot cast bar emptied before the arrow left.** It was
  guessing how long the wind-up lasts from a formula with a hardcoded +15%
  quiver factor baked in, and the guess came out short — so the bar hit zero
  while the shot was still in the air. It no longer guesses: it asks the swing
  timer when the shot actually fires and runs to that moment, which lands within
  ~15ms of the arrow at any haste. (In-game measurement also settled what the
  wind-up really is: not the flat 0.5s everyone assumed, but 0.5s at *base*
  weapon speed, shortening with haste — 0.37s unbuffed down to 0.23s with Rapid
  Fire and Quick Shots up.) The bar also clears on the real release instead of
  lingering, and can no longer inherit another cast's timing when the wind-up
  begins while something else is in flight.
- **New: a wind-up mark on the auto-shot bars.** A neutral mark on both the
  classic swing bar and the React converge bar showing where the next Auto Shot
  *commits* — the point its wind-up begins. That wind-up sits **inside** the
  weapon-speed cycle, so the shot is locked in before the bar reaches 100%,
  which is why the cast bar looks like it fires early. It doesn't; the bar just
  runs one wind-up past the commit point. The mark's position is measured from
  your own shots rather than assumed, so it stays correct under Rapid Fire and
  on any bow. Toggle in **Rotation → Clip-zone ticks**. It's a landmark only and
  changes no clip verdict.
- **Shot bars use the real wind-up length.** The Steady-vs-Auto equilibrium that
  sizes the orange window was assuming a flat 0.5s wind-up; it now uses the
  measured, haste-aware value, so the windows are sized correctly during Rapid
  Fire instead of being pulled ~0.24s too far left.
- **Fixed: the clip warnings were telling you it was safe to cast when it
  wasn't.** Two errors, both pointing the same way. The clip zone was measured
  against the moment the arrow *leaves*, but the shot is locked in one wind-up
  earlier — so a cast that finished "just in time" still delayed it. And the
  modelled Steady cast time had a +15% quiver factor applied to it, which speeds
  up your swing but does nothing to a cast, making Steady look ~15% faster than
  it is. Together the red tick sat about **half a second too permissive**, and
  the rotation engine was recommending Steady inside that window. Multi-Shot was
  worse still — its cast time was never haste-adjusted at all. All fixed, and
  the clip deadline now has a single shared definition used by the rotation
  engine, both swing bars and the shot bars, so they can't drift apart again.
  Expect the red and orange ticks to sit noticeably earlier than before; that is
  the correction, not a bug. If a cast can't fit the cycle at all (common at
  high haste), the tick now pins to the start of the bar instead of vanishing.
- **Clip risk is now treated as a band, not a tail — Nock will stop nagging you
  during the queue window.** Press a shot in the last moments before the arrow
  leaves and the game holds it for you: the cast starts right after the shot and
  costs nothing. Nock used to flag that whole stretch as a clip, which is
  precisely the window an experienced hunter weaves into. The danger is only the
  band between the red tick and the wind-up mark — early enough that your cast is
  still in flight when the shot wants to go, but not late enough to be queued.
  Outside that band, in both directions, you are fine. Verified on a dummy: casts
  overlapping the wind-up delayed the shot by almost exactly the overlap, while
  presses inside the wind-up produced no delay at all.
- **The Weave Bind page opens on the controls, not on the manual.** The five
  paragraphs of explanation that used to sit at the top pushed the key box and
  both macro fields below the fold. They are now compacted into a **How it
  works** section underneath the macros — same information, roughly half the
  words, with the Snowball line, the backpedal option, the garment gates and the
  key-edge handling each called out on its own instead of buried in prose. Only
  the *Experimental* flag stays at the top.
- **The weave coach's sound cues are retired.** The whole **Weave coach**
  section — the header, the master toggle and both sound pickers — is gone from
  the Weave Bind page, and the cues are switched off once on update, so a
  profile that had a sound picked doesn't keep playing it with no switch left to
  reach. The setup wizard's weaver card no longer arms them either. The coach
  itself is untouched: the Range Finder bar still walks you through GO IN →
  HOLD → BACK OUT → RELEASE, and that explanation moved up into **How it
  works**. Your chosen sound names are still stored, so nothing is lost if the
  cues come back.
- **The settings now explain both Auto Shot bars with a picture.** Rotation → Shot
  timing bars opens with a labelled miniature of the bar itself: each colour
  drawn in your own configured shade, with pointers to the two breakpoints
  ("clip starts", "queue opens") and the shot. React HUD → Auto Shot bar gets the
  same treatment for the converge bar, showing where the Steady and Multi clip
  ticks and the wind-up mark sit relative to the closing halves. Rather than
  reading a colour list and mapping it onto a moving bar, you can see which
  stretch is which.
- **The shot bars now show the clip band as its own thing, and go green when it's
  safe to press.** The red block is the band — start a cast anywhere in it and it
  will still be in flight when the shot wants to go, which is the one place a cast
  actually costs you. The dim orange stretch after it is the queue window, and it
  **turns green the moment the wind-up starts**: green means press whatever you
  like right now, it's held and fires the instant the arrow leaves. Previously
  that stretch was drawn in the same bright orange as the ordinary Steady window,
  which made two very different things look identical. Both shades are
  configurable in Rotation → Shot timing bars. Note the white vertical line is the
  shot itself, not a warning.
- **Fixed: the shot timing bars went blank just before every shot.** The bars
  hide anything you can't press yet, and they were counting the Auto Shot
  wind-up as one of those things — so they dropped out for the last fraction of
  every cycle, which is exactly the moment you're looking at them. The wind-up
  doesn't stop you pressing anything (that's the queue window), so it no longer
  counts. Same fix applied to the medallion's lockout sweep and the mana
  suggestion, which were suppressed for the same wrong reason.
- **Clip safety margin re-baselined.** Now that the wind-up is accounted for
  properly, the margin is purely extra leeway for unstable latency rather than a
  manual stand-in for it. `0.0` is still the default and now genuinely means "no
  leeway". The old Safe (0.5s) and Balanced (0.25s) presets became Cautious
  (0.3s) and Some slack (0.15s); if you had either of the old presets selected
  it is reset to 0 once on upgrade, since keeping it would double-count the
  wind-up. A hand-tuned value that wasn't one of those two is left alone.

## 1.0.16

- **New: a setup wizard for first-time users.** A fresh install now opens a
  short, one-question-at-a-time wizard a few seconds after you log in (Hunters
  only, once per account, and it waits for you to leave combat). Every page
  drives the *real* HUD as you answer, so you pick your setup by watching it
  change rather than by reading a settings tree: choosing React swaps the
  cluster live, the shot-display cards swap the actual bars, the warnings page
  shows real sample alerts, and flipping a tracker on makes its panel appear.
  Choices apply the moment you make them — closing or skipping keeps
  everything you picked, and only the previews are cleaned up. It covers the
  client settings Nock can fix for you (with one-click fixes), HUD style, shot
  display, whether you melee weave, the headline warnings, the raid trackers,
  and the out-of-combat helpers, then finishes with a summary of what you
  chose. The Misdirection tracker and its click-to-MD tank buttons are now
  recommended on for new users; if you turn them off, re-running the wizard
  respects that. Run it again any time with `/nock setup`.
- **The wizard adapts to your answers.** The shot-display step is skipped when
  it can't apply — in React mode (React has its own fixed display and ignores
  those settings) and when you've turned the HUD off — and weavers get an extra
  step for the weave-key macros with three starting points: **Default** (Nock's
  tested press/release pair), **Clever** (the same plus
  `/click MovePadBackward`, so you auto-backpedal for exactly as long as you
  hold the key — Nock loads the Movement Pad for you and warns if your client
  can't provide it), and **Natty** (both macros emptied so you can write your
  own). A macro you have hand-edited yourself is never overwritten. Depending
  on your answers the run is 7 to 9 steps.
- **New: run Nock without a HUD.** The HUD style step gains a third choice,
  **No HUD**, and Layout gains a matching "Show the HUD" toggle. It hides the
  HUD box and everything in it — swing bars, shot display, cooldown grid, range
  finder, mana bar, info row, and the pet and repair panels glued to it — while
  leaving every free-floating feature running: warnings, the Misdirection /
  buff / debuff trackers, the helpers panel, the shopping list and the mailbox.
  For anyone who wants Nock's alerts and raid tools without a bar cluster on
  screen. Picking Classic or React again brings the HUD straight back.

## 1.0.15

- **New: Mailbox module — snowball logistics.** Thousands of raid snowballs
  living in mailbox mails no longer need manual shuffling before the 30-day
  expiry. At any mailbox, a panel under the mail frame (plus `/nock mail`)
  shows how many snowball mails / snowballs you have and when the earliest
  expires (red when under 5 days), and offers three one-click runs:
  **Return All** bounces every returnable snowball mail back to its sender,
  **Send All** loots snowball mails into your bags and auto-mails them
  (12 stacks = 240 per mail) to a chosen character — driving the default
  mail UI visibly, tab flips and all — and **Bags Only** ships just what's
  already in your bags without touching the inbox (for re-sending after an
  earlier loot). The panel also counts snowballs sitting in your bags. Recipients are an account-wide list (Options → Mailbox)
  with a per-character session pick, so the banker sends to the hunter and
  vice versa; a keep-in-bags amount reserves raid supply. Mail bounced to you
  once can't be returned again (it dies for good on its second expiry) — the
  panel counts those "bounce-dead" mails, and the Send run is the way to
  refresh them. COD and non-snowball mail is never touched. The module (and
  only it) also runs on non-Hunter characters, so a banker alt can work the
  other leg of the cycle. (`Modules/Mailbox.lua`, `UI/Frame_Mailbox.lua`,
  Options → Mailbox, `/nock mail report | send [name] | sendbags [name] | return | stop`.)
- **Aspect warning: optional raid-only gate.** The "Wrong aspect (not Hawk)"
  warning gets an "Only inside a raid instance" checkbox (off by default),
  matching the Pet Growl / Wrong Trinket gates: tick it and the nag stays
  silent everywhere but raid instances — open world, dungeons, battlegrounds
  and arenas included. (Options → Warnings → Wrong aspect,
  `warnAspectRaidOnly`.)

## 1.0.14

- **Fix: the React cast bar now shows the Auto Shot wind-up by default.** The
  0.5s wind-up was gated behind the General tab's off-by-default "Show Auto
  Shot in cast bar" toggle, so fresh profiles never saw it on the React HUD.
  React mode now has its own toggle — React HUD tab → Elements → "Auto Shot
  wind-up on cast bar" — which is **on** by default. The classic HUD keeps the
  existing General-tab opt-in (its swing timer covers Auto Shot there).
- **The simplified Shot Bars are now the default look.** The V3 bar from the
  Experimental tab — tall ranged lane, a dark GCD/cast shade sweeping from
  the fire edge (anything under it is unreachable), a hard red
  clip-breakpoint tick, the melee lane as a slim timeline strip — graduates
  to the baseline. The previous multi-lane look is one toggle away:
  Rotation tab → **"Use legacy Shot Bars"**. `/nock v3` now toggles just the
  (still experimental) next-action medallion.
- **New: a React HUD settings tab.** Every React-mode setting now lives in one
  place (between Layout and Warnings) instead of being split across General
  and the bottom of Cooldown Grid — and the tab adds real configurability
  while keeping the reference skin as the default look:
  - **Elements**: show/hide each piece (Auto Shot / melee / range / mana /
    cast bar, cooldown grid, buff row) with React-specific toggles. These no
    longer share the classic Layout → Rows settings — if you'd hidden, say,
    the mana bar before, it will reappear in React until you untick it here.
  - **Fill direction** for the Auto Shot bar (converge to center — the
    reference — or a plain left/right fill, with the clip ticks and eWS marks
    following) and the melee swing bar (left/right).
  - **Auto Shot bar**: the rotation notation can now be hidden (plus the
    existing delay readout and eWS bracket marks).
  - **Cooldown grid — now fully editable**: each of the three rows keeps its
    style (large rotation tiles / small utility tiles / consumables), but you
    choose what's in it — reorder with Up/Down, remove with X, add any
    ability Nock tracks (including custom spells/items defined on the
    Cooldown Grid tab), hide a slot without removing it, and reset to the
    built-in layout with one click. Plus "Always show consumables" keeps
    row 3 visible while idle. The add list also gains ready-made consumable
    slots: Dark/Demonic Rune (one slot — they share their cooldown),
    Healthstone (Master/Major ranks) and Grenade (Adamantite → Thorium),
    joining the existing Sapper entry.
  - **Buff row**: hide individual utility icons (Feed Pet, Windfury, …), turn
    the in-combat RANGE/MISSING labels off, and add your own proc buff spell
    IDs — trinkets the built-in list doesn't know now get an icon too.
  - **Skin**: a curated set of overrides — the five bar heights and ten fill/
    state colors — defaulting to the reference look, with a one-click "Reset
    skin to reference look". Seams, fonts, textures and the grid stay fixed.
- **Fixed: a stream of "unknown event" errors at login.** Nock registered a
  spell-learned event the Anniversary client no longer has
  (`LEARNED_SPELL_IN_TAB`), producing up to 11 AceEvent errors at login —
  often blamed on other addons that happened to share the library. The
  range finder now registers the modern event name with safe fallbacks.

- **New (experimental): a React HUD look.** A second skin for the whole HUD,
  replicating the React hunter WeakAura pack: a converge-to-center Auto Shot
  bar with clip ticks and gated eWS marks, a melee-readiness bar (carrying
  the weave coach's stage cues), the predictive range bar, a thin mana bar
  and a glued cast bar in one bordered cluster; below it a three-row
  cooldown grid (burst row — including your racial — utility row, and a row
  that only appears while something on it is active); above it the pack's
  two buff-icon rows (important procs, dynamic utility). Switch under
  General → "HUD look", or flip quickly with `/nock react`; the Classic row
  stack is untouched and stays the default. React mode is deliberately
  fixed-skin: position, width, scale and the grid toggles apply, the
  texture/color/height settings don't. (`UI/Frame_ReactCluster.lua`,
  `UI/Frame_ReactCastBar.lua`, `UI/Frame_ReactCooldowns.lua`,
  `UI/Frame_ReactBuffs.lua`.)
- **Range Finder rebuilt: finding ladder + predictive weave bar.** One bar,
  two phases. Beyond ~10yd it names your yard bracket ("25-30 YD", "HM OUT OF
  RANGE", Hawk Eye-aware) with a drain-style fill — full at max range, empty
  at the weave-zone handoff; a config toggle swaps to the color-block Range
  Check look. Inside ~10yd it becomes a clamp-and-snap predictive weave bar:
  fill glides toward the melee tick with your run speed, snaps exact at every
  range boundary, and recolors by zone — Out while closing, Sweet in the
  weave ring, Perfect at the melee edge, and a red Deadzone once you're in
  melee. RESYNC (orange, parked at the tick) still flags a degraded estimate.
  The old thumb/slider display and the experimental "smooth range glide" flag
  are gone; `rangeInColor` is now the Deadzone color (old default
  auto-migrates to red once). The glide state machine lives in a pure engine
  file with a standalone LuaJIT test suite. (`Modules/RangeEngine.lua`,
  `Modules/RangeFinder.lua`, `UI/Frame_RangeFinder.lua`,
  `Tests/range_engine_test.lua`, config.)
- **React HUD range bar now rides the same engine.** The React cluster's range
  bar dropped its own inline copy of the WA state machine and Range Check
  ladder and consumes the shared engine's state instead — full parity with
  the classic bar: finding ladder honors the Finding style setting (drain
  fill with bracket-colored labels, or solid color block), and the orange
  parked-at-tick RESYNC now shows in React mode too. Palette stays the
  hardcoded reference-WA look. (`UI/Frame_ReactCluster.lua`.)
- **New (experimental): a Weave Bind.** A hold-to-melee-weave keybind Nock owns
  natively, so the Grounded addon is no longer needed for it: hold the key to step
  in (stops your cast, Raptor Strike, melee auto on), release to step back out
  (melee off, back to shooting). Both the press and release macro bodies are
  editable in the new Weave Bind tab, with a one-click restore of the shipped
  defaults. Both key edges fire via the secure button's `useOnKeyDown` attribute
  (the modern per-button override of the `ActionButtonUseKeyDown` CVar), so the
  macros need no `/console` lines and the rest of your action bars are untouched
  while the key is held; a watchdog still restores the CVar for user-edited
  macros that flip it themselves. Nock also adds a cast-on-key-down Setup Check
  entry (a latency recommendation, not a weave requirement). Mechanism modeled on
  press/release binds from the Grounded addon by Gello (reimplemented, no code
  copied). Off by default. (`Modules/WeaveBind.lua`, options, Setup Check.)
- **New (experimental): a weave coach on the RangeFinder bar.** While the Weave
  Bind is enabled, the range bar walks you through the weave cycle with a border
  tint and a small left-side label: green **GO IN** when the weave window opens
  (Raptor ready, enough swing headroom, right distance — same conditions as the
  rotation helper's Raptor call), amber **HOLD** while you're holding the key
  waiting for the hit, blue **BACK OUT** the moment the melee hit lands — move
  out but *keep holding* — and cyan **RELEASE** once Auto Shot is back in range,
  so the release macro's `!Auto Shot` actually sticks instead of failing with
  "target too close" and leaving you standing idle. Two optional sound cues fire
  on the outcomes you can't watch for while moving (hit landed / clear to
  release), configurable in the Weave Bind tab. Happy-path only for now.
  (`Modules/WeaveCoach.lua`, `state.weave`, RangeFinder view.)
- **Weave macros can be garment-gated, and Nock understands the gate.** Macro
  lines carrying an `[equipped:...]` / `[noequipped:...]` conditional for
  Shirt or Tabard don't evaluate correctly on this client, so Nock resolves
  them itself when applying the weave macros and re-applies the moment the
  garment changes: wear a tabard to keep a `/use [noequipped:Tabard]
  Snowball` line quiet on trash, take it off to arm it for the boss — or
  gate the other way round with `[equipped:...]`. A red warning calls out a
  wrongly-set garment when you target a raid boss ("Tabard on!" or "Shirt
  off!", whichever direction your macros use), and `/nock shirt` dumps the
  full resolver state into a copyable window for bug reports.
  (`Modules/WeaveBind.lua`, `Modules/Warnings.lua`.)
- **The garment gate can work itself.** Two new Weave Bind toggles: "Set
  your shirt/tabard for bosses automatically" puts the gate garment in the
  state your macros need the moment you target a raid boss out of combat —
  off for `[noequipped:...]` lines, on (fetched from your bags) for
  `[equipped:...]` lines — checking bag space first and never fighting a
  change you make by hand; "Switch it back after the fight" restores the
  everyday state once no living boss is targeted, remembering the item
  across a `/reload`. That upkeep works anywhere, not just in raids: a
  garment left in its boss state (forgotten after a manual swap, say) is
  put right as soon as no boss is targeted, so gated lines can't burn
  Snowballs out in the world. In combat gear is locked, so the red warning
  still covers that case. Off by default.
- **`/nock weavelog`: a weave tuning diagnostic.** Logs your weave presses
  and outcomes — hold duration, melee-swing recharge, range zone and ping at
  each press, whether the hold ever reached true melee, plus per-cycle
  weave-delay metrics (ability→weave / weave→ability) — so a sluggish weave
  is attributable from the log alone. Metrics-only by default;
  `/nock weavelog full` prints every key edge, flagging switch bounce and
  lost releases.
- **The "pop cooldowns during Bloodlust" warning can speak the trinket
  chain.** An opt-in voice cue (off by default, under that warning's
  settings): with Bloodlust up and both equipped trinkets on-use, popping
  the first trinket makes the game's text-to-speech call out the other one
  ("Trinket 2"), once per Lust window — trinket chaining without taking your
  eyes off the boss.
- **Rotation engine: Raptor/weave calls now wait for the melee swing timer.**
  The engine (and therefore the weave coach's GO IN) used to suggest stepping in
  right after a weave, while your melee swing was still recharging and no hit
  could possibly land. It now requires the melee swing to be ready within half a
  second — matching the Shot Bars weave lane, which already hid itself for
  exactly this reason. (`Modules/Rotation.lua`.)
- **The Range Finder bar height is now configurable** (Range Finder tab, 10-48
  px, default unchanged at 16) — it's grown from a passive readout into the
  weave coach's display surface, so it can now be made as prominent as that
  role deserves. The HUD rows repack around the new height.
- **Fixed: switching settings profiles now repaints the HUD immediately.**
  Switching, copying, or resetting an AceDB profile used to leave the HUD
  drawn with the old profile's looks until a `/reload`; every view now
  re-reads its settings on the spot.

## 1.0.12

- **New: a pet-training helper.** Open Beast Training and Nock puts a live, per-raid
  checklist right beside the window: pick your raid from the selector along the top,
  and each ability your build wants shows as a row with its own icon. Rows you've
  already trained are ticked off; the ones still to do stay highlighted — click a
  to-do row to select it, then press the game's own Train button. Your unspent
  training points and the done/to-do counts update as you go, so you can fill an
  optimal build without alt-tabbing to a guide.
- **New: an unspent pet training-points warning.** A quiet downtime nudge — out of
  combat only — when your pet is sitting on unspent training points, which is exactly
  the thing you forget after an untrain or on a freshly-levelled pet. The square
  shows how many points are waiting and clears once you've spent them (there's a
  threshold under Warnings if you'd rather it only speak up past a certain amount).
- **Misdirection now announces when the shot actually lands, not when you click.** The
  chat callout used to fire on the button press, so a Misdirect that never went out —
  out of range, line of sight, moving, on cooldown — still told the raid it had. It
  now waits for the cast to succeed before announcing, and only announces the tank the
  shot actually went to. The clicker can also follow whoever holds the raid's Main
  Tank assignment, so it tracks the designated tank even when role tags are messy.
- **The Steam Tonk Controller is now on the consumables checklist.** Handy for the
  pet-reset trick (hop in the tonk to dismiss your pet, hop out and re-summon it at
  full health), so the checklist reminds you to keep one in your bags.
- **New: an Experimental tab, with an opt-in "next-action" display.** A new Options
  tab collects unfinished, opt-in features — everything there is off by default and
  may change between versions. The first one is a big, movable medallion near your
  character that always says *what* to press, with a countdown ring that drains to the
  moment you fire and turns red while your Auto Shot is winding up, paired with a
  decluttered Shot Bars lane that only says *when*. Toggle both with `/nock v3`.

## 1.0.11

- **Nock now ships its own bar texture and uses it by default.** The bars used to
  default to the plain Blizzard texture, which is why screenshots of the same HUD
  never quite matched. The new "Nock Clean" texture is bundled with the addon, so
  everyone gets the same look without needing SharedMedia or WeakAuras installed.
  If you've already picked your own bar texture, it's left alone — if you never
  changed it, your bars will look a little cleaner after this update.
- **New: a wrong-aspect warning.** Nags you when you're in combat with anything
  other than Aspect of the Hawk up, or with no aspect at all. The square shows
  whichever aspect you're actually in, so it reads at a glance. Viper is not
  exempt — forgetting to swap back out of it is exactly the mistake this catches.
  Out of combat it stays quiet, so travelling in Cheetah and topping up in Viper
  between pulls won't nag you.
- **New: a Dazed alert, with an optional sound.** Being dazed slows you and locks
  you out of casting, and the fix is time-critical, so it now gets a warning
  square and — if you want one — an audio cue. The sound fires once per daze
  rather than repeating, and is off by default; pick one under Warnings → Dazed,
  where there's a Preview button next to it.
- **Each swing bar can now have its own direction.** The Auto Shot, Melee and GCD
  bars were locked together on a single setting; they now each have their own,
  defaulting to "Inherit (global)" so nothing moves until you deliberately split
  one. The clip ticks follow the Auto Shot bar.
- **Rotation labels can be renamed.** Every built-in notation ("1:1",
  "6:9:1:1 3w", and the rest) now has a text box under Rotation → Rename rotation
  labels. Call them whatever reads better for you; leave a box blank to keep the
  built-in. Display-only — the rotation engine itself is unaffected.
- **The Pet Growl and Wrong Trinket nags can be limited to raids.** A Riding Crop
  or Growl on autocast is perfectly reasonable out in the world and only really a
  problem in a raid, so both warnings now have an "Only inside a raid instance"
  toggle. Off by default, so they still warn everywhere unless you say otherwise.
- **Mounts and other non-combat casts can now show on the cast bar.** Mounting,
  Hearthstone, First Aid and Cooking never appeared there, because the cast bar
  reads the combat log and the combat log doesn't record them. There's a new
  toggle in General to include them; it's off by default, and your combat casts
  behave exactly the same either way.
- Thanks to **Noobweaver!** for the swing-bar direction suggestion.

## 1.0.10

- **Nock no longer eats your framerate during boss fights.** Several parts of the
  HUD were re-reading your entire buff list on every single frame, so the cost
  grew with both your framerate and the size of the raid's buff stack — which is
  why it only bit on boss pulls, and why it hit high-FPS machines hardest. Those
  checks now run ten times a second instead of every frame. The swing bars, shot
  bars and cast bar still redraw at full speed, so nothing looks any less smooth.
  Measured in a live raid, this cut Nock's CPU use by about 60% and took the test
  character from 74 to 111 FPS.
- **The raid-buff checklist is much cheaper.** It used to scan your buffs from
  scratch once for every buff it tracks; it now reads them once and matches the
  whole list against that single pass. Same display, a fraction of the work.
- **New: `/nock profile`.** A built-in performance readout, in case Nock ever
  feels heavy again. `/nock profile start` followed by `/nock profile show` puts a
  small live overlay on screen with Nock's CPU use, its tick rate, and which parts
  are costing the most; `/nock profile report` prints the full breakdown to chat.
  It's off by default and costs nothing while it isn't running — if you ever see a
  slowdown, this is the thing to send me.
- Thanks to **Noobweaver!** for the report that started this.

## 1.0.9

- **Fixed a combat error spam from the Misdirection panel.** With the tank
  click-cast buttons in use, the Misdirect panel threw a stream of "action
  blocked" errors throughout combat (it was trying to resize itself while the
  secure buttons had it locked). The panel now leaves its size alone during
  combat and settles it the moment combat ends, so the errors are gone.
- **Fixed the "Pop cooldowns" Bloodlust warning erroring out.** When you were in
  Bloodlust/Heroism with a cooldown ready, the warning that tells you to pop it
  would throw a Lua error instead of showing. It now displays correctly.
- **Fixed the Feign Death resist warning — it never actually worked.** The alert
  that fires when an enemy resists your Feign Death was both erroring and, under
  the hood, never triggering at all. It now latches on and plays its sound as
  intended.
- Thanks to **prollyadhd!** for reporting all three.

## 1.0.8

- **Updated for the 2.5.6 client.** Blizzard's latest Anniversary patch bumped the
  game to 2.5.6, which made Nock show as "Out of date". It now matches the new
  client, so the warning is gone.
- **Fixed a startup error that could break the options panel.** On some load
  orders Nock failed to open its settings with an "AceGUI-3.0" library error. The
  bundled libraries now load in the correct order, so the settings window opens
  reliably.
- **Fixed the HUD background disappearing after a reload.** With "Show background"
  enabled, the backdrop box would vanish on login or /reload and only reappear
  after toggling the setting off and on. It now shows correctly from the start.

## 1.0.7

- **Weave rotation notation.** The rotation label can now show weave patterns
  (5:5:1:1 3w, 2:2 1w, 6:9:1:1 3w, 6:11:1:1 3w, 3:7 2w) instead of only the turret
  patterns. It auto-switches to the weave pattern while you're in weaving range
  with a two-hander, and back to the turret pattern at range — so turret players
  are unaffected. Off by default; enable it under Rotation. The weave pattern is
  chosen from your active haste procs/buffs (Rapid Fire, imp. Aspect of the Hawk,
  plus total melee haste for Bloodlust / Dragonspine / Abacus / Haste Potion).
  Thanks to **Gilly** for the suggestion.
- **Hide the rotation text per component.** New toggles to hide just the rotation
  notation (without hiding the bar) on the Auto Shot bar (Swing Bars tab) and on
  the Shot Bars (Rotation tab). Also thanks to **Gilly**.
- **Cast bar & pet status can now be hidden.** Neither had an off switch before —
  they each get their own visibility toggle now, handy if you run your own HUD but
  still want Nock's smart features. Thanks to **Wickoss** for the report.
- **One place to control visibility.** The Layout tab now toggles every element —
  HUD rows, swing/cast bars, the pet panel, and all feature panels — each kept in
  sync with its own tab, plus **Hide all / Show all** buttons. Hiding everything
  no longer leaves a thin residual bar on screen.
- **Tuning defaults.** The clip-zone safety margin now defaults to 0s (matching
  the real clip zone), and the Shot Bars lookahead window defaults to 6 seconds.

## 1.0.6

- **Click-to-Misdirect tank buttons.** The Misdirection panel gains an optional
  second section: a clickable button for every group member assigned the Tank
  role, where clicking casts Misdirection straight onto that tank. Tanks are
  auto-detected from their assigned role, with a manual name list as a fallback,
  and an optional raid/party announce on each cast. Off by default — enable the
  "Tank buttons" section under Misdirection.
- **Unified Misdirection panel.** The cooldown tracker and the new tank buttons
  now share one draggable, lockable panel — tracker on top, a divider, then the
  tank buttons below (their own "Misdirect Tank" title and violet bars so the two
  sections read apart) — with a single, reorganized settings page for both.
- Thanks to **Pjonkish** for testing.

## 1.0.5

- **Customizable swing bars.** The Auto Shot bar and the melee swing timer can now
  each be hidden on their own, drop their spell icon (the bar then stretches to
  full width), and take a custom height and their own bar texture — all while
  still respecting the overall Scale and the Swing-timers per-row scale.
- **New "Swing Bars" tab.** The per-bar options, the swing-bar direction, and the
  GCD bar settings now live together in their own settings tab instead of being
  scattered through General.
- **Shot Bars direction.** A new toggle flows the scrolling timeline left→right
  (fire edge on the right) instead of the default right→left.
- **Auto Shot delay readout (experimental).** Optionally show, on the right edge of
  the Auto Shot bar, how many seconds late each shot fired versus one full
  weapon-speed cycle — color-coded green (tight) to red (badly delayed), resets out
  of combat. Off by default; enable it under Swing Bars.

## 1.0.4

- **GCD bar.** A thin global-cooldown sweep now sits just above the Auto Shot
  bar, tracking the haste-scaled global cooldown so you can see at a glance when
  your next shot or ability is free to fire. It follows the same direction as the
  swing bars.
- **Configurable.** Toggle it on/off, set its height, and pick its fill color
  (with alpha) — all under the new "Global Cooldown bar" section in General.
- **Spoken "Pet idle" alert.** The "Pet not attacking" warning can now say
  "Pet idle" aloud via the game's text-to-speech, repeating every 5 seconds while
  your pet sits idle during a boss encounter. Off by default; enable it under
  Warnings → "Pet not attacking".

## 1.0.3

- **Removable / tunable HUD background.** The solid black backdrop can now be
  turned off, dimmed, or recolored — a show/hide toggle, an opacity slider, and a
  color picker (General → Background). Set the opacity to 0 with a border for an
  outline-only look.
- **Border styling.** Choose a LibSharedMedia border for the HUD box with its own
  thickness, color, and opacity.
- **Per-element scaling.** Independently scale the rotation/helper row, shot bars,
  swing timers, range finder, info row, and the totem panel — on top of the
  overall Scale. The HUD box grows to fit the largest row.
- **Side panels follow the background.** The totem, pet-status, and repair panels
  now match the HUD background styling instead of always drawing a black box.
- **Row alignment.** Pick Center (new default) or Left for all rows; swing timers
  and the info row are no longer left-pinned out of the box.
- **Free placement mode.** Drag each HUD row — and the totem panel — anywhere;
  positions are saved per character. Unlock the HUD to drag (rows show a green
  edit border); a Reset button restores the grid.
- **New Layout tab.** Alignment, free placement, row visibility, and per-element
  scaling now live together (with a Lock HUD toggle), decluttering General. The
  totem tracker visibility toggle is also surfaced here under Rows.
- **Saner defaults.** Rotation clip ticks default to the tight (0.0s) preset, and
  the shopping list seeds every Alliance and Horde capital out of the box.

## 1.0.2

- **State-aware Shot Bars melee weave lane.** Two-tone — green when Raptor Strike
  is ready (Raptor weave), white when only an auto-attack weave is possible — and
  hidden while your melee swing is recharging.
- **Fluffy Hunter Bars attribution.** The Shot Bars view is inspired by
  Fluffy Hunter Bars by fluffymoo4kra (see `ATTRIBUTION.md`).
