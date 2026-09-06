-- UI/KeyCapture.lua
-- Shared key/mouse capture for keybinding rows: one active capture, AceGUI's binding-string format, mouse wheel included.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
Nock.UI = Nock.UI or {}
local KC = {}
Nock.UI.KeyCapture = KC

local IGNORE = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = false }
local MOUSE = { LeftButton = nil, RightButton = nil, MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

function KC.Format(key, shift, ctrl, alt)
  if key == nil then return nil end
  if key == "ESCAPE" then return "" end
  if IGNORE[key] then return nil end
  key = MOUSE[key] or key
  local s = key
  if shift then s = "SHIFT-" .. s end
  if ctrl then s = "CTRL-" .. s end
  if alt then s = "ALT-" .. s end
  return s
end

local active   -- { frame, onDone, refuse }

local function finish(result)
  local a = active
  if not a then return end
  active = nil
  local f = a.frame
  f:EnableKeyboard(false)
  f:EnableMouseWheel(false)
  f:SetScript("OnKeyDown", nil)
  f:SetScript("OnMouseDown", nil)
  f:SetScript("OnMouseWheel", nil)
  if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
  a.onDone(result)
end

-- Begin capturing on `frame` (a Button/Frame that can take keyboard focus).
-- onDone(str) gets the binding string, "" for a clear, nil for a cancel.
function KC.Begin(frame, onDone, opts)
  if active then finish(nil) end
  local refuse = opts and opts.refuse or nil
  active = { frame = frame, onDone = onDone, refuse = refuse }
  frame:EnableKeyboard(true)
  frame:EnableMouseWheel(true)
  if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(false) end
  frame:SetScript("OnKeyDown", function(_, key)
    local s = KC.Format(key, IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown())
    if s == nil then return end
    if refuse and s ~= "" then
      local action = GetBindingAction and GetBindingAction(s, true)
      if action and refuse[action] then return end
    end
    finish(s)
  end)
  frame:SetScript("OnMouseDown", function(_, button)
    if button == "RightButton" then finish("") return end
    local s = KC.Format(button, IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown())
    if s then finish(s) end
  end)
  frame:SetScript("OnMouseWheel", function(_, delta)
    finish(KC.Format(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN", IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()))
  end)
end

function KC.End() finish(nil) end
function KC.IsActive() return active ~= nil end
