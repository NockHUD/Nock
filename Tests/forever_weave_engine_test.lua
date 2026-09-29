-- Tests/forever_weave_engine_test.lua
-- Forever/WeaveEngine.lua: one weave loop stage by stage, GO vs WAIT, leg
-- learning with a pause, the glide, the ranged re-anchor, every exit.
-- Run from the repo root: luajit Tests/forever_weave_engine_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local E = dofile("Forever/WeaveEngine.lua")
-- The cases below predate the rest band: with the shoot edge at 0 the old
-- geometry (DEAD edge = 0, melee = 1) holds; the rest-band cases at the end
-- set the fraction explicitly; the dead-zone edge gap is off for them too.
E.SHOOT_FRAC = 0
E.EDGE_GAP = 0
ok(type(E) == "table" and type(E.Step) == "function", "engine loads standalone")

-- New: seeds, stored legs, clamps.
local st = E.New(nil, nil, 1.1)
ok(near(st.legIn, 1.1) and near(st.legOut, 1.1) and st.learnedIn == false and st.learnedOut == false, "fresh: both legs on the seed, nothing learned")
local stored = E.New(0.9, 1.3, 1.1)
ok(near(stored.legIn, 0.9) and near(stored.legOut, 1.3) and stored.learnedIn and stored.learnedOut, "stored legs are learned legs")
ok(near(E.New(0.1, 9, 1.1).legIn, E.LEG_MIN) and near(E.New(0.1, 9, 1.1).legOut, E.LEG_MAX), "stored legs clamp to 0.3..4.0")
ok(near(E.New(nil, nil, nil).legIn, E.SEED), "no seed: 1.1 s")

