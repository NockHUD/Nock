-- Forever/PetLamp.lua
-- The pet happiness row's decision: pet state and the Feed Pet timer in, what the three lamps show out (pure).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local LIT = { [1] = "u", [2] = "c", [3] = "h" }
local OUT = {}

-- pet: state.pet; feed: state.ledgerTimers.Feed ({ exp, dur }) or nil.
-- Returns the same table every call: no allocation on the tick.
function Nock.PetLamp(pet, feed, now)
  local o = OUT
  o.show, o.lit, o.pulse, o.fill, o.label, o.feedLeft = false, nil, false, nil, nil, nil
  if type(pet) ~= "table" or pet.exists ~= true or pet.dead == true or pet.loneWolf == true then return o end
  local lit = LIT[pet.happiness]
  if not lit then return o end
  o.show, o.lit = true, lit
  local exp, dur = feed and feed.exp, feed and feed.dur
  if type(exp) == "number" and type(dur) == "number" and dur > 0 and exp > now then
    local left = exp - now
    local f = 1 - left / dur
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    o.fill, o.label, o.feedLeft = f, "FEEDING", math.ceil(left)
  elseif lit ~= "h" then
    o.label = "FEED NOW"
  end
  o.pulse = (lit == "u") and o.label ~= "FEEDING"
  return o
end
