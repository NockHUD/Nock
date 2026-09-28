-- Forever/TrackingWheel.lua
-- The tracking wheel: a held key opens the hunter's eight Track spells at the cursor; a flick and release casts one, in or out of combat (the aspect ring's factory).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

-- key ("beasts") -> Track spell id, from Nock.Spells.TRACKING (id -> key).
function Nock.TrackingWheelIdByKey()
  local out = {}
  for id, key in pairs(Nock.Spells.TRACKING) do out[key] = id end
  return out
end

-- Wheel size (Utilities -> Tracking wheel): the ring's clamp on its own key.
function Nock.TrackingWheelScale(p) return Nock.RingScale(p, "trackingWheelScale") end

-- The slot order is fixed (Nock.Spells.TRACKING_RING): Beasts up, then
-- clockwise. Always a fresh table, as the ring's order() contract asks.
function Nock.TrackingWheelOrder()
  local out = {}
  for i, k in ipairs(Nock.Spells.TRACKING_RING) do out[i] = k end
  return out
end

-- The Key Bindings entry is Bindings.xml; its label is in Core/Bindings.lua.
Nock.NewRingModule({
  name = "TrackingWheel", button = "NockTrackingWheelButton", screen = "NockTrackingWheelScreen", layer = "NockTrackingWheelLayer",
  stateKey = "trackingWheel", n = #Nock.Spells.TRACKING_RING, prefix = "track",
  keyProfile = "trackingWheelKey", scaleProfile = "trackingWheelScale",
  configMsg = "NOCK_TRACKING_WHEEL_CONFIG", closeMsg = "NOCK_TRACKING_WHEEL_CLOSE",
  idByKey = Nock.TrackingWheelIdByKey,
  order = Nock.TrackingWheelOrder,
})