-- rel = seconds since the last shot (the ranged swing's age); nil = fresh.
-- `moving` (the old bool) becomes intent: toward the target unless an out
-- leg runs or melee is being left; the flag itself still feeds SetMoving.
local function radialFor(s, moving)
  if not moving then return 0 end
  local out = (s.leg and s.leg.kind == "out") or s.zone == "MELEE" or s.stage == "STRIKE" or s.stage == "OUT"
  return out and -1 or 1
end
-- The old cases run out on a turned character (forward intent, facing
-- away from an anchor at 0), never on a backpedal: their samples land in
-- the run leg as they always did.
local function step(s, now, zone, moving, mri, rr, qw, rap, rel, radial)
  E.SetMoving(s, moving, now)
  if radial ~= nil then
    E.Step(s, now, zone, nil, radial, nil, mri or 0, rr or 5, qw or 0.4, rap or 0, rel or 0)
    return
  end
  if s.anchor == nil then s.anchor = 0 end
  local r = radialFor(s, moving)
  E.Step(s, now, zone, nil, (r ~= 0) and 1 or 0, (r < 0) and math.pi or 0, mri or 0, rr or 5, qw or 0.4, rap or 0, rel or 0)
end

-- Idle in range: nothing.
step(st, 0, "SWEET", false)
ok(st.stage == nil and near(st.glide, 0), "idle in range: no stage, glide at the ranged end")

-- Auto fires, white swing ready in 0.5 s, leg 1.1 s: GO.
ok(E.RangedSwing(st, 1) == true, "a Ranged swing with no melee hit before it is a shot")
step(st, 1, "SWEET", false, 0.5)
ok(st.stage == "GO" and st.waitFor == nil, "auto fired, melee ready by arrival: GO")

-- WAIT: melee 2.0 s out counts down into GO.
local w = E.New(nil, nil, 1.1)
step(w, 0, "SWEET", false)
E.AutoFired(w, 1)
-- A WAIT is only offered when its GO still lands inside the shot's window
-- (user 2026-09-28: a late GO throws the swing away; wait for the next shot).
ok(near(E.WAIT_MAX, E.GO_WINDOW), "WAIT_MAX equals the GO window")
step(w, 1, "SWEET", false, 2.0)
ok(w.stage == nil and w.pending == false, "melee 2.0 s out (wait 0.8 > the window): nothing this shot")
E.AutoFired(w, 1)
step(w, 1, "SWEET", false, 1.9)
ok(w.stage == "WAIT" and near(w.waitFor, 1.9 - 1.2), "melee 1.9 s out: WAIT 0.7 (melee minus leg minus slack)")
step(w, 1.5, "SWEET", false, 1.4)
ok(w.stage == "WAIT" and near(w.waitFor, 0.2), "WAIT counts down")
step(w, 1.9, "SWEET", false, 1.1)
ok(w.stage == "GO" and w.waitFor == nil, "and flips to GO when the swing will be ready on arrival")
-- GO is a window right after the shot (or the WAIT's end): a hunter who
-- has not left by then keeps the swing and waits for the next shot.
step(w, 1.9 + E.GO_WINDOW - 0.1, "SWEET", false, 0)
ok(w.stage == "GO", "GO holds inside its window")
step(w, 1.9 + E.GO_WINDOW + 0.1, "SWEET", false, 0)
ok(w.stage == nil and w.pending == false, "GO not taken inside the window: dropped until the next shot")
-- moving toward the target during GO is the run-in itself (2026-09-29: the
-- leg starts on intent, from the rest band), but never past START_MAX of
-- the ranged swing: with the next shot about to leave, a start would waste
-- it (in-game report 2026-09-28).
local gm = E.New(nil, nil, 1.1)
step(gm, 0, "SWEET", false); E.AutoFired(gm, 0); step(gm, 0, "SWEET", true, 0)
step(gm, E.GO_WINDOW + 0.5, "SWEET", true, 0, 5, 0.4, 0, E.GO_WINDOW + 0.5)
ok(gm.stage == "IN" and gm.leg and gm.leg.kind == "in", "moving during GO: the run-in is on, past the window")
step(gm, E.START_MAX + 0.1, "SWEET", true, 0, 5, 0.4, 0, E.START_MAX + 0.1)
ok(gm.stage == nil and gm.leg == nil and gm.pending == false, "the swing is 1.75 s old and range was never left: over, moving or not")
-- a WAIT that would end past START_MAX is not offered either
local gw = E.New(nil, nil, 1.1)
step(gw, 0, "SWEET", false); E.AutoFired(gw, 0); step(gw, 0, "SWEET", false, 1.9, 5, 0.4, 0, 0)
ok(gw.stage == "WAIT", "WAIT 0.7 right after the shot")
step(gw, 1.0, "SWEET", false, 1.0, 5, 0.4, 0, E.START_MAX + 0.2)
ok(gw.stage == nil, "the swing aged past START_MAX during the WAIT: dropped")

-- Raptor Strike must be off cooldown by arrival too (castable mid-run).
local rp = E.New(nil, nil, 1.1)
step(rp, 0, "SWEET", false); E.AutoFired(rp, 0)
step(rp, 0, "SWEET", false, 0, 5, 0.4, 1.9)
ok(rp.stage == "WAIT" and near(rp.waitFor, 1.9 - 1.2), "melee ready, Raptor 1.9 s out: WAIT 0.7 for the cooldown")
step(rp, 0.5, "SWEET", false, 0, 5, 0.4, 1.4)
ok(rp.stage == "WAIT" and near(rp.waitFor, 0.2), "counts down with the cooldown")
step(rp, 0.8, "SWEET", false, 0, 5, 0.4, 1.2)
ok(rp.stage == "GO", "Raptor ready by arrival: GO")
local rp2 = E.New(nil, nil, 1.1)
step(rp2, 0, "SWEET", false); E.AutoFired(rp2, 0)
step(rp2, 0, "SWEET", false, 1.8, 5, 0.4, 1.0)
ok(rp2.stage == "WAIT" and near(rp2.waitFor, 1.8 - 1.2), "the later of the two (melee 1.8, Raptor 1.0) sets the wait")

-- A wait longer than WAIT_MAX is not worth the lost swing: no cue this shot.
local wm = E.New(nil, nil, 1.1)
step(wm, 0, "SWEET", false); E.AutoFired(wm, 0)
step(wm, 0, "SWEET", false, 1.2 + E.WAIT_MAX + 0.5, 5, 0.4, 0)
ok(wm.stage == nil and wm.pending == false, "melee too far out: no WAIT, no GO, until the next shot")
E.AutoFired(wm, 3)
step(wm, 3, "SWEET", false, 1.2 + E.WAIT_MAX - 0.1, 5, 0.4, 0)
ok(wm.stage == "WAIT", "just inside WAIT_MAX: WAIT")

-- IN: the DEAD edge starts the leg; the glide runs on the seed; a pause stops it.
step(st, 1.2, "CLOSE", true, 0.3)
ok(st.stage == "IN" and st.leg and st.leg.kind == "in", "DEAD edge while GO: IN")
step(st, 1.75, "CLOSE", true)
ok(near(st.glide, 0.55 / 1.1), "0.55 s into a 1.1 s leg: glide 0.5")
step(st, 1.8, "CLOSE", false)
step(st, 2.3, "CLOSE", false)
ok(near(st.glide, 0.6 / 1.1), "standing still: the glide holds")
ok(near(st.leg.remaining, 0.5), "leg remaining counts only moving time")
step(st, 2.3, "CLOSE", true)
step(st, 3.0, "MELEE", true)
ok(st.stage == "STRIKE" and st.leg == nil and near(st.glide, 1), "MELEE edge: STRIKE, glide at the melee end")
ok(st.learnedIn == false and near(st.legIn, 1.1), "a leg spent 28% standing is not learned (moved 1.3 of 1.8)")

-- OUT: the hit starts the out leg; a Ranged swing inside the grace is the client's reset.
E.MeleeHit(st, 3.1)
ok(st.stage == "OUT" and st.leg and st.leg.kind == "out" and st.pending == false, "melee hit: OUT")
ok(E.RangedSwing(st, 3.15) == false and st.clientResets == true, "client reset inside the grace: not a shot")
step(st, 3.15, "MELEE", true)
ok(E.ReanchorDue(st, 3.3) == nil, "the client reset: nothing to re-anchor")
step(st, 3.3, "CLOSE", true)
ok(st.stage == "OUT", "leaving melee while OUT keeps OUT")
step(st, 3.65, "CLOSE", true)
ok(near(st.glide, 1 - 0.55 / 1.1), "half the out leg: glide back at 0.5")
-- back in range with the auto inside the queue window: RELEASE, then plain
step(st, 4.2, "SWEET", true, 0, 0.3, 0.4)
ok(st.stage == "RELEASE" and near(st.releaseAt, 4.2) and st.leg == nil, "SWEET edge with the shot within the queue window: RELEASE")
ok(st.learnedOut == true and near(st.legOut, 1.1) and near(st.sampleOut, 1.1), "the out leg (all moving from the hit, 1.1 s) is learned as is")
step(st, 4.5, "SWEET", false, 0, 0.1, 0.4)
ok(st.stage == "RELEASE", "RELEASE holds 0.4 s")
step(st, 4.61, "SWEET", false, 0, 0.0, 0.4)
ok(st.stage == nil, "then plain")

-- No client reset: re-anchor once, on the hit time.
local r = E.New(nil, nil, 1.1)
step(r, 0, "MELEE", true)
E.MeleeHit(r, 5)
ok(E.ReanchorDue(r, 5.05) == nil, "inside the grace: not yet")
ok(near(E.ReanchorDue(r, 5.11), 5), "past the grace with no Ranged event: re-anchor on the hit")
ok(E.ReanchorDue(r, 5.2) == nil, "and only once")
step(r, 6.5, "SWEET", true)
ok(E.RangedSwing(r, 7) == true, "a Ranged swing well after the hit, from range, is a shot")

-- Learning: a clean in leg replaces the seed; the next blends 50/50.
local l = E.New(nil, nil, 1.1)
step(l, 0, "SWEET", false)
E.AutoFired(l, 0); step(l, 0, "SWEET", false, 0)
step(l, 1, "CLOSE", true)
step(l, 2, "MELEE", true)
ok(l.learnedIn and near(l.legIn, 1.0) and near(l.sampleIn, 1.0) and near(l.learnedAt, 2), "first clean crossing (1.0 s) replaces the seed")
E.MeleeHit(l, 2.1); step(l, 2.1, "CLOSE", true)
step(l, 3.1, "SWEET", true, 0, 5, 0.4)
ok(l.stage == nil and near(l.legOut, 1.0), "out leg (hit at 2.1, range at 3.1 = 1.0 s) learned; shot not yet ready: plain")
E.AutoFired(l, 3.1); step(l, 3.1, "SWEET", false, 0)
step(l, 4, "CLOSE", true); step(l, 5.4, "MELEE", true)
ok(near(l.legIn, 1.2), "second crossing 1.4 s: 50/50 with the first = 1.2")
-- the glide uses the learned leg; the out leg's clock starts AT THE HIT
E.MeleeHit(l, 5.5); step(l, 5.5, "MELEE", true); step(l, 5.6, "CLOSE", true); step(l, 6.0, "CLOSE", true)
ok(near(l.glide, 1 - 0.5 / 1.0), "the out glide runs on the learned 1.0 s leg from the hit")
-- stale: 1.3x the estimate and still moving
step(l, 5.5 + 1.31, "CLOSE", true)
ok(l.leg and l.stale == true, "pushing on the edge past 1.3x the estimate: stale")
step(l, 5.5 + 1.0 * E.LEG_TIMEOUT_MUL + 0.01, "CLOSE", true)
ok(l.stage == nil and l.leg == nil, "past 3x the estimate: the leg is abandoned")

-- Movement edges at their own time (the helper forwards the events): the
-- leg clock closes when the player stopped, not at the next tick.
local mv = E.New(nil, nil, 1.0)
step(mv, 0, "SWEET", false); E.AutoFired(mv, 0); step(mv, 0, "SWEET", false, 0)
step(mv, 1, "CLOSE", true)
E.SetMoving(mv, false, 1.4)
step(mv, 1.9, "CLOSE", false)
ok(near(mv.glide, 0.4), "stopped at 1.4, ticked at 1.9: 0.4 s of the leg moved")
E.SetMoving(mv, true, 2.0)
step(mv, 2.3, "CLOSE", true)
ok(near(mv.glide, 0.7), "resumed at 2.0, ticked at 2.3: 0.7 s")

-- Hit before the MELEE edge (the finder's settle): the hit finishes the in leg.
local h = E.New(nil, nil, 1.1)
step(h, 0, "SWEET", false); E.AutoFired(h, 0); step(h, 0, "SWEET", false, 0)
step(h, 1, "CLOSE", true); step(h, 1.9, "CLOSE", true)
E.MeleeHit(h, 1.9)
ok(h.stage == "OUT" and h.learnedIn == false, "hit while the zone still reads DEAD: OUT; a leg started on the late CLOSE report and ended by the exact hit is no sample")

-- Turned back: IN then SWEET again drops the leg with no sample; OUT then MELEE again is STRIKE.
local tb = E.New(nil, nil, 1.1)
step(tb, 0, "SWEET", false); E.AutoFired(tb, 0); step(tb, 0, "SWEET", false, 0)
step(tb, 1, "CLOSE", true); step(tb, 1.4, "SWEET", true)
ok(tb.stage == nil and tb.leg == nil and tb.learnedIn == false, "turned back to range: idle, no sample")
E.AutoFired(tb, 1.5); step(tb, 1.5, "SWEET", false, 0)
step(tb, 2, "MELEE", true); E.MeleeHit(tb, 2); step(tb, 2.1, "CLOSE", true); step(tb, 2.6, "MELEE", true)
ok(tb.stage == "STRIKE" and tb.leg == nil, "back into melee while OUT (past the finder's catch-up grace): STRIKE, the out leg dropped")
step(tb, 2.6, "CLOSE", true)
ok(tb.stage == "OUT" and tb.leg and tb.leg.kind == "out", "leaving melee without a hit still runs an out leg")

-- GO straight into MELEE (tiny dead zone): STRIKE, no leg.
local g = E.New(nil, nil, 1.1)
step(g, 0, "SWEET", false); E.AutoFired(g, 0); step(g, 0, "SWEET", false, 0)
step(g, 0.5, "MELEE", true)
ok(g.stage == "STRIKE" and g.leg == nil and g.pending == false, "GO then MELEE with no DEAD read: STRIKE")

-- Exits: LONG, no target, target change; the legs survive.
local x = E.New(1.0, 1.2, 1.1)
step(x, 0, "SWEET", false); E.AutoFired(x, 0); step(x, 0, "SWEET", false, 0); step(x, 1, "CLOSE", true)
step(x, 1.5, "LONG", true)
ok(x.stage == nil and x.leg == nil and near(x.glide, 0), "LONG: idle")
E.AutoFired(x, 2); step(x, 2, "SWEET", false, 0); step(x, 3, "CLOSE", true)
step(x, 3.2, nil, true)
ok(x.stage == nil and x.leg == nil, "no target: idle")
E.AutoFired(x, 4); step(x, 4, "SWEET", false, 0); step(x, 5, "CLOSE", true)
E.TargetChanged(x, 5.5)
ok(x.stage == nil and x.leg == nil and x.pending == false and near(x.legIn, 1.0) and near(x.legOut, 1.2), "target change keeps the legs")
E.MeleeHit(x, 6)
ok(x.stage == nil, "a hit with no cue up stays idle")

-- Publish: flat fields, no allocation.
local out = {}
local p = E.New(nil, nil, 1.1)
step(p, 0, "SWEET", false); E.AutoFired(p, 0); step(p, 0, "SWEET", false, 0); step(p, 1, "CLOSE", true); step(p, 1.5, "CLOSE", true)
E.Publish(p, out)
ok(out.stage == "IN" and out.legKind == "in" and near(out.legProg, 0.5 / 1.1) and near(out.legRemaining, 0.6)
   and out.legStale == false and near(out.legIn, 1.1) and near(out.legOut, 1.1) and out.waitFor == nil and near(out.glide, 0.5 / 1.1),
   "Publish writes the flat weave fields")
E.TargetChanged(p, 2); E.Publish(p, out)
ok(out.stage == nil and out.legKind == nil and near(out.legProg, 0) and near(out.legRemaining, 0) and out.legStale == false, "Publish after idle clears the leg fields")

-- Review fixes (2026-09-28). A paused leg expires on the wall clock too: a
-- stun, a knockback or standing in melee after the hit must not leave the
-- cue marching (and the range warning silenced) forever.
local pz = E.New(nil, nil, 1.0)
step(pz, 0, "SWEET", false); E.AutoFired(pz, 0); step(pz, 0, "SWEET", false, 0)
step(pz, 1, "CLOSE", true); step(pz, 1.3, "CLOSE", false)
step(pz, 1 + E.IDLE_TIMEOUT - 0.1, "CLOSE", false)
ok(pz.stage == "IN" and pz.leg ~= nil, "a paused leg holds inside the idle timeout (from the leg's start)")
step(pz, 1 + E.IDLE_TIMEOUT + 0.1, "CLOSE", false)
ok(pz.stage == nil and pz.leg == nil, "a leg paused past the idle timeout is abandoned (wall clock)")
-- a slow leg (moving) still gets its 3x estimate
local sl = E.New(nil, nil, 2.0)
step(sl, 0, "SWEET", false); E.AutoFired(sl, 0); step(sl, 0, "SWEET", false, 0)
step(sl, 1, "CLOSE", true); step(sl, 1 + 5.5, "CLOSE", true)
ok(sl.stage == "IN", "a slow moving leg lives to 3x its 2.0 s estimate (5.5 s in)")
step(sl, 1 + 6.1, "CLOSE", true)
ok(sl.stage == nil, "and is abandoned past it")

-- A Ranged event while the stage is STRIKE or OUT can only be the client's
-- reset (no shot leaves from melee or the dead zone), whatever the grace.
local lr = E.New(nil, nil, 1.1)
step(lr, 0, "SWEET", false); E.AutoFired(lr, 0); step(lr, 0, "SWEET", false, 0)
step(lr, 1, "MELEE", true); E.MeleeHit(lr, 1); step(lr, 1, "MELEE", true)
ok(E.RangedSwing(lr, 1.35) == false and lr.pending == false and lr.clientResets == true, "a late Ranged event during OUT is a reset, not a phantom shot")
step(lr, 1.4, "CLOSE", true); step(lr, 2.2, "SWEET", true, 0, 5, 0.4)
ok(lr.stage == nil, "no GO owed after it")
local ls = E.New(nil, nil, 1.1)
step(ls, 0, "SWEET", false); E.AutoFired(ls, 0); step(ls, 0, "SWEET", false, 0)
step(ls, 1, "MELEE", true)
ok(ls.stage == "STRIKE" and E.RangedSwing(ls, 1.5) == false and ls.pending == false, "a Ranged event while STRIKE (before any hit) is not a shot either")

-- Gate round 3 (user, in game): a GO appeared long after a weave, the moment
-- Raptor came off cooldown. A "shot" recorded while standing in melee (the
-- client's late reset, no stage up) armed `pending` with no expiry.
local ph = E.New(nil, nil, 1.1)
step(ph, 0, "MELEE", false)
ok(E.RangedSwing(ph, 0.5) == false and ph.pending == false, "a Ranged event while the zone is MELEE is never a shot")
step(ph, 1, "CLOSE", true)
ok(E.RangedSwing(ph, 1.2) == false and ph.pending == false, "nor while it is the dead zone")
-- pending armed at range, then the hunter wanders: it expires with the swing
local pe = E.New(nil, nil, 1.1)
step(pe, 0, "SWEET", false); E.AutoFired(pe, 0)
step(pe, 0.2, "MELEE", true, 0, 5, 0.4, 5.0, 0.2)       -- decision blocked: not in range
ok(pe.pending == true and pe.stage == nil, "pending waits while out of range")
step(pe, 3.0, "MELEE", true, 0, 5, 0.4, 2.0, 3.0)
ok(pe.pending == false, "past START_MAX the pending shot is forgotten, whatever the zone")
step(pe, 3.5, "SWEET", false, 0, 5, 0.4, 0.5, 3.5)
ok(pe.stage == nil, "back in range with Raptor coming off cooldown: no GO without a fresh shot")

-- The start window is a setting (weaveStartWindow): E.SetWindow scales the
-- GO window, the WAIT cap and the swing-age cut-off together.
local sw = E.New(nil, nil, 1.1)
ok(near(sw.goWindow, E.GO_WINDOW), "New: the default window")
E.SetWindow(sw, 1.5)
ok(near(sw.goWindow, 1.5), "SetWindow stores it")
step(sw, 0, "SWEET", false); E.AutoFired(sw, 0)
step(sw, 0, "SWEET", false, 2.5)
ok(sw.stage == "WAIT" and near(sw.waitFor, 1.3), "a 1.3 s WAIT is offered with a 1.5 s window")
step(sw, 1.3, "SWEET", false, 1.2, 5, 0.4, 0, 1.3)
ok(sw.stage == "GO", "then GO")
step(sw, 1.3 + 1.4, "SWEET", false, 0, 5, 0.4, 0, 2.7)
ok(sw.stage == nil, "GO not taken inside 1.5 s: dropped")
E.AutoFired(sw, 5); step(sw, 5, "SWEET", false, 0, 5, 0.4, 0, 0)
step(sw, 5, "SWEET", true, 0, 5, 0.4, 0, 0)
step(sw, 7.4, "SWEET", true, 0, 5, 0.4, 0, 2.4)
ok(sw.stage == "IN", "moving: the run-in lives to window + 1 s of swing age")
step(sw, 7.6, "SWEET", true, 0, 5, 0.4, 0, 2.6)
ok(sw.stage == nil, "and not past it")
ok(near(E.SetWindow(sw, 0.05).goWindow, 0.2) and near(E.SetWindow(sw, 9).goWindow, 3.0) and near(E.SetWindow(sw, nil).goWindow, E.GO_WINDOW), "SetWindow clamps 0.2..3.0, nil = default")

-- An uncued weave (user 2026-09-28): a crossing the hunter makes without a
-- GO still runs the leg (glide, learning, the stage words from there on).
-- A mob walking into a standing hunter starts nothing.
local uc = E.New(nil, nil, 1.0)
step(uc, 0, "SWEET", false)
step(uc, 1, "CLOSE", true)
ok(uc.stage == "IN" and uc.leg and uc.leg.kind == "in", "walking into the dead zone with no cue: IN, leg running")
step(uc, 1.5, "CLOSE", true)
ok(near(uc.glide, 0.5), "the glide moves")
step(uc, 1.8, "MELEE", true)
ok(uc.stage == "STRIKE" and uc.learnedIn and near(uc.legIn, 0.8), "and the crossing is learned")
E.MeleeHit(uc, 2); step(uc, 2, "MELEE", true); step(uc, 2.1, "CLOSE", true)
ok(uc.stage == "OUT" and uc.leg.kind == "out", "the hit starts the out leg as usual")
-- out without a hit and without a cue: walking out of melee
local uo = E.New(nil, nil, 1.0)
step(uo, 0, "MELEE", false)
step(uo, 1, "CLOSE", true)
ok(uo.stage == "OUT" and uo.leg and uo.leg.kind == "out", "walking out of melee with no cue: OUT, leg running")
step(uo, 2, "SWEET", true, 0, 0.1, 0.4)
ok(uo.stage == "RELEASE" and uo.learnedOut and near(uo.legOut, 1.0), "learned, RELEASE on arrival with the shot ready")
-- standing still: the target moved, not the hunter
local mm = E.New(nil, nil, 1.0)
step(mm, 0, "SWEET", false)
step(mm, 1, "CLOSE", false)
ok(mm.stage == nil and mm.leg == nil, "a mob walking into a standing hunter: no leg, no cue")
step(mm, 2, "MELEE", false)
ok(mm.stage == nil, "into melee reach: still nothing")

-- ---------------------------------------------------------------------------
-- Intent (2026-09-29 addendum): the glide runs on the movement keys, not on
-- the client's moving flag. `radial` is + toward the target, - away, in the
-- character's frame; the facing anchor from the last shot / hit flips it.
-- ---------------------------------------------------------------------------
E.SHOOT_FRAC = 0
local function stepi(s, now, zone, radial, facing, rest, lateral)
  E.Step(s, now, zone, rest, radial, facing, 0, 5, 0.4, 0, 0, lateral)
end

-- W+S together: the client says moving, the keys say 0. Frozen.
local ws = E.New(nil, nil, 1.0)
stepi(ws, 0, "SWEET", 0); E.RangedSwing(ws, 0.1); stepi(ws, 0.1, "SWEET", 0)
ok(ws.stage == "GO", "GO on the shot")
stepi(ws, 0.5, "CLOSE", 0)
ok(ws.stage == "IN" and ws.leg.kind == "in", "DEAD edge under GO: IN")
stepi(ws, 0.9, "CLOSE", 1)
ok(near(ws.glide, 0.4), "0.4 s of intent in on a 1.0 s leg: 0.4")
E.SetMoving(ws, true, 0.9)
stepi(ws, 1.4, "CLOSE", 0)
ok(near(ws.glide, 0.4) and ws.stage == "IN", "W+S (radial 0, client moving): frozen, still IN")
stepi(ws, 1.9, "CLOSE", 0)
ok(near(ws.glide, 0.4) and ws.stale == false, "and not stale: nothing is pushing")

-- Strafe: the same 0. Autorun is the helper's business (it hands radial 1).
stepi(ws, 2.3, "CLOSE", 1)
ok(near(ws.glide, 0.8), "back on W: runs again")

-- A rest-band run-in that never left range dies with the shot's age; a
-- running out leg back in melee is STRIKE.
local ex = E.New(1.0, 1.0, 1.0)
stepi(ex, 0, "SWEET", 0); E.RangedSwing(ex, 0); stepi(ex, 0, "SWEET", 0)
stepi(ex, 0.3, "SWEET", 1)
ok(ex.stage == "IN", "moving under GO in the rest band: IN")
E.Step(ex, 2.0, "SWEET", nil, 1, nil, 0, 5, 0.4, 0, 2.0)
ok(ex.stage == nil and ex.leg == nil, "1.75 s after the shot, still in range: over")
local bk = E.New(1.0, 1.0, 1.0)
stepi(bk, 0, "MELEE", 0); E.MeleeHit(bk, 0)
stepi(bk, 0, "MELEE", 0)
ok(bk.stage == nil and bk.leg and bk.leg.kind == "out", "a hit with no stage arms the way out silently (in-game 2026-09-30: a run-in the anchor missed left the bar pinned full)")
stepi(bk, 0.1, "MELEE", -1)
ok(near(bk.glide, 0.9), "and the bar drains from the hit")
stepi(bk, 0.2, "CLOSE", -1)
ok(bk.stage == "OUT" and bk.leg.t0 ~= nil, "leaving melee with intent out: the words follow")
stepi(bk, 0.5, "CLOSE", -1)
stepi(bk, 0.6, "MELEE", 1)
ok(bk.stage == "STRIKE" and bk.leg == nil, "back into melee on a leg that had backed out: STRIKE")

-- S mid run-in: walks back at the out rate, reads BACK OUT, ends at the
-- SWEET edge with no in sample.
local sb = E.New(0.8, 1.6, 1.0)
stepi(sb, 0, "SWEET", 0); E.RangedSwing(sb, 0); stepi(sb, 0, "SWEET", 0)
stepi(sb, 0.2, "CLOSE", 0)
stepi(sb, 0.6, "CLOSE", 1)
ok(near(sb.glide, 0.5), "0.4 s in on a 0.8 leg: half way")
stepi(sb, 1.0, "CLOSE", -1)
ok(sb.stage == "OUT" and sb.leg.kind == "in" and near(sb.glide, 0.25), "S: 0.4 s out on the 1.6 out leg = -0.25, BACK OUT, the leg keeps its kind")
stepi(sb, 1.4, "CLOSE", -1)
ok(near(sb.glide, 0), "clamped at the shoot edge")
stepi(sb, 1.5, "SWEET", -1)
ok(sb.stage == nil and sb.leg == nil and near(sb.legIn, 0.8) and sb.sampleIn == nil, "SWEET edge: idle, the in leg is not a sample")

-- The hit, the camera turn, W: forward on a turned character is out.
local ct = E.New(1.0, 1.0, 1.0)
stepi(ct, 0, "SWEET", 0, 0); E.RangedSwing(ct, 0, 0); stepi(ct, 0, "SWEET", 0, 0)
stepi(ct, 0.1, "CLOSE", 1, 0)
stepi(ct, 1.0, "MELEE", 1, 0)
E.MeleeHit(ct, 1.1, 0)
ok(ct.stage == "OUT" and ct.leg.kind == "out" and near(ct.glide, 1) and near(ct.anchor, 0), "hit: OUT, pos 1, anchor = facing at the hit")
stepi(ct, 1.2, "CLOSE", 0, math.pi)
ok(near(ct.glide, 1) and ct.leg.t0 == nil, "turned, standing, out of melee reach: nothing moves, the clock has not started")
stepi(ct, 1.4, "CLOSE", 1, math.pi)
ok(ct.face == -1 and near(ct.glide, 0.8) and ct.stage == "OUT", "W on the turned character: face -1, 0.2 s out, BACK OUT")
stepi(ct, 1.6, "CLOSE", 1, math.pi)
ok(near(ct.glide, 0.6), "and on through the dead zone")
stepi(ct, 2.0, "CLOSE", 1, math.pi)
stepi(ct, 2.2, "CLOSE", 1, math.pi)
ok(near(ct.glide, 0), "1.0 s out: at the shoot edge")
E.Step(ct, 2.2, "SWEET", nil, 1, math.pi, 0, 0.1, 0.4, 0, 0)
ok(ct.stage == "RELEASE" and near(ct.legOut, 1.0) and near(ct.sampleOut, 1.0), "SWEET edge: RELEASE, the out leg (1.0 s net) learned")

-- The same weave with S and no turn: the same numbers.
local sn = E.New(1.0, 1.0, 1.0)
stepi(sn, 0, "SWEET", 0, 0); E.RangedSwing(sn, 0, 0); stepi(sn, 0, "SWEET", 0, 0)
stepi(sn, 0.1, "CLOSE", 1, 0)
stepi(sn, 1.0, "MELEE", 1, 0)
E.MeleeHit(sn, 1.1, 0)
stepi(sn, 1.2, "CLOSE", 0, 0)
stepi(sn, 1.4, "CLOSE", -1, 0)
ok(sn.face == 1 and near(sn.glide, 0.8) and sn.stage == "OUT", "S facing the target: face 1, 0.2 s out")
stepi(sn, 1.6, "CLOSE", -1, 0)
stepi(sn, 2.0, "CLOSE", -1, 0)
stepi(sn, 2.2, "CLOSE", -1, 0)
E.Step(sn, 2.2, "SWEET", nil, -1, 0, 0, 0.1, 0.4, 0, 0)
ok(sn.stage == "RELEASE" and near(sn.sampleOutBack, 1.0), "identical outcome, learned as the backpedal leg")

-- The face-back at range: the anchor still holds, so W is in again.
-- (The GO decision runs before the RELEASE flash clears: one tick later.)
stepi(sn, 2.65, "SWEET", 0, 0)
E.RangedSwing(sn, 2.65, 0); stepi(sn, 2.65, "SWEET", 0, 0)
stepi(sn, 2.7, "SWEET", 0, 0)
ok(sn.stage == "GO", "the next shot: GO once the flash is over")
stepi(sn, 2.8, "SWEET", 1, 0)
ok(sn.stage == "IN" and sn.leg.kind == "in" and sn.leg.fromRest == true, "W from the rest edge: IN at once, a rest-band leg")

-- A turn while the anchor is stale (facing drifted 80 degrees while strafing) still reads toward.
local fd = E.New(1.0, 1.0, 1.0)
stepi(fd, 0, "SWEET", 0, 0); E.RangedSwing(fd, 0, 0); stepi(fd, 0, "SWEET", 0, 0)
stepi(fd, 0.2, "CLOSE", 1, 80 * math.pi / 180)
ok(fd.face == 1 and fd.stage == "IN", "80 degrees off the anchor: still facing, in")
stepi(fd, 0.4, "CLOSE", 1, 100 * math.pi / 180)
ok(fd.face == -1, "100 degrees: away")
-- face wraps at 2 pi: 350 degrees from the anchor is a 10 degree turn.
local fw2 = E.New(1.0, 1.0, 1.0)
stepi(fw2, 0, "SWEET", 0, 0.1); E.RangedSwing(fw2, 0, 0.1); stepi(fw2, 0, "SWEET", 0, 0.1)
stepi(fw2, 0.2, "CLOSE", 1, 2 * math.pi - 0.1)
ok(fw2.face == 1, "face wraps at 2 pi")
-- No anchor yet: forward is toward.
local na = E.New(1.0, 1.0, 1.0)
stepi(na, 0, "SWEET", 0, math.pi); stepi(na, 0.2, "CLOSE", 1, math.pi)
ok(na.face == 1 and na.stage == "IN", "no anchor: forward is toward")

-- The learned sample is the net signed time, not the wall time.
local ln = E.New(nil, nil, 1.0)
stepi(ln, 0, "SWEET", 0); E.RangedSwing(ln, 0); stepi(ln, 0, "SWEET", 0)
stepi(ln, 0.0, "CLOSE", 1)
stepi(ln, 0.5, "CLOSE", 1)     -- +0.5
stepi(ln, 0.6, "CLOSE", -1)    -- -0.1
stepi(ln, 1.2, "CLOSE", 1)     -- +0.6 = net 1.0 of 1.2 wall (83 %: accepted)
stepi(ln, 1.2, "MELEE", 1)
ok(ln.stage == "STRIKE" and near(ln.sampleIn, 1.0) and near(ln.legIn, 1.0), "net 1.0 s (0.5 - 0.1 + 0.6): the sample")

-- A 3 s hitch integrates as DT_MAX.
local hz = E.New(4.0, 4.0, 1.0)
stepi(hz, 0, "SWEET", 0); E.RangedSwing(hz, 0); stepi(hz, 0, "SWEET", 0)
stepi(hz, 0.1, "CLOSE", 0)
stepi(hz, 3.1, "CLOSE", 1)
ok(near(hz.glide, E.DT_MAX / 4.0), "a 3 s hitch integrates as DT_MAX")

-- Rest band (item 9606): GO only from inside it; the glide's 0 is the rest
-- edge and the shoot edge sits at shootFrac; the outer edge pins 0 and
-- flags an overshoot on the way out.
E.SHOOT_FRAC = 0.55
local rb = E.New(1.0, 1.0, 1.0)
stepi(rb, 0, "SWEET", 0, nil, false)
E.RangedSwing(rb, 0); stepi(rb, 0, "SWEET", 0, nil, false)
ok(rb.stage == nil and rb.pending == true, "a shot from beyond 9606: no GO yet, the shot stays pending")
stepi(rb, 0.3, "SWEET", 0, nil, true)
ok(rb.stage == "GO" and near(rb.glide, 0), "into the band inside the window: GO, glide at the rest edge")
stepi(rb, 0.5, "SWEET", 1, nil, true)
ok(rb.stage == "IN" and rb.leg.fromRest == true and near(rb.leg.t0, 0.3) and near(rb.glide, 0.2), "W: IN from the rest edge, the clock from the previous tick, 0.2 s = 0.2")
stepi(rb, 0.85, "CLOSE", 1, nil, true)
ok(near(rb.leg.netAtShoot, 0.55) and near(rb.glide, 0.55) and rb.stale == false, "the shoot edge, reported as the estimate reaches it: net at the edge recorded")
stepi(rb, 1.3, "CLOSE", 1, nil, true)
ok(near(rb.glide, 1.0), "0.45 s past the edge = melee")
E.MeleeHit(rb, 1.3)
ok(near(rb.sampleIn, 1.0) and near(rb.sampleFrac, 0.55) and near(rb.shootFrac, 0.55) and rb.learnedFrac == true,
   "a rest-band leg samples its whole net (1.0 s) and where the shoot edge sat (0.55)")
-- Out. The finder reports every edge ~0.15 s late: MELEE after the hit,
-- CLOSE 0.15 s after the hunter leaves reach, SWEET 0.15 s after the shoot
-- edge; the crossing measured between the two late reports is clean.
-- (the way out draws the dead zone alone: the hit is full, the shoot edge
-- is empty, so RELEASE lands on empty; recordings 2026-09-30)
stepi(rb, 1.4, "MELEE", -1, nil, true)
ok(rb.stage == "OUT" and rb.leg and rb.leg.kind == "out" and near(rb.pos, 0.9) and near(rb.glide, 0.35 / 0.45), "MELEE reported after the hit: the out leg lives, 0.1 s out (pos 0.9, the bar 0.78)")
stepi(rb, 1.45, "CLOSE", -1, nil, true)
ok(near(rb.pos, 0.85) and near(rb.glide, 0.30 / 0.45), "out of melee reach reported: the drain goes on")
stepi(rb, 1.75, "CLOSE", -1, nil, true)
ok(near(rb.pos, 0.55) and near(rb.glide, 0), "0.45 s out: the shoot edge, the bar empty")
E.Step(rb, 1.75, "SWEET", true, -1, nil, 0, 0.1, 0.4, 0, 0)
ok(rb.stage == "RELEASE" and near(rb.glide, 0) and near(rb.sampleOutBack, 1.0), "RELEASE on empty: 0.45 s of backpedal from the hit / 0.45 = 1.0")
stepi(rb, 2.30, "SWEET", -1, nil, true)
ok(near(rb.pos, 0) and near(rb.glide, 0), "backing to the rest edge: still empty")
stepi(rb, 2.6, "SWEET", -1, nil, false)
ok(rb.overshot == true and near(rb.glide, 0), "past 9606 while backing: overshot")
stepi(rb, 2.8, "SWEET", 0, nil, false)
stepi(rb, 3.0, "SWEET", 1, nil, true)
ok(rb.overshot == false, "back inside: the flag clears")
-- the next run-in draws the full span again from empty
E.RangedSwing(rb, 3.1); stepi(rb, 3.1, "SWEET", 0, nil, true)
E.SetMoving(rb, true, 3.1); stepi(rb, 3.3, "SWEET", 1, nil, true)
ok(rb.stage == "IN" and near(rb.glide, 0.2), "W under the next GO: the bar rises from empty on the full span")

-- Stopping in the rest band settles the bar to empty: where the hunter
-- stands at rest IS the rest edge (in-game 2026-09-29: the way out with S
-- let go at RELEASE parked the bar at the shoot edge's half mark).
local rs = E.New(1.0, 1.0, 1.0)
stepi(rs, 0, "SWEET", 0, nil, true)
stepi(rs, 0.1, "MELEE", 0, nil, true); E.MeleeHit(rs, 0.1)
stepi(rs, 0.2, "CLOSE", -1, nil, true)
stepi(rs, 0.6, "CLOSE", -1, nil, true)
E.Step(rs, 0.65, "SWEET", true, -1, nil, 0, 0.1, 0.4, 0, 0)
ok(rs.stage == "RELEASE" and near(rs.pos, 0.55) and near(rs.glide, 0), "RELEASE at the shoot edge: the bar empty")
stepi(rs, 0.75, "SWEET", -1, nil, true)
ok(rs.pos < 0.55 and rs.pos > 0.4 and near(rs.glide, 0), "still backing: the estimate drains on, the bar stays empty")
E.SetMoving(rs, false, 0.8)
stepi(rs, 0.8, "SWEET", 0, nil, true)
ok(near(rs.pos, 0) and near(rs.glide, 0), "stopped in the band: settled to the rest edge")
stepi(rs, 2.0, "SWEET", 0, nil, true)
E.RangedSwing(rs, 2.0); stepi(rs, 2.0, "SWEET", 0, nil, true)
E.SetMoving(rs, true, 2.1)
stepi(rs, 2.2, "SWEET", 1, nil, true)
ok(rs.stage == "IN" and rs.leg.fromRest == true and near(rs.glide, 0.1), "the next run-in starts from empty as a rest-band leg")
-- W+S (intent 0, client still moving) does not settle it: only a real stop does.
local rw = E.New(1.0, 1.0, 1.0)
stepi(rw, 0, "SWEET", 0, nil, true); rw.pos = 0.3
E.SetMoving(rw, true, 0.1)
stepi(rw, 0.1, "SWEET", 0, nil, true)
ok(near(rw.glide, 0.3), "W+S in the band: frozen where it is")

-- Review fixes (2026-09-29). An unknown position is not the rest edge: a
-- fresh target while standing at the shoot edge must not learn the first
-- run-in as a rest-band leg.
local uk = E.New(nil, nil, 1.0)
E.SetMoving(uk, true, 0)
stepi(uk, 0, "SWEET", 1, nil, true)      -- moving already on the first tick: nothing has pinned pos
E.RangedSwing(uk, 0.1); stepi(uk, 0.1, "SWEET", 1, nil, true)
ok(uk.stage == "IN" and uk.leg.fromRest == false and uk.posKnown == false, "run-in from an unknown spot: not a rest-band leg")
stepi(uk, 0.3, "CLOSE", 1, nil, true)
stepi(uk, 0.75, "CLOSE", 1, nil, true)
E.MeleeHit(uk, 0.75)
ok(uk.learnedFrac == false and uk.sampleIn == nil, "nothing learned from it")
-- standing still in the band makes the spot known (it settles to 0)
local kn = E.New(nil, nil, 1.0)
stepi(kn, 0, "SWEET", 0, nil, true)
ok(kn.posKnown == true and near(kn.pos, 0), "standing in the band on a fresh target: at rest, known")

-- The OUT countdown runs to the shoot edge, where the leg ends.
local oc = E.New(1.0, 1.0, 1.0)
stepi(oc, 0, "MELEE", 0, nil, true); E.MeleeHit(oc, 0)
stepi(oc, 0.1, "CLOSE", -1, nil, true)
ok(near(oc.leg.remaining, (0.9 - 0.55) * 1.0), "OUT remaining = time to the shoot edge, not to the rest edge")

-- GO arrives from where the hunter stands: at rest the whole leg, half way in half of it.
local ga = E.New(1.0, 1.0, 1.0)
stepi(ga, 0, "SWEET", 0, nil, true)
E.RangedSwing(ga, 0); E.Step(ga, 0, "SWEET", true, 0, nil, 1.05, 5, 0.4, 0, 0)
ok(ga.stage == "GO", "at rest, white swing in 1.05 s, leg 1.0 + slack 0.1: GO")
local gh = E.New(1.0, 1.0, 1.0)
stepi(gh, 0, "SWEET", 0, nil, true); gh.pos = 0.5
E.RangedSwing(gh, 0); E.Step(gh, 0, "SWEET", true, 0, nil, 1.05, 5, 0.4, 0, 0)
ok(gh.stage == "WAIT" and near(gh.waitFor, 1.05 - 0.6), "half way in: the arrival is 0.5 s, so WAIT 0.45")

-- Stale only while a leg pushes on the edge it has not been reported past;
-- holding W into melee at STRIKE is not stale.
local sk = E.New(1.0, 1.0, 1.0)
stepi(sk, 0, "SWEET", 0, nil, true); E.RangedSwing(sk, 0); stepi(sk, 0, "SWEET", 0, nil, true)
stepi(sk, 0.2, "CLOSE", 1, nil, true)
stepi(sk, 0.7, "MELEE", 1, nil, true)
stepi(sk, 1.2, "MELEE", 1, nil, true)
ok(sk.stage == "STRIKE" and sk.stale == false, "W held 0.5 s in melee at STRIKE: not stale")
E.MeleeHit(sk, 1.2)
stepi(sk, 1.7, "MELEE", 1, nil, true)
ok(sk.stage == "OUT" and sk.stale == false and near(sk.glide, 1), "W still held after the hit: OUT stays, pinned at melee, not stale")

-- A late MELEE report (the finder's worst case is ~0.3 s) does not replay STRIKE.
local lm = E.New(1.0, 1.0, 1.0)
stepi(lm, 0, "SWEET", 0, nil, true); E.RangedSwing(lm, 0); stepi(lm, 0, "SWEET", 0, nil, true)
stepi(lm, 0.2, "CLOSE", 1, nil, true)
stepi(lm, 0.65, "CLOSE", 1, nil, true)
E.MeleeHit(lm, 0.65)
stepi(lm, 0.8, "CLOSE", -1, nil, true)
stepi(lm, 1.0, "MELEE", -1, nil, true)
ok(lm.stage == "OUT" and lm.leg and lm.leg.kind == "out", "MELEE reported 0.35 s after the hit while backing: still OUT")
stepi(lm, 1.2, "CLOSE", -1, nil, true)
stepi(lm, 1.6, "MELEE", 1, nil, true)
ok(lm.stage == "STRIKE" and lm.leg == nil, "back into melee 0.95 s after the hit on a leg that had backed out: STRIKE")

-- Overshot is backing out past 9606, not standing while the mob walks off.
local ov = E.New(1.0, 1.0, 1.0)
stepi(ov, 0, "SWEET", 0, nil, true)
stepi(ov, 0.2, "SWEET", 0, nil, false)
ok(ov.overshot == false, "the band left while standing: no overshoot")

-- The way out from deep inside melee reach (in-game recording 2026-09-30:
-- with the weave key the hunter hits 2-3 yd inside reach): the bar stays
-- full while the ladder reads MELEE and the out glide starts at the melee
-- edge report; no countdown and no stale meanwhile.
-- (2026-09-30, second recording: drawing reach full and starting at the
-- melee edge read as broken: a long full bar, a quarter-second drain, a
-- jump. The hit-anchored drain the user called smooth is back, calibrated
-- by the learned hit-to-shoot-edge time.)
local dp = E.New(1.0, 2.0, 1.0)
stepi(dp, 0, "SWEET", 0, nil, true); E.RangedSwing(dp, 0); stepi(dp, 0, "SWEET", 0, nil, true)
stepi(dp, 0.2, "CLOSE", 1, nil, true)
stepi(dp, 0.65, "MELEE", 1, nil, true)
E.MeleeHit(dp, 1.0)
stepi(dp, 1.5, "MELEE", 0, nil, true)
ok(near(dp.glide, 1) and dp.leg.t0 == nil, "standing after the hit: full")
stepi(dp, 2.1, "MELEE", -1, nil, true)
ok(dp.stage == "OUT" and near(dp.pos, 0.7) and near(dp.glide, 0.15 / 0.45) and dp.stale == false and near(dp.leg.remaining, 0.3), "0.6 s out inside reach on a 2.0 s out leg: pos 0.7, the bar a third, 0.3 s to the shoot edge, not stale")
stepi(dp, 2.2, "CLOSE", -1, nil, true)
ok(near(dp.pos, 0.65), "the melee edge reported: no snap, the drain goes on")
stepi(dp, 2.4, "CLOSE", -1, nil, true)
E.Step(dp, 2.4, "SWEET", true, -1, nil, 0, 0.1, 0.4, 0, 0)
ok(dp.stage == "RELEASE" and near(dp.glide, 0) and near(dp.sampleOutBack, 2.0), "RELEASE on empty: 0.9 s of backpedal from the hit = a 2.0 s out leg")

-- Inside the dead zone the bar stops a hair short of both ends until the
-- ladder reports the crossing (user 2026-09-30: "100% but the text says
-- DEAD ZONE" for the finder's settle), then the edge snaps it.
E.EDGE_GAP = 0.05
local eg = E.New(1.0, 1.0, 1.0)
stepi(eg, 0, "SWEET", 0, nil, true); E.RangedSwing(eg, 0); stepi(eg, 0, "SWEET", 0, nil, true)
stepi(eg, 0.2, "CLOSE", 0, nil, true)
stepi(eg, 1.2, "CLOSE", 1, nil, true)
ok(near(eg.pos, 1 - 0.05 * 0.45) and near(eg.glide, 1 - 0.05 * 0.45), "pushing past the estimate in the dead zone: a hair short of full (opt-in; the default gap is 0 since the stall read worse)")
ok(E.EDGE_GAP_DEFAULT == 0, "the default edge gap is 0")
stepi(eg, 1.3, "MELEE", 1, nil, true)
ok(near(eg.glide, 1), "MELEE reported: full")
E.MeleeHit(eg, 1.3)
stepi(eg, 1.5, "CLOSE", -1, nil, true)
stepi(eg, 2.5, "CLOSE", -1, nil, true)
ok(near(eg.pos, 0.55 + 0.05 * 0.45) and near(eg.glide, 0.05), "backing past the estimate in the dead zone: a hair above empty")
E.Step(eg, 2.6, "SWEET", true, -1, nil, 0, 0.1, 0.4, 0, 0)
ok(eg.stage == "RELEASE" and near(eg.glide, 0), "SWEET reported: empty")
E.EDGE_GAP = 0

-- Intent projected onto the target bearing (2026-09-30, second round):
-- forward counts cos(turn), turn left = facing up (keys probe). A strafe
-- counts NOTHING: its sign came out both ways in game (a range probe
-- walked away on a facing-down turn + strafe left; a later weave backing
-- and strafing left on a facing-up turn reached range while the same
-- sign said toward), so a strafe-out is drawn at the edges only.
E.SHOOT_FRAC = 0
local pj = E.New(1.0, 1.0, 1.0)
stepi(pj, 0, "SWEET", 0, 0); E.RangedSwing(pj, 0, 0); stepi(pj, 0, "SWEET", 0, 0)
stepi(pj, 0.2, "CLOSE", 1, 0)
stepi(pj, 0.6, "MELEE", 1, 0); E.MeleeHit(pj, 0.6, 0)
stepi(pj, 0.7, "MELEE", 0, -math.pi / 2)
ok(near(pj.glide, 1) and pj.face == 1, "turned 90 (facing down), standing: nothing moves, forward would be sideways")
stepi(pj, 1.0, "MELEE", 0, -math.pi / 2, nil, -1)
ok(near(pj.glide, 1) and pj.lateral == -1, "RMB+A (strafe left) on the turn: frozen, the strafe is read but not trusted")
stepi(pj, 1.3, "MELEE", 0, -math.pi / 2, nil, 1)
ok(near(pj.glide, 1), "strafe right: frozen too")
stepi(pj, 1.6, "MELEE", 1, math.pi, nil, 1)
ok(near(pj.glide, 0.7), "W on the flipped character with a strafe key held: the forward share alone, away")
local pd = E.New(1.0, 1.0, 1.0)
stepi(pd, 0, "SWEET", 0, 0); E.RangedSwing(pd, 0, 0); stepi(pd, 0, "SWEET", 0, 0)
stepi(pd, 0.2, "CLOSE", 0, 0)
stepi(pd, 0.6, "CLOSE", 1, math.pi / 3)
ok(near(pd.glide, 0.2), "W at 60 degrees off the target: half rate, 0.4 s = 0.2")
stepi(pd, 0.6, "CLOSE", 0.707, 0, nil, 0.707)
stepi(pd, 1.0, "CLOSE", 0.707, 0, nil, 0.707)
ok(near(pd.glide, 0.2 + 0.4 * 0.707), "W+D+RMB facing the target (the reader's diagonal pair): the forward share")

-- No depth (tried and reverted 2026-09-30: letting the estimate run past
-- the melee edge held the bar full through the deep part of the way out,
-- the stall the user rejects, and rescaled the learned leg). Inside reach
-- the estimate stays at the edge and the way out drains from the hit.
E.SHOOT_FRAC = 0.55
local dd = E.New(1.0, 2.0, 1.0)
stepi(dd, 0, "SWEET", 0, 0, true); E.RangedSwing(dd, 0, 0); stepi(dd, 0, "SWEET", 0, 0, true)
stepi(dd, 0.2, "CLOSE", 0, 0, true)
stepi(dd, 0.65, "MELEE", 1, 0, true)
stepi(dd, 1.0, "MELEE", 1, 0, true)
ok(dd.stage == "STRIKE" and near(dd.pos, 1), "0.35 s further in: the estimate stays at the edge")
E.MeleeHit(dd, 1.0, 0)
stepi(dd, 1.5, "MELEE", -1, 0, true)
ok(near(dd.pos, 0.75) and near(dd.glide, 0.2 / 0.45), "0.5 s of backpedal (2.0 s leg): the drain runs from the hit")
E.SHOOT_FRAC = 0

-- A white swing landing on the way out (still inside reach) must not pin
-- the estimate back to full (recording 2026-09-30: the bar snapped back
-- mid-drain); only a fresh hit does.
local wh = E.New(1.0, 2.0, 1.0)
stepi(wh, 0, "SWEET", 0, 0); E.RangedSwing(wh, 0, 0); stepi(wh, 0, "SWEET", 0, 0)
stepi(wh, 0.2, "CLOSE", 1, 0); stepi(wh, 0.6, "MELEE", 1, 0); E.MeleeHit(wh, 0.6, 0)
stepi(wh, 1.0, "MELEE", -1, 0)
ok(near(wh.pos, 0.8), "0.4 s of backpedal on a 2.0 s leg: 0.8")
E.MeleeHit(wh, 1.0, 0)
stepi(wh, 1.2, "MELEE", -1, 0)
ok(wh.stage == "OUT" and near(wh.pos, 0.7) and wh.leg and wh.leg.kind == "out", "a white hit mid way out: the drain goes on from 0.8, the leg is kept")

-- Two learned out legs: a backpedal (S while facing) has its own time;
-- a run or strafe out keeps the other. Keyed at the first step out.
E.SHOOT_FRAC = 0.55
local tl = E.New(1.0, 2.0, 1.0, nil, 4.0)
ok(near(tl.legOutBack, 4.0) and tl.learnedOutBack == true, "New takes a stored backpedal leg")
ok(near(E.New(1.0, 2.0, 1.0).legOutBack, 2.0) and E.New(1.0, 2.0, 1.0).learnedOutBack == false, "no stored backpedal leg: seeded from the out leg")
stepi(tl, 0, "SWEET", 0, 0, true); E.RangedSwing(tl, 0, 0); stepi(tl, 0, "SWEET", 0, 0, true)
stepi(tl, 0.2, "CLOSE", 0, 0, true); stepi(tl, 0.6, "MELEE", 0, 0, true); E.MeleeHit(tl, 0.6, 0)
stepi(tl, 1.5, "MELEE", -1, 0, true)
ok(tl.leg.method == "back" and near(tl.pos, 1 - 0.9 / 4.0), "S out: the backpedal leg, 0.9 s on 4.0")
stepi(tl, 2.4, "CLOSE", -1, 0, true)
E.Step(tl, 2.4, "SWEET", true, -1, 0, 0, 0.1, 0.4, 0, 0)
ok(near(tl.sampleOutBack, 4.0) and near(tl.legOutBack, 4.0) and near(tl.legOut, 2.0) and tl.sampleOut == nil, "1.8 s of backpedal / 0.45 = 4.0 learned into the backpedal leg; the run leg untouched")
E.SetMoving(tl, false, 2.5); stepi(tl, 2.5, "SWEET", 0, 0, true)
E.RangedSwing(tl, 3.0, 0); stepi(tl, 3.0, "SWEET", 0, 0, true)
E.SetMoving(tl, true, 3.0)
stepi(tl, 3.4, "SWEET", 1, 0, true); stepi(tl, 3.55, "CLOSE", 1, 0, true); stepi(tl, 4.0, "MELEE", 1, 0, true); E.MeleeHit(tl, 4.0, 0)
stepi(tl, 4.45, "MELEE", 1, math.pi, true)
ok(tl.leg.method == "run" and near(tl.pos, 1 - 0.45 / 2.0), "W on the flipped character: the run leg, 0.45 s on 2.0")
stepi(tl, 4.9, "CLOSE", 1, math.pi, true)
E.Step(tl, 4.9, "SWEET", true, 1, math.pi, 0, 0.1, 0.4, 0, 0)
ok(near(tl.sampleOut, 2.0) and near(tl.legOutBack, 4.0), "0.9 s of run / 0.45 = 2.0 into the run leg; the backpedal leg untouched")
local pw = {}
E.Publish(tl, pw)
ok(pw.lateral == tl.lateral and pw.legOutBack == tl.legOutBack, "Publish: lateral and the backpedal leg")
E.SHOOT_FRAC = 0.55

-- An uncued run-in from rest (user 2006-09-30: Raptor's cooldown beyond
-- the window withholds the GO, so the bar only woke at the dead-zone edge,
-- 0.5-1 s after the first step): a run toward the target from the rest
-- edge starts the leg on its own; a stop before the shoot edge ends it.
E.SHOOT_FRAC = 0.55
local ur = E.New(1.0, 1.0, 1.0)
stepi(ur, 0, "SWEET", 0, 0, true)
E.RangedSwing(ur, 0, 0)
E.Step(ur, 0, "SWEET", true, 0, 0, 0, 5, 0.4, 2.5, 0)   -- Raptor 2.5 s out: no GO this shot
ok(ur.stage == nil and ur.pending == false and near(ur.pos, 0), "Raptor on cooldown: no GO, at rest")
E.SetMoving(ur, true, 0.1)
stepi(ur, 0.3, "SWEET", 1, 0, true)
ok(ur.stage == "IN" and ur.leg.fromRest == true and near(ur.glide, 0.2), "W from rest without a GO: IN at once, the bar rises from the first step")
E.SetMoving(ur, false, 0.4)
stepi(ur, 0.4, "SWEET", 0, 0, true)
ok(ur.stage == nil and ur.leg == nil and near(ur.pos, 0), "stopped before the shoot edge: over, settled at rest")
-- A run-in from an unknown spot still waits for the dead-zone edge.
local uu = E.New(1.0, 1.0, 1.0)
E.SetMoving(uu, true, 0)
stepi(uu, 0, "SWEET", 1, 0, true)
stepi(uu, 0.3, "SWEET", 1, 0, true)
ok(uu.stage == nil, "moving on a fresh target with no known spot: nothing yet")

-- rest nil (item 9606 unanswered) reads as inside: GO anywhere in SWEET.
local rn = E.New(1.0, 1.0, 1.0)
stepi(rn, 0, "SWEET", 0, nil, nil)
E.RangedSwing(rn, 0); stepi(rn, 0, "SWEET", 0, nil, nil)
ok(rn.stage == "GO", "rest nil reads as inside")

-- A leg that starts at the shoot edge (no rest start) samples the in leg but not the fraction.
local se = E.New(nil, nil, 1.0)
stepi(se, 0, "SWEET", 0); E.RangedSwing(se, 0); stepi(se, 0, "SWEET", 0)
stepi(se, 0.2, "CLOSE", 0)
ok(near(se.glide, 0.55) and near(se.leg.netAtShoot, 0), "GO reaching the dead zone without an intent start: the leg starts at the shoot edge")
stepi(se, 0.65, "CLOSE", 1)
E.MeleeHit(se, 0.65)
ok(se.sampleIn == nil and se.learnedFrac == false, "ended by the hit (exact) after a late start: no sample, no fraction")
local sz = E.New(nil, nil, 1.0)
stepi(sz, 0, "SWEET", 0); E.RangedSwing(sz, 0); stepi(sz, 0, "SWEET", 0)
stepi(sz, 0.2, "CLOSE", 0)
stepi(sz, 0.65, "MELEE", 1)
ok(near(sz.sampleIn, 1.0) and sz.learnedFrac == false, "ended by the MELEE report (late like its start): 0.45 s past the edge = a 1.0 s leg")

-- Publish carries the new fields.
local pw = {}
E.Publish(se, pw)
ok(pw.radial == se.radial and pw.face == se.face and pw.overshot == false and near(pw.glide, se.pos), "Publish: radial, face, overshot, glide")

print(("forever_weave_engine: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
