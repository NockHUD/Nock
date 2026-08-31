-- Tests/hud_mode_predicate_test.lua
-- Standalone LuaJIT tests for the hudMode predicates in Core/State.lua:
-- Nock.HudMode / Nock.HudIsClassic / Nock.HudIsReact — THE one reading of the
-- mode string, so a third mode ("fluffy") can't be misfiled by scattered
-- `== "react"` comparisons. Also pins FreeLayoutActive's behavior for cluster
-- modes: free placement is a Classic-look setting; react AND fluffy grid.
-- Run from the repo root: luajit Tests/hud_mode_predicate_test.lua
--
-- Comparison-site audit (Task 0.2 record). Every former raw hudMode compare and
-- the predicate it routes through:
--   CLASSIC-ONLY (HudIsClassic()):
--     UI/Frame_CastBar.lua       classic cast bar renders only in classic
--     UI/Frame_PetStatus.lua     Mend/Feed slots only in classic (cluster modes carry the procs row)
--     UI/Frame_TotemTracker.lua  panel + unlocked preview only in classic (x2)
--     UI/Frame_ReleaseBar.lua    classic backdrop chrome vs flat cluster skin
--     UI/Frame_ReactBuffs.lua    classic host branch (becomes three-way Host() in Phase 3)
--     UI/HUD.lua ApplyBackground box only in classic
--     Core/State.lua             FreeLayoutActive (classic-only free placement)
--     Modules/Onboarding.lua     "classic card selected" / rotation page visible / recap rotation row
--                                (these take a passed profile `p`, so they compare
--                                (p.hudMode or "classic") == "classic" literally)
--     Config/Options.lua:6300    classic branch active badge
--   REACT-ONLY (HudIsReact()):
--     UI/Frame_ReactCastBar.lua  render gate
--     UI/Frame_ReactCorners.lua  pad gate + render gate (x2)
--     UI/HUD.lua                 ApplyRowVisibility react branch, width floor, free-belt
--     Modules/Onboarding.lua     react card selected/apply, reactcorners page, recap react row
--     Config/Options.lua:1748    react-only row, :5251 notReact gate, :6111 react active badge
--   LITERAL STRING KEPT (names the mode, not a branch):
--     Config/Defaults.lua:625 (the key), Options.lua hudModeSelect get/set,
--     Core/Core.lua:622 diag dump, :684-686 `/nock react` toggle,
--     Modules/ActionGlow.lua:203 diag dump, Onboarding apply(p) writes.

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Minimal WoW/Ace surface, same harness as free_layout_test.lua.
local Nock = {}
_G.GetRangedHaste = function() return 0 end
_G.LibStub = function() return { GetAddon = function() return Nock end } end

dofile("Core/State.lua")

ok(type(Nock.HudMode) == "function", "HudMode exists")
ok(type(Nock.HudIsClassic) == "function", "HudIsClassic exists")
ok(type(Nock.HudIsReact) == "function", "HudIsReact exists")

local function setMode(mode, extra)
  local prof = extra or {}
  prof.hudMode = mode
  Nock.db = { profile = prof }
  return prof
end

-- Classic (explicit and defaulted).
setMode("classic")
ok(Nock.HudMode() == "classic", "explicit classic: HudMode")
ok(Nock.HudIsClassic() == true, "explicit classic: HudIsClassic")
ok(Nock.HudIsReact() == false, "explicit classic: not HudIsReact")

setMode(nil)
ok(Nock.HudMode() == "classic", "unset key defaults to classic")
ok(Nock.HudIsClassic() == true, "unset key: HudIsClassic")

Nock.db = nil
ok(Nock.HudMode() == "classic", "no profile: defaults to classic, no error")
ok(Nock.HudIsClassic() == true, "no profile: HudIsClassic")
ok(Nock.HudIsReact() == false, "no profile: not HudIsReact")

-- React.
setMode("react")
ok(Nock.HudMode() == "react", "react: HudMode")
ok(Nock.HudIsClassic() == false, "react: not HudIsClassic")
ok(Nock.HudIsReact() == true, "react: HudIsReact")

-- Fluffy: a third value is NEITHER classic NOR react.
setMode("fluffy")
ok(Nock.HudMode() == "fluffy", "fluffy: HudMode")
ok(Nock.HudIsClassic() == false, "fluffy: not HudIsClassic")
ok(Nock.HudIsReact() == false, "fluffy: not HudIsReact")

-- FreeLayoutActive: only the Classic look frees; both cluster modes grid,
-- and a stale classic flag is ignored, not consumed.
setMode("classic", { freeLayout = true })
ok(Nock.FreeLayoutActive() == true, "classic + flag: free active")
setMode("react", { freeLayout = true })
ok(Nock.FreeLayoutActive() == false, "react ignores the stale flag")
setMode("fluffy", { freeLayout = true })
ok(Nock.FreeLayoutActive() == false, "fluffy ignores the stale flag")
setMode("fluffy", { freeLayout = false })
ok(Nock.FreeLayoutActive() == false, "fluffy + flag off: inactive")

print(("hud_mode_predicate: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
