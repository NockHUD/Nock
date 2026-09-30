-- Forever/Quickstart.lua
-- Quickstarts > Weaving: which option sits on which checklist card, and each card's readiness. Pure but for Env().

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Q = {}
Nock.Quickstart = Q

-- The checklist, in setup order. `master` and every row are option paths in
-- the Forever settings tree; Config/OptionsForever.lua copies those nodes onto
-- the page, so a row here IS the switch on its home page. `adv` retags the
-- copy Advanced on this page; a `fix` row shows only while its rule holds.
Q.WEAVE = {
  { key = "hud", name = "On the HUD", icon = "rows",
    master = "hud.react.tabSize.weaveHelperEnabled",
    rows = {
      { "general.grpVisibility.hudEnabled", fix = function(p) return p.hudEnabled == false end },
      { "hud.react.tabSize.reactShowMeleeBar" },
      { "hud.react.tabSize.reactMeleeStageCue" },
      { "hud.react.tabSize.reactShowWeaveStrip" },
      { "hud.react.tabSize.weaveLegsReset" },
      { "hud.react.tabSize.weaveStartWindow" },
      { "hud.react.tabSize.weaveLegSeed" },
      { "hud.react.tabSize.reactWeaveH" },
      { "hud.react.tabSize.stagePreview" },
    } },
  { key = "camera", name = "Camera", icon = "turn",
    master = "utilities.cameraFlip.cameraFlipEnabled",
    rows = {
      { "utilities.cameraFlip.cameraFlipGate" },
      { "utilities.cameraFlip.cameraFlipAutoFace" },
      { "utilities.cameraFlip.cameraFlipSetup" },
      { "utilities.cameraFlip.cameraFlipStyle" },
    } },
  { key = "key", name = "Weave key", icon = "keyboard",
    master = "utilities.weaveKey.weaveKeyEnabled",
    rows = {
      { "utilities.weaveKey.weaveKey" },
      { "utilities.weaveKey.weaveKeyMovePad" },
      { "utilities.weaveKey.weaveKeyErrors" },
      { "utilities.weaveKey.weaveKeyReport" },
      { "utilities.weaveKey.weaveKeyMacroDown", adv = true },
      { "utilities.weaveKey.weaveKeyResetDown", adv = true },
      { "utilities.weaveKey.weaveKeyMacroUp", adv = true },
      { "utilities.weaveKey.weaveKeyResetUp", adv = true },
    } },
  { key = "macros", name = "Macros", icon = "text",
    hidden = function(p) return p.weaveKeyEnabled == true end,
    rows = {
      { "utilities.cameraFlip.cameraFlipMacros" },
    } },
  { key = "sounds", name = "Sounds", icon = "bell",
    rows = {
      { "alerts.sounds.range.soundCuesEnabled", fix = function(p) return p.soundCuesEnabled == false end },
      { "alerts.sounds.weaving.weaveStrikeEnabled" },
      { "alerts.sounds.weaving.weaveStrikeSound" },
      { "alerts.sounds.weaving.weaveStrikePreview" },
      { "alerts.sounds.weaving.weaveReleaseEnabled" },
      { "alerts.sounds.weaving.weaveReleaseSound" },
      { "alerts.sounds.weaving.weaveReleasePreview" },
      { "alerts.sounds.range.cueDeadZoneEnabled" },
      { "alerts.sounds.range.cueMeleeEnabled" },
    } },
}

function Q.Card(key)
  for _, c in ipairs(Q.WEAVE) do
    if c.key == key then return c end
  end
  return nil
end

local GATE = { solo = "everywhere", party = "party and raid", raid = "raid only" }

local function card(state, pill, line, problems)
  return { state = state, pill = pill, line = line, problems = problems or {} }
end

-- problems: { { pill, line }, ... } in fix order. The pill names the first,
-- the line carries them all.
local function attention(problems)
  local lines = {}
  for i, pr in ipairs(problems) do lines[i] = pr[2] end
  return card("attention", problems[1][1], table.concat(lines, " "), problems)
end

local function noClip(name) return name == nil or name == "" or name == "None" end

