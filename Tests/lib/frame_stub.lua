-- Tests/lib/frame_stub.lua
-- A WoW frame stub for headless UI tests: every method is a no-op that returns the frame; a few keep state.
local Stub = { counters = { SetText = 0, SetTexture = 0, SetPoint = 0 } }
local function noop(self) return self end
local Frame = {}
-- WoW API methods are UpperCamel; anything else (the view's own fields: key,
-- trueT0, easing, fill, edges, ...) reads nil until the view sets it.
Frame.__index = function(t, k)
  local v = rawget(Frame, k)
  if v ~= nil then return v end
  if type(k) == "string" and k:match("^%u") then return noop end
  return nil
end
function Frame:SetSize(w, h) self._w, self._h = w, h; return self end
function Frame:SetWidth(w) self._w = w; return self end
function Frame:SetHeight(h) self._h = h; return self end
function Frame:GetWidth() return self._w or 960 end
function Frame:GetHeight() return self._h or 224 end
function Frame:SetText(s) self._text = s or ""; Stub.counters.SetText = Stub.counters.SetText + 1; return self end
function Frame:GetText() return self._text or "" end
function Frame:GetStringWidth() return #(self._text or "") * 6 end
function Frame:SetTexture(t) self._tex = t; Stub.counters.SetTexture = Stub.counters.SetTexture + 1; return self end
function Frame:SetAlpha(a) self._alpha = a; return self end
function Frame:GetAlpha() if self._alpha == nil then return 1 end; return self._alpha end
function Frame:Show() self._shown = true; return self end
function Frame:Hide() self._shown = false; return self end
function Frame:IsShown() return self._shown ~= false end
function Frame:SetPoint(p, rel, rp, x, y)
  if type(rel) == "number" then x, y, rel, rp = rel, rp, nil, nil end
  self._point = { p, rel, rp, x or 0, y or 0 }
  Stub.counters.SetPoint = Stub.counters.SetPoint + 1
  return self
end
function Frame:GetPoint()
  local p = self._point or { "CENTER", nil, "CENTER", 0, 0 }
  return p[1], p[2], p[3], p[4], p[5]
end
function Frame:GetFrameLevel() return self._level or 1 end
function Frame:SetFrameLevel(l) self._level = l; return self end
function Frame:GetFrameStrata() return self._strata or "MEDIUM" end
function Frame:SetFrameStrata(s) self._strata = s; return self end
function Frame:GetEffectiveScale() return self._effScale or 1 end
function Frame:GetScale() return 1 end
function Frame:GetLeft() return 0 end
function Frame:GetBottom() return 0 end
function Frame:GetRight() return self._w or 0 end
function Frame:GetTop() return 0 end
function Frame:GetParent() return self._parent end
function Frame:SetParent(p) self._parent = p; return self end
function Frame:SetScript(name, fn) self._scripts = self._scripts or {}; self._scripts[name] = fn; return self end
function Frame:GetScript(name) return self._scripts and self._scripts[name] end
function Frame:CreateTexture() return Stub.CreateFrame("Texture", nil, self) end
function Frame:CreateFontString() return Stub.CreateFrame("FontString", nil, self) end
function Stub.CreateFrame(kind, name, parent, template)
  local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _template = template }, Frame)
  if name then _G[name] = f end
  return f
end
return Stub
