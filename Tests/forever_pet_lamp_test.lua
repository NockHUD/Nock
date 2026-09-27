-- Tests/forever_pet_lamp_test.lua
-- Forever/PetLamp.lua: pet state + feed timer -> what the three happiness lamps show.
-- Run from the repo root: luajit Tests/forever_pet_lamp_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local Nock = { Flavor = { forever = true } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/PetLamp.lua")
local L = Nock.PetLamp

local function pet(h, t)
  local p = { exists = true, dead = false, loneWolf = false, happiness = h }
  for k, v in pairs(t or {}) do p[k] = v end
  return p
end

local o = L(pet(3), nil, 100)
ok(o.show and o.lit == "h" and not o.pulse and o.label == nil and o.fill == nil, "happy: green, no label")
o = L(pet(2), nil, 100)
ok(o.show and o.lit == "c" and not o.pulse and o.label == "FEED NOW", "content: amber, FEED NOW")
o = L(pet(1), nil, 100)
ok(o.show and o.lit == "u" and o.pulse and o.label == "FEED NOW", "unhappy: red pulsing, FEED NOW")

ok(not L(pet(3, { exists = false }), nil, 100).show, "no pet hides")
ok(not L(pet(3, { dead = true }), nil, 100).show, "dead pet hides")
ok(not L(pet(3, { loneWolf = true }), nil, 100).show, "Lone Wolf hides")
ok(not L(pet(nil), nil, 100).show, "nil/secret happiness hides")
ok(not L(pet(7), nil, 100).show, "out-of-range happiness hides")
ok(not L(nil, nil, 100).show, "no state table hides")

-- Feeding: 20 s effect, 5 s in.
o = L(pet(1), { exp = 115, dur = 20 }, 100)
ok(o.show and o.lit == "u" and not o.pulse, "feeding while unhappy: red, pulse stops")
ok(o.label == "FEEDING" and o.feedLeft == 15 and math.abs(o.fill - 0.25) < 1e-9, "feeding: label, 15 s left, 25% filled")
o = L(pet(3), { exp = 100.2, dur = 20 }, 100)
ok(o.label == "FEEDING" and o.feedLeft == 1 and o.lit == "h", "feeding while happy: fill in the green lamp, ceil seconds")
o = L(pet(2), { exp = 99, dur = 20 }, 100)
ok(o.label == "FEED NOW" and o.fill == nil and o.feedLeft == nil, "feed expired: back to FEED NOW")
o = L(pet(2), { exp = 115, dur = 0 }, 100)
ok(o.label == "FEED NOW" and o.fill == nil, "unlearned feed dur: no fill")
o = L(pet(2), { exp = 150, dur = 20 }, 100)
ok(o.fill == 0 and o.feedLeft == 50, "exp beyond dur: fill clamps at 0")

ok(L(pet(3), nil, 1) == L(pet(2), nil, 1), "one reused output table")

print(("forever_pet_lamp: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