-- Pure. `p` is the profile; `env` the client facts it does not hold. A nil
-- fact means "cannot tell" and is never a problem. Keys read exactly as their
-- switches read them (the helper and the strip are on unless set false).
function Q.WeaveStatus(p, env)
  p, env = p or {}, env or {}
  local out = {}
  local helper = p.weaveHelperEnabled ~= false
  local flip = p.cameraFlipEnabled == true
  local key = p.weaveKeyEnabled == true

  if not helper then
    out.hud = card("off", "OFF", "The weave helper is off: no words, no strip.")
  else
    local pr = {}
    if p.hudEnabled == false then pr[#pr + 1] = { "HUD HIDDEN", "The HUD is hidden, so the words and the strip have nowhere to show." } end
    if p.reactShowMeleeBar == false then pr[#pr + 1] = { "MELEE BAR OFF", "The melee swing bar is off: the weave words ride on it." } end
    if #pr > 0 then out.hud = attention(pr)
    else
      local parts = { p.reactMeleeStageCue == true and "Words on the melee bar" or "Small words on the melee bar" }
      if p.reactShowWeaveStrip ~= false then parts[#parts + 1] = "weave strip" end
      out.hud = card("ready", "READY", table.concat(parts, ", "))
    end
  end

  if not flip then
    if key then
      out.camera = attention({ { "TURN IT ON", "The weave key wants the camera flip: without it the second hold runs you toward the target." } })
    else
      out.camera = card("off", "OFF", "No turn: you back out on your own keys.")
    end
  else
    local pr = {}
    if env.cameraSetupDone == false then pr[#pr + 1] = { "SET UP CAMERA", "The camera was never set up on this character." } end
    if env.cameraStyle ~= nil and env.cameraStyle ~= "0" then pr[#pr + 1] = { "FIX CAMERA STYLE", "Camera Following Style must be Never adjust." } end
    if #pr > 0 then out.camera = attention(pr)
    else out.camera = card("ready", "READY", "On, " .. (GATE[p.cameraFlipGate or "raid"] or GATE.raid)) end
  end

  if not key then
    out.key = card("off", "OFF", "One-key weaving is off.")
  else
    -- Nock's own key, or the one bound under Nock in the game's Key Bindings.
    local bound = (p.weaveKey ~= nil and p.weaveKey ~= "") and p.weaveKey or env.bindingKey
    local pr = {}
    if not bound then pr[#pr + 1] = { "BIND A KEY", "No key is bound." } end
    if env.movePad == false then pr[#pr + 1] = { "NO MOVEMENT PAD", "The Movement Pad is not available on this client: the key cannot run you." } end
    if #pr > 0 then out.key = attention(pr)
    else out.key = card("ready", "READY", "Key: " .. bound) end
  end

  if not key then
    if not flip then
      out.macros = card("off", "NOT NEEDED", "Without the camera flip your macros need nothing from Nock.")
    elseif env.macroFlip == nil or env.macroFace == nil then
      out.macros = card("none", "", "Copy the two macros, or add the camera lines to your own.")
    elseif env.macroFlip and env.macroFace then
      out.macros = card("ready", "READY", "Both camera lines are in your macros.")
    else
      local missing = {}
      if not env.macroFlip then missing[#missing + 1] = "/run NockCamFlip()" end
      if not env.macroFace then missing[#missing + 1] = "/run NockCamFace()" end
      out.macros = attention({ { "ADD CAMERA LINES", "No macro of yours carries " .. table.concat(missing, " or ") .. "." } })
    end
  end

  -- The weave cues (strike, release) decide the state. The range voice lines
  -- ship on for every hunter, so alone they are named, not counted.
  local on, voice, clipless = {}, {}, {}
  if p.weaveStrikeEnabled == true then
    on[#on + 1] = "strike"
    if noClip(p.weaveStrikeSound) then clipless[#clipless + 1] = "Strike" end
  end
  -- Release ships with no clip and may stay that way: silent is a choice
  -- there, not a problem, and a silent cue is not listed as one.
  if p.weaveReleaseEnabled == true and not noClip(p.weaveReleaseSound) then on[#on + 1] = "release" end
  if p.cueDeadZoneEnabled == true then voice[#voice + 1] = "dead zone" end
  if p.cueMeleeEnabled == true then voice[#voice + 1] = "melee" end
  if #on == 0 then
    local line = "No weave cues."
    if #voice > 0 and p.soundCuesEnabled ~= false then line = line .. " Voice lines: " .. table.concat(voice, ", ") .. "." end
    out.sounds = card("off", "OFF", line)
  else
    for _, v in ipairs(voice) do on[#on + 1] = v end
    local pr = {}
    if p.soundCuesEnabled == false then pr[#pr + 1] = { "CUES MUTED", "Range cues are switched off, so none of these play." } end
    if #clipless > 0 then pr[#pr + 1] = { "PICK A CLIP", table.concat(clipless, " and ") .. " cue: no clip picked, so it is silent." } end
    if #pr > 0 then out.sounds = attention(pr)
    else
      local text = table.concat(on, ", ")
      out.sounds = card("ready", "READY", text:sub(1, 1):upper() .. text:sub(2))
    end
  end

  return out
end

function Q.Tally(status)
  local t = { attention = 0, ready = 0, off = 0 }
  for _, s in pairs(status or {}) do
    if t[s.state] then t[s.state] = t[s.state] + 1 end
  end
  return t
end

function Q.TallyText(t)
  local parts = {}
  if t.attention > 0 then parts[#parts + 1] = t.attention .. (t.attention == 1 and " needs you" or " need you") end
  if t.ready > 0 then parts[#parts + 1] = t.ready .. " ready" end
  if t.off > 0 then parts[#parts + 1] = t.off .. " off" end
  return table.concat(parts, " · ")
end

-- A card's body is open while it needs you, or while it has no status to
-- show (its button is all it has); a click on the head (`choice`, true or
-- false) overrides that for the session.
function Q.CardOpen(state, choice)
  if choice ~= nil then return choice == true end
  return state == "attention" or state == "none"
end

-- The head's open/close cue: a chevron glyph (UI/IconAtlas.lua) and a word.
function Q.OpenCue(open)
  if open then return { glyph = "chevronup", text = "HIDE" } end
  return { glyph = "chevrondown", text = "SHOW" }
end

-- Pure: do these macro bodies carry the two camera hooks? nil list = the
-- client gave none to read. `unreadable` = how many bodies could not be
-- read: a line not found is then unknown (nil), not missing (false).
function Q.MacroLines(bodies, unreadable)
  if bodies == nil then return nil, nil end
  local flip, face = false, false
  for _, b in ipairs(bodies) do
    if type(b) == "string" then
      if b:find("NockCamFlip", 1, true) then flip = true end
      if b:find("NockCamFace", 1, true) then face = true end
    end
  end
  if (unreadable or 0) > 0 then
    if not flip then flip = nil end
    if not face then face = nil end
  end
  return flip, face
end

-- Every account and character macro body, or nil when the client has no way
-- to read them; second value = how many bodies could not be read.
local function macroBodies()
  if not (_G.GetNumMacros and _G.GetMacroBody) then return nil end
  local okn, account, character = pcall(_G.GetNumMacros)
  if not okn then return nil end
  local out, unreadable = {}, 0
  local function take(index)
    local okb, body = pcall(_G.GetMacroBody, index)
    if okb and type(body) == "string" then out[#out + 1] = body else unreadable = unreadable + 1 end
  end
  for i = 1, tonumber(account) or 0 do take(i) end
  local first = tonumber(_G.MAX_ACCOUNT_MACROS) or 120
  for i = 1, tonumber(character) or 0 do take(first + i) end
  return out, unreadable
end

-- The client facts WeaveStatus needs. Every read is guarded; what cannot be
-- read stays nil. The Movement Pad and the game binding are only asked for in
-- key mode (loading the pad is the weave key's business).
function Q.Env(p)
  local env = {}
  local ch = Nock.db and Nock.db.char
  if ch then env.cameraSetupDone = ch.cameraSetupDone == true end
  local get = (_G.C_CVar and _G.C_CVar.GetCVar) or _G.GetCVar
  if get then
    local okc, v = pcall(get, "cameraSmoothStyle")
    if okc and v ~= nil then env.cameraStyle = tostring(v) end
  end
  if p and p.weaveKeyEnabled == true then
    if _G.GetBindingKey then
      local WKB = Nock.WeaveKey and Nock.WeaveKey.BUTTON or "NockWeaveKey"
      local okb, k = pcall(_G.GetBindingKey, "CLICK " .. WKB .. ":LeftButton")
      if okb and type(k) == "string" and k ~= "" then env.bindingKey = k end
    end
    if _G.MovePadForward then
      env.movePad = true
    else
      local WK = Nock.WeaveKey
      if WK and WK.LoadPad then
        local okp, v = pcall(WK.LoadPad, WK)
        if okp then env.movePad = v == true end
      end
    end
  end
  env.macroFlip, env.macroFace = Q.MacroLines(macroBodies())
  return env
end

-- The page's status, by settings path. Memoised for the frame (a render asks
-- once per card); the window invalidates before each render.
function Q.StatusFor(pagePath)
  if pagePath ~= "quickstarts.weaving" then return nil end
  local p = Nock.db and Nock.db.profile
  if not p then return nil end
  local now = _G.GetTime and _G.GetTime() or nil
  local m = Q._memo
  if now and m and m.t == now and m.p == p then return m.st end
  local st = Q.WeaveStatus(p, Q.Env(p))
  Q._memo = { t = now, p = p, st = st }
  return st
end

function Q.Invalidate() Q._memo = nil end

return Q
