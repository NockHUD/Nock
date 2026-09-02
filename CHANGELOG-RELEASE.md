## 1.1.8

- **Fix: Helpers click-to-apply used a scroll on your target.** A plain
  consumable click was a bare item use, which the client aims at the
  current target when the item can be targeted -- with a mob selected the
  scroll went to the mob. Every click is now a macro with an explicit unit:
  scrolls and food on you, pet food on the pet, stones on the named hand.
- **Helpers click-to-apply: expiring badges click too.** A countdown badge
  (buff about to run out) now takes a click and reapplies, like a missing
  one; with both scrolls or both stones up it names the sooner one and the
  click refreshes exactly that. EATING keeps the click (mage food gives no
  Well Fed, the real food replaces it); APPLYING still does not.
- **Helpers badges sweep the item's cooldown.** The refill item's cooldown
  (and the global cooldown it triggers) runs on the badge, so a click that
  did nothing reads as not-ready instead of silence.
- **React HUD: move-in cue on the melee bar.** The weave coach's stage now
  takes over the melee bar instead of swapping its 9px text: the bar fills
  in the stage colour, triangles march the way to move (in on GO IN, out on
  BACK OUT), the word stays over them, and RELEASE enters with a flash. React
  HUD → Size & elements → "Weave cue takes over the melee bar" (off by
  default; off = the small text as before). Needs the hold-to-weave key,
  like the coach.
  A session-only "Preview: cycle the weave stages" toggle next to it runs
  the four stages on the bar, the Raptor glow and the buff row's weave slot
  out of combat; practice drills show the real cue.
- **React buff row: weave stage slot.** The row carries the coach's stage as
  a slot too: Raptor Strike's icon (the plain Attack icon on an auto-only
  weave, Raptor on cooldown) with GO IN / HOLD / BACK OUT / RELEASE under
  it, first in the row. Hide it per entry under Buff Row like the
  other utility slots. (MOVE IN stays what it was: the ranged alert for a
  target beyond Auto Shot range, with the Auto Shot icon.)
- **React HUD: Raptor Strike glow on GO IN** (Cooldown Grid → Glows & tints,
  off by default, shared with the FluffyHUD row). The Raptor tile gets the
  action-button glow while the coach says GO IN.
- **Helpers row reworked.** The label sits in a band inside each icon, a
  muted PRE-PULL caption sits under the row, scroll badges say which scroll
  is missing (AGI / STR) with a YOU or PET strip along the top, and "ask
  friend?" became NO FOOD / NO FLASK / NO SCROLL style labels. Text is Nock's
  Plex Mono face, colours come from the skin palette.
- **Click to apply** (Helpers tab, on by default). A badge whose consumable
  is in your bags pulses gold with a pointer and uses it on click: scrolls on
  you or your pet, stones on your main hand. Out of combat only, one item per
  press.
- The expiring warning now defaults to 3 minutes (was 5), the slider goes up
  to 30, and the Demonslaying badge caps its own window at the last minute
  since the elixir itself lasts five.
- `/nock helpers test` bypasses the instance and raid gates for the session
  so the row can be tried on a dummy; `/nock helpers test demon` or `undead`
  also makes any target count as a boss of that type, for the Demonslaying
  and consecrated-stone badges. `/nock helpers test off` clears it.
- **Eating / drinking pill.** A small centre-screen capsule (above the boss
  alert, movable) while the Food or Drink aura is on you: round icon under
  a draining swipe, EATING / DRINKING, seconds left; a buff food adds a
  WELL FED IN Ns line counting down the ten seconds, and the pill flashes
  WELL FED in green when the buff lands, with an optional chime. On by default and
  shown wherever you eat or drink; size and chime in the Helpers tab.
- **Weapon stones on both hands.** For dual wielders the stone badge (and
  the consecrated one vs Undead) now covers the off hand too: the top strip
  says MAIN or OFF, the click applies to that hand, and the stone offered
  matches the weapon (sharpening stone on a blade, weightstone on a mace).
  2H weapons stay skipped: that hand carries Windfury.
- **Cast bar: the Feign Death bar no longer outlives the feign.** After
  standing up, the six-minute feign bar could stay in place and come back
  after every later cast, and the shot bars treated it as a six-minute
  lockout; a mount pressed right after a quick feign (the aggro drop) got
  no bar at all. The bar's on/off now follows the combat log's own
  apply/remove edges for Feign Death (with the client's feign flag and the
  aura scan as fall-backs) instead of trusting the aura scan alone, and a
  cast started while the feign record is still up displaces it, since a
  cast is what breaks a feign.
