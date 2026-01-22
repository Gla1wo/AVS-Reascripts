-- @description Set Fade Curve from Vertical Cursor Position
-- @author AVS
-- @version 1.2
-- @about .
--   Sets the fade curve of the fade under the mouse cursor based on vertical position.
--   - Cursor near TOP of item = Cosine curve (value 1.0)
--   - Cursor near BOTTOM of item = Exponential curve (value -1.0)
--   Intended for use with a keyboard shortcut. Fails silently if no fade is detected.
-- @changelog
--   v1.2: Inverted curve logic for fade-ins to maintain visual consistency
--   v1.1: Added easing for easier extreme values, descriptive undo message

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~ USER CONFIG ~~~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- Easing power: Lower = easier to reach extreme curves (0.5 = sqrt, 1.0 = linear)
-- Recommended range: 0.4 to 0.7
local EASING_POWER = 0.5

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~ EXTENSION CHECK ~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- Check for SWS Extension (required for mouse context functions)
if not reaper.BR_GetMouseCursorContext then
  return -- SWS not installed, fail silently
end

-- Check for js_ReaScriptAPI (required for vertical position calculation)
if not reaper.JS_Window_FindChildByID then
  return -- js_ReaScriptAPI not installed, fail silently
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~~~~ FUNCTIONS ~~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

local function getItemUnderCursor()
  reaper.BR_GetMouseCursorContext()
  return reaper.BR_GetMouseCursorContext_Item()
end

local function getMouseTimePosition()
  return reaper.BR_GetMouseCursorContext_Position()
end

local function isOverFade(item, mouse_pos)
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local fade_in_len = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
  local fade_out_len = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  
  -- Also check auto-fades if manual fades aren't set
  if fade_in_len == 0 then
    fade_in_len = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO")
  end
  if fade_out_len == 0 then
    fade_out_len = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO")
  end
  
  local fade_in_end = item_pos + fade_in_len
  local fade_out_start = item_pos + item_len - fade_out_len
  
  local over_fade_in = fade_in_len > 0 and mouse_pos >= item_pos and mouse_pos <= fade_in_end
  local over_fade_out = fade_out_len > 0 and mouse_pos >= fade_out_start and mouse_pos <= item_pos + item_len
  
  return over_fade_in, over_fade_out
end

local function applyEasing(relative_y)
  -- Convert linear position to eased position for easier extreme values
  -- relative_y: 0 = top, 1 = bottom
  
  -- Calculate deviation from center (0 at middle, 1 at edges)
  local deviation = math.abs(relative_y - 0.5) * 2
  
  -- Apply power curve - values < 1 make extremes easier to reach
  local eased_deviation = deviation ^ EASING_POWER
  
  -- Determine sign based on which half we're in (top = positive, bottom = negative)
  local sign = (relative_y < 0.5) and 1 or -1
  
  -- Return curve value: +1 at top, -1 at bottom
  return sign * eased_deviation
end

local function getVerticalCurveValue(item)
  local mouse_x, mouse_y = reaper.GetMousePosition()
  local track = reaper.GetMediaItem_Track(item)
  
  -- Get arrange window
  local hwnd = reaper.GetMainHwnd()
  local arrange = reaper.JS_Window_FindChildByID(hwnd, 1000)
  if not arrange then return 0 end
  
  -- Get arrange window client rectangle (screen coordinates)
  local retval, ar_left, ar_top, ar_right, ar_bottom = reaper.JS_Window_GetClientRect(arrange)
  if not retval then return 0 end
  
  -- Get track dimensions
  local track_y = reaper.GetMediaTrackInfo_Value(track, "I_TCPY")
  local track_h = reaper.GetMediaTrackInfo_Value(track, "I_WNDH")
  
  if track_h <= 0 then return 0 end
  
  -- Calculate track bounds in screen coordinates
  local track_top_screen = ar_top + track_y
  
  -- Calculate relative Y position (0 = top of track, 1 = bottom of track)
  local relative_y = (mouse_y - track_top_screen) / track_h
  relative_y = math.max(0, math.min(1, relative_y)) -- Clamp to 0-1
  
  -- Apply easing and return curve value
  return applyEasing(relative_y)
end

local function setFadeCurve(item, curve, is_fade_in, is_fade_out)
  if is_fade_in then
    -- Invert curve for fade-ins to maintain visual consistency
    reaper.SetMediaItemInfo_Value(item, "D_FADEINDIR", -curve)
  end
  if is_fade_out then
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", curve)
  end
  reaper.UpdateItemInProject(item)
end

local function getFadeTypeString(is_fade_in, is_fade_out)
  if is_fade_in and is_fade_out then
    return "fade in/out"
  elseif is_fade_in then
    return "fade in"
  else
    return "fade out"
  end
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~~~~~~ MAIN ~~~~~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

local function main()
  -- Get item under cursor
  local item = getItemUnderCursor()
  if not item then return end -- No item under cursor, fail silently
  
  -- Get mouse timeline position
  local mouse_pos = getMouseTimePosition()
  
  -- Check if cursor is over a fade
  local over_fade_in, over_fade_out = isOverFade(item, mouse_pos)
  if not over_fade_in and not over_fade_out then return end -- Not over any fade, fail silently
  
  -- Calculate curve value based on vertical position
  local curve = getVerticalCurveValue(item)
  
  -- Get fade type string for undo message
  local fade_type = getFadeTypeString(over_fade_in, over_fade_out)
  
  -- Determine displayed curve value (inverted for fade-in only scenarios)
  local display_curve = curve
  if over_fade_in and not over_fade_out then
    display_curve = -curve
  end
  
  -- Apply curve to the appropriate fade(s)
  reaper.Undo_BeginBlock()
  setFadeCurve(item, curve, over_fade_in, over_fade_out)
  reaper.Undo_EndBlock(string.format("Set %s curve to %.2f", fade_type, display_curve), -1)
end

main()
