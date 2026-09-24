-- Core/Bindings.lua
-- The Key Bindings window labels for Bindings.xml; loaded by every toc, because the client reads Bindings.xml for all of them.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local forever = Nock.Flavor and Nock.Flavor.forever

-- Written through _G: the CLICK name carries a space and a colon, and the
-- global-write check stays clean.
_G["BINDING_HEADER_NOCK"] = "Nock"

-- Practice (Modules/Practice.lua, TBC): Start/Stop toggles the fight (and
-- turns practice on for it), Focus toggles the stage between the window and
-- the HUD, Expert the two-panel mode (combat log + weave log, no stage).
_G["BINDING_NAME_NOCK_PRACTICE_STARTSTOP"] = "Practice: start / stop the fight"
_G["BINDING_NAME_NOCK_PRACTICE_FOCUS"] = "Practice: focus (stage on the HUD / workbench)"
_G["BINDING_NAME_NOCK_PRACTICE_EXPERT"] = "Practice: expert (combat log + weave log, no stage)"

-- Aspect ring (Forever/AspectRing.lua, WoW Forever only: the button does not
-- exist on TBC, where the entry says so).
_G["BINDING_NAME_CLICK NockAspectRingButton:LeftButton"] = forever and "Aspect ring (hold)" or "Aspect ring (WoW Forever)"
