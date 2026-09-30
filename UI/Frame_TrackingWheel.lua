-- UI/Frame_TrackingWheel.lua
-- The tracking wheel's layer and eight secure slot buttons (the aspect ring view factory; WoW Forever).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

-- The tracking that is on comes from Forever/Tracking.lua (state.tracking).
Nock.NewRingView({
  name = "TrackingWheelView", layer = "NockTrackingWheelLayer", slotPrefix = "NockTrackingWheelSlot",
  stateKey = "trackingWheel", n = #Nock.Spells.TRACKING_RING,
  disc = "TrackingWheelDisc.tga", wedge = "TrackingWheelWedge.tga",
  closeMsg = "NOCK_TRACKING_WHEEL_CLOSE", scaleProfile = "trackingWheelScale",
  idByKey = Nock.TrackingWheelIdByKey,
  activeKey = function(state)
    local active = state.tracking and state.tracking.activeId
    return active and Nock.Spells.TRACKING[active] or nil
  end,
})
