-- Tests/forever_weave_engine_test.lua
-- Forever/WeaveEngine.lua: one weave loop stage by stage, GO vs WAIT, leg
-- learning with a pause, the glide, the ranged re-anchor, every exit.
-- Run from the repo root: luajit Tests/forever_weave_engine_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local E = dofile("Forever/WeaveEngine.lua")
ok(type(E) == "table" and type(E.Step) == "function", "engine loads standalone")

-- New: seeds, stored legs, clamps.
local st = E.New(nil, nil, 1.1)
ok(near(st.legIn, 1.1) and near(st.legOut, 1.1) and st.learnedIn == false and st.learnedOut == false, "fresh: both legs on the seed, nothing learned")
local stored = E.New(0.9, 1.3, 1.1)
ok(near(stored.legIn, 0.9) and near(stored.legOut, 1.3) and stored.learnedIn and stored.learnedOut, "stored legs are learned legs")
ok(near(E.New(0.1, 9, 1.1).legIn, E.LEG_MIN) and near(E.New(0.1, 9, 1.1).legOut, E.LEG_MAX), "stored legs clamp to 0.3..4.0")
ok(near(E.New(nil, nil, nil).legIn, E.SEED), "no seed: 1.1 s")

-- rel = seconds since the last shot (the ranged swing's age); nil = fresh
local function step(s, now, zone, moving, mri, rr, qw, rap, rel)
  E.Step(s, now, zone, moving, mri or 0, rr or 5, qw or 0.4, rap or 0, rel or 0)
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
-- moving during GO keeps it (the DEAD edge is coming), but never past
-- START_MAX of the ranged swing: with the next shot about to leave, a start
-- would waste it (in-game report 2026-09-28).
local gm = E.New(nil, nil, 1.1)
step(gm, 0, "SWEET", false); E.AutoFired(gm, 0); step(gm, 0, "SWEET", true, 0)
step(gm, E.GO_WINDOW + 0.5, "SWEET", true, 0, 5, 0.4, 0, E.GO_WINDOW + 0.5)
ok(gm.stage == "GO", "moving during GO: the cue stays past the window")
step(gm, E.START_MAX + 0.1, "SWEET", true, 0, 5, 0.4, 0, E.START_MAX + 0.1)
ok(gm.stage == nil and gm.pending == false, "the swing is 1.75 s old: no GO, moving or not")
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
E.MeleeHit(st, 3.1, true)
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
ok(st.learnedOut == true and near(st.legOut, 1.1) and near(st.sampleOut, 1.1), "the out leg (all moving, 1.1 s) is learned as is")
step(st, 4.5, "SWEET", false, 0, 0.1, 0.4)
ok(st.stage == "RELEASE", "RELEASE holds 0.4 s")
step(st, 4.61, "SWEET", false, 0, 0.0, 0.4)
ok(st.stage == nil, "then plain")

-- No client reset: re-anchor once, on the hit time.
local r = E.New(nil, nil, 1.1)
step(r, 0, "MELEE", true)
E.MeleeHit(r, 5, true)
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
E.MeleeHit(l, 2.1, true); step(l, 2.1, "MELEE", true)
step(l, 2.2, "CLOSE", true); step(l, 3.1, "SWEET", true, 0, 5, 0.4)
ok(l.stage == nil and near(l.legOut, 1.0), "out leg (hit at 2.1, range at 3.1 = 1.0 s) learned; shot not yet ready: plain")
E.AutoFired(l, 3.1); step(l, 3.1, "SWEET", false, 0)
step(l, 4, "CLOSE", true); step(l, 5.4, "MELEE", true)
ok(near(l.legIn, 1.2), "second crossing 1.4 s: 50/50 with the first = 1.2")
-- the glide uses the learned leg; the out leg's clock starts AT THE HIT
E.MeleeHit(l, 5.5, true); step(l, 5.5, "MELEE", true); step(l, 5.6, "CLOSE", true); step(l, 6.0, "CLOSE", true)
ok(near(l.glide, 1 - 0.5 / 1.0), "the out glide runs on the learned 1.0 s leg from the hit")
-- stale: 1.3x the estimate and still moving
step(l, 5.5 + 1.31, "CLOSE", true)
ok(l.leg and l.leg.stale == true, "past 1.3x the estimate, still moving: stale")
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
E.MeleeHit(h, 1.9, true)
ok(h.stage == "OUT" and h.learnedIn and near(h.legIn, 0.9), "hit while the zone still reads DEAD: in leg learned from the hit, OUT")

-- Turned back: IN then SWEET again drops the leg with no sample; OUT then MELEE again is STRIKE.
local tb = E.New(nil, nil, 1.1)
step(tb, 0, "SWEET", false); E.AutoFired(tb, 0); step(tb, 0, "SWEET", false, 0)
step(tb, 1, "CLOSE", true); step(tb, 1.4, "SWEET", true)
ok(tb.stage == nil and tb.leg == nil and tb.learnedIn == false, "turned back to range: idle, no sample")
E.AutoFired(tb, 1.5); step(tb, 1.5, "SWEET", false, 0)
step(tb, 2, "MELEE", true); E.MeleeHit(tb, 2, true); step(tb, 2.1, "CLOSE", true); step(tb, 2.4, "MELEE", true)
ok(tb.stage == "STRIKE" and tb.leg == nil, "back into melee while OUT: STRIKE, the out leg dropped")
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
E.MeleeHit(x, 6, true)
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
step(lr, 1, "MELEE", true); E.MeleeHit(lr, 1, true); step(lr, 1, "MELEE", true)
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
ok(sw.stage == "GO", "moving: a GO lives to window + 1 s of swing age")
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
E.MeleeHit(uc, 2, true); step(uc, 2, "MELEE", true); step(uc, 2.1, "CLOSE", true)
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

print(("forever_weave_engine: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
