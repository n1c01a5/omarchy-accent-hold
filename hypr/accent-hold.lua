-- Accent Hold: press-and-hold detection inside Hyprland.
--
-- The plugin service loads this file with `hyprctl eval` and loads it again
-- after every Hyprland config reload. Loading it twice is safe: the previous
-- instance is torn down first.
--
-- Nothing here reads /dev/input. Hyprland reports each key press, and a
-- non-consuming bind per accent letter tells us which letter it was. When a
-- letter stays down for the hold delay, a custom IPC event asks the plugin
-- service to open the accent popup.

local previous = rawget(_G, "__accent_hold")
if previous then
  previous.stop()
end

local cfg = rawget(_G, "__accent_hold_config") or {}

local EVENT_PREFIX = "accent-hold>>"
local MIN_DELAY_MS = 120
local LEAD_MS = 60

local BLOCKING_KEYS = {
  "Control_L", "Control_R",
  "Alt_L", "Alt_R",
  "Super_L", "Super_R",
  "Meta_L", "Meta_R",
  "ISO_Level3_Shift",
}

local M = { binds = {}, subscriptions = {} }
_G.__accent_hold = M

local pending = nil
local last_pressed_keycode = nil

local function hold_delay()
  local configured = tonumber(cfg.hold_delay) or 0
  if configured > 0 then
    return math.max(MIN_DELAY_MS, math.floor(configured))
  end
  local repeat_delay = tonumber((hl.get_config("input.repeat_delay"))) or 600
  return math.max(MIN_DELAY_MS, repeat_delay - LEAD_MS)
end

local function any_down(keys)
  for _, key in ipairs(keys) do
    if hl.is_key_down(key) then
      return true
    end
  end
  return false
end

local function excluded(window)
  if not window then
    return false
  end
  local class = window.class or ""
  for _, pattern in ipairs(cfg.exclude_classes or {}) do
    local ok, matched = pcall(string.find, class, pattern)
    if ok and matched then
      return true
    end
  end
  return false
end

local function xy(value)
  if type(value) ~= "table" then
    return 0, 0
  end
  return value.x or value[1] or 0, value.y or value[2] or 0
end

-- Target point for the popup, in global logical coordinates.
local function anchor(window)
  if cfg.position == "pointer" or not window then
    local cursor = hl.get_cursor_pos() or {}
    local monitor = hl.get_monitor_at_cursor()
    return math.floor(cursor.x or 0), math.floor(cursor.y or 0), monitor and monitor.name or ""
  end
  local x, y = xy(window.at)
  local w, h = xy(window.size)
  return math.floor(x + w / 2), math.floor(y + h / 2), window.monitor and window.monitor.name or ""
end

local function cancel()
  pending = nil
  M.timer:set_enabled(false)
end

local function fire()
  M.timer:set_enabled(false)
  local hold = pending
  pending = nil
  if not hold or not hl.is_key_down(hold.letter) or any_down(BLOCKING_KEYS) then
    return
  end

  local window = hl.get_active_window()
  if excluded(window) then
    return
  end

  local x, y, monitor = anchor(window)
  local payload = string.format(
    '{"letter":"%s","shift":%s,"x":%d,"y":%d,"monitor":"%s"}',
    hold.letter, tostring(hold.shift), x, y, (monitor:gsub('[^%w%-_.]', ''))
  )
  hl.dispatch(hl.dsp.event(EVENT_PREFIX .. payload))
end

local function on_letter(letter)
  if any_down(BLOCKING_KEYS) then
    cancel()
    return
  end
  pending = {
    letter = letter,
    keycode = last_pressed_keycode,
    shift = hl.is_key_down("Shift_L") or hl.is_key_down("Shift_R"),
  }
  M.timer:set_timeout(hold_delay())
end

-- Every key event, before Hyprland runs its binds. Keys forwarded by the
-- input method (fcitx5) arrive here a second time with the same keycode,
-- so only a different keycode cancels the pending hold.
local function on_key(keycode, _, state)
  if state == 1 then
    last_pressed_keycode = keycode
    if pending and pending.keycode ~= keycode then
      cancel()
    end
  elseif pending and pending.keycode == keycode then
    cancel()
  end
end

M.timer = hl.timer(fire, { timeout = 1000, type = "repeat" })
M.timer:set_enabled(false)

table.insert(M.subscriptions, hl.on("input.keyboard.key", on_key))

for letter in (cfg.letters or ""):gmatch("%l") do
  table.insert(M.binds, hl.bind(letter, function() on_letter(letter) end, {
    non_consuming = true,
    ignore_mods = true,
    description = "Accent Hold: " .. letter,
  }))
end

function M.stop()
  pending = nil
  M.timer:set_enabled(false)
  for _, bind in ipairs(M.binds) do
    pcall(function() bind:remove() end)
  end
  for _, subscription in ipairs(M.subscriptions) do
    pcall(function() subscription:remove() end)
  end
  M.binds = {}
  M.subscriptions = {}
  _G.__accent_hold = nil
end

return #M.binds
