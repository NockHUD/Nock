## 2.0.0-alpha.2

- **Alpha of the 2.0 line.** Everything below is new since 1.1.x and not all
  of it has been seen on a real raid night. Report anything odd on the
  CurseForge page or the GitHub issues; the stable 1.1.x file stays the
  default download until 2.0.0 ships.
- **Profiles you can share.** Profiles → Sharing exports your whole setup
  (settings, weave macros, every frame position) as one text string; Import
  pastes one from another player into a new profile under a name you pick,
  with a way back to your own. Starter profiles bundled with Nock can be applied the same way, and the
  setup wizard then opens with "Start from scratch" or "Start from <name>'s
  layout". Your own profile is never overwritten: every apply is a new named
  profile. `/nock share export | import | apply <key>`. Session flags (the
  profiler overlay, debug prints) never travel with a string.
- **React HUD: clip ticks can be hidden.** React HUD → Bars → `Clip ticks`
  switches the red/orange Steady and Multi tick pairs off; the wind-up mark
  and the GCD divider keep their own switches.
- **Tranq alert knows the Black Temple Leviathan.** Electric Spur (spell
  40076), which a nearby mob puts on the Leviathan, is on the built-in list.
- **Settings search glass drew broken.** The magnifier icon was drawn at
  14 px and lost most of its strokes; it is 16 px now, like the nav icons.
