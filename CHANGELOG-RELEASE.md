## 1.1.9

- **The buff and debuff grids' "missing" border is their own, and off by
  default.** The border around a greyed (missing) slot was the rotation's
  next-action highlight, borrowed wholesale, so its only controls were three
  tabs away under Rotation → Next-action highlight and restyling one restyled
  the other. Both grids gained a *Missing highlight* block under their
  Background settings — Effect (none, static border, pixel ring, spell-proc
  sparkle, auto-cast) and Color — and the baseline is *None*: the greyed icon
  says missing on its own, the border is opt-in. Existing profiles lose the
  green ring on missing slots until they pick an effect there. A restyle now
  applies to the slots at once instead of on the next buff change.
- **Fix: the rotation label never checked the spec, so a Survival hunter was
  told to play the Beast Master rotation.** rotationtools' Short French,
  `5:4:1:1`, "only ever appears for survival hunters without the 20% haste out
  of the BM talent tree": without Serpent's Swiftness the swing is slow enough
  to hold seven casts over four autos, and the label used to land in the
  `5:5:1:1` bracket regardless. The HUD now reads the talent-tab majority
  (BM / MM / SV, re-read on every talent change) and a hunter without the BM
  haste gets `5:4:1:1` with nothing up, `5:5:1:1` on a Hawk or DST proc (the
  reference's own rule; a Survival Hawk proc used to show the BM-only Long
  French), and the live bracket for Rapid Fire and Bloodlust (`1:1` under
  Rapid Fire + Hawk, Skipping only with Lust on top). A Beast Master's labels
  are unchanged, spec unread resolves as before, and the new notation has its
  paper string, its rename/color row and its practice drill like the others.
- **Fix: the buff and debuff grids showed no timer without OmniCC.** Each
  slot's Cooldown frame has its own countdown hidden, and the buff grid only
  ever showed an empty text layer when no cooldown-text addon was there to
  paint it; the debuff grid had no fallback at all. Without OmniCC, tullaCC
  or ncCooldown both grids now write the seconds themselves (tenths under
  ten, minutes past ninety); with one loaded they stay quiet and leave the
  Cooldown frame to it, as before.
- **Fix: drink-walking could leave the DRINKING pill up for good.** Sit, sip
  a tick, run, repeat every two seconds: the Drink aura is applied and
  cancelled over and over, often inside one frame. The same-frame fold is the
  EATING fix below; on top of it, a cancel the client never reports now ends
  on its own once the drink's thirty seconds would have run, instead of
  waiting for the next aura change to notice.
- **Fix: the arrow counter ignored every arrow type except the one loaded.**
  With a full quiver and a second kind of arrow in the bags, the info row and
  the shopping list stopped at the quiver's 4800. Phase 3 makes that the
  normal case: Mysterious Arrows from Karazhan and Timeless Arrows from the
  Caverns of Time are both bind-on-pickup, so they sit next to the maker's
  Adamantite Stingers. The bag pass now counts every projectile of the loaded
  kind (arrows for a bow, bullets for a gun), whatever the item. `/nock arrows`
  opens its dump in the copybox instead of BugSack.
- **Fix: the EATING pill could stick after a food click while moving.** A
  food used on the run is applied and cancelled inside one frame, and the
  client reports both edges in a single aura event. The aura cache took the
  removal before the addition, so the addition stayed behind as a record
  nothing ever removed, and the pill sat at zero until the next full aura
  rebuild. The cache now applies additions, then updates, then removals
  (the order the client's own aura frames use), and an eating or drinking
  record whose time has run out no longer counts as eating at all.
- **Fix: a feign broken the instant it lands no longer leaves a six-minute
  bar (and black Classic shot bars).** An FD + trap macro, or an ability
  queued right behind Feign Death, stands you up before anything has seen you
  down, so 1.1.8's end signals (the combat log's removal, the aura seen then
  gone, the client's feign flag seen then dropped) never armed and the feign
  record sat on its six-minute cap. The Classic shot bars clip at that
  lockout, hence a bar with nothing on it. A feign record with no evidence of
  a feign after 0.6 s is now ended, and the bookkeeping runs even while the
  cast that broke the feign holds the cast bar, so the ghost cannot come back
  when that cast lands.
- **Fix: the React buff row's weave slot now follows the move-in cue toggle.**
  1.1.8 showed the GO IN / HOLD / BACK OUT / RELEASE slot whenever the weave
  coach ran, even with "Weave cue takes over the melee bar" off. That toggle
  (React HUD → Size & elements, off by default) is the one switch for the
  whole cue: off hides the slot too, on shows it, and the Buff Row entry
  stays the per-slot hide under it.
