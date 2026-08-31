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
