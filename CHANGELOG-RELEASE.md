## 1.1.10

- **The warnings row can be moved.** `/nock unlock` (or the Unlock button)
  now shows a bordered box where the alert squares appear, draggable and
  with the usual nudge pad, name tag and element-list entry; the spot is
  saved per character. Warnings → Appearance gains a Reset position button
  that puts it back at the stock top-centre spot. Until now the row was the
  one panel that ignored unlock.
- **Own color for the Auto Shot wind-up on every cast bar.** Each HUD's cast
  bar gets a second fill color used while it shows the Auto Shot wind-up
  instead of a real cast: Classic HUD → Cast Bar → Auto Shot wind-up color,
  React → Skin → Cast: Auto Shot wind-up fill, FluffyHUD → Skin → Cast: Auto
  Shot wind-up fill. Each defaults to that bar's cast color, so nothing
  changes until you set it.
- **Mana tick on every HUD, and FluffyHUD gets a mana bar.** Each mana bar
  can show a thin spark riding the server's mana regen tick, opt-in per HUD
  (Classic HUD → Mana Bar, React → Bars, FluffyHUD → Bars, with a color under
  each Skin). In combat it sweeps the bar every 2 seconds and lands on the
  far edge as the tick arrives. Out of combat a spend starts the five-second
  rule instead: one sweep landing on the first regen tick at or after 5
  seconds, then the 2-second tick keeps sweeping until you are full. Each
  state has its own direction setting (stock: left to right in combat, right
  to left out of it). It is never shown at full mana. Gains and losses the
  combat log attributes to something else (a potion, Judgement of Wisdom,
  Mana Spring, a drink, a mana burn) are ignored so they cannot throw the
  tick off. Logic follows the "Tick Mana" WeakAura (wago a3MaLWYVn).
  FluffyHUD gains the thin React-style mana bar at the bottom of its stack,
  on by default, with its own height, fill color and center-text setting.
- **FluffyHUD's stack is reorderable.** FluffyHUD → Bars gains React's
  Up/Down bar-order editor over the five rows (Auto Shot bar, shot windows,
  weave lane, range finder, mana bar), with a reset to the built-in order.
  The cast bar is not a row: it keeps floating above whatever sits on top.
  New reference sizes for the stack: Auto Shot bar 14, shot lane 24, weave
  lane 10, font 10 (cast, range and mana bars stay at 14 / 12 / 12). *Reset
  skin* writes them back; a profile that already overrode a height keeps its
  own value.
