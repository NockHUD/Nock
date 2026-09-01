## 1.1.7

- **New stock weave macros — the battle-tested pair.** The shipped weave
  bind now presses Snowball poke → Raptor Strike → Kill Command (on your
  pet's target) → `/startattack`, and re-arms with Kill Command +
  `!Auto Shot` on release. No `/stopcasting` — the step-in's own movement
  already cancels a running Steady, and Kill Command rides both edges so
  the proc is never wasted. Fresh installs and never-edited profiles get
  the pair automatically; an edited or older stock pair is left alone
  until you re-pick "Default" in the wizard, which upgrades it and keeps
  your shirt-gate choices. The shirt gate now covers the press-side
  `/startattack` too.
- **Auto-backpedal as a settings switch.** Options → Weave Bind: a
  toggle that adds the movement-pad backpedal to both macro bodies (the
  wizard's "Clever" option, now flippable any time) and removes it
  cleanly again.
- **Anetheron helper reworked: Sleep is instant.** Videos and logs show
  no cast bar — the whole cast machinery is gone and the button now runs
  on the real mechanic: the next Sleep window opens 20 s after a cast
  (slider 10–30). While the window is closed a small wait bar under the
  icon fills toward the opening (red for the last 3 s); CLICK NOW plus
  the Glass sound when it opens, with a configurable leeway (default 1 s)
  to drink a moment early. The air horn now ships silent — it only ever
  fired when it was already too late — and the button hides when you
  carry no Slammer (a mid-raid buy brings it back with the timer right).
  `/nock slammer sim` runs a practice boss on the real numbers.
- **FluffyHUD: spell icons on the lanes (opt-in).** A new toggle under
  Fluffy HUD → Size & Elements draws each window's ability icon at the
  left edge of its span — Steady, Multi, Arcane, Raptor Strike and the
  melee Attack fist on the weave lane. The queue window and the clip
  band stay bare, and spans too narrow for the icon show none. Off by
  default.
