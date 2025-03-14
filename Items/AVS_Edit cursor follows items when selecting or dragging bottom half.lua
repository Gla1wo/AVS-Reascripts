-- @description Edit cursor follows items when selecting or dragging bottom half
-- @version 1.0
-- @author AVS
-- @changelog Initial release
-- @about
--   This script moves the playhead to the start of the selected media item without changing 
--   the horizontal or vertical view in REAPER. It runs as a background toggleable action.
--
--   - Detects left clicks on the bottom half of media items and moves the playhead to their start.
--   - Restores the previous arrange and vertical scroll position after moving the playhead.
--   - Runs in the background, continuously checking for selected items.
--   - Supports toolbar toggling (on/off state).
--
-- @provides
--   [main] .
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0


local _, _, section, cmdID = reaper.get_action_context()

local function move_playhead_to_start_of_selected_item()
    reaper.Main_OnCommandEx(41173, 0, 0) -- go to start of selected item
end

local function store_previous_arrange_view()
    local start_time, end_time = reaper.GetSet_ArrangeView2(0, false, 0, 0)
    return start_time, end_time
end

local function restore_previous_arrange_view(start_time, end_time)
    reaper.GetSet_ArrangeView2(0, true, 0, 0, start_time, end_time)
end

local function store_previous_vertical_scroll_position()
    local vertical_scroll_position = reaper.SNM_GetIntConfigVar("vzoom2", -1)
    return vertical_scroll_position
end

local function restore_previous_vertical_scroll_position(vertical_scroll_position)
    reaper.SNM_SetIntConfigVar("vzoom2", vertical_scroll_position)
    reaper.UpdateArrange() -- Update the arrange view to reflect the change
end

local arrange_hwnd = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)

-- Add variables to keep track of the previous state
local prevClick = 0
local prevSelectedItemCount = 0

local function media_item_left_click()
    -- check if left drag was performed on a media item's bottom half
    local x, y = reaper.GetMousePosition()
    local item = reaper.GetItemFromPoint(x, y, true)
    local click = reaper.JS_Mouse_GetState(1)
    if item then
        local track = reaper.GetTrackFromPoint(x, y)
        local tr_y = reaper.GetMediaTrackInfo_Value(track, "I_TCPY")
        local item_y = reaper.GetMediaItemInfo_Value(item, "I_LASTY")
        local item_h = reaper.GetMediaItemInfo_Value(item, "I_LASTH")
        local item_center = tr_y + item_y + (item_h / 2)
        local _, cy = reaper.JS_Window_ScreenToClient(arrange_hwnd, x, y)
        
        -- Modify the condition to check if the mouse button was just released
        if cy >= item_center and prevClick == 1 and click == 0 then
            -- store previous arrange view
            local prev_start_time, prev_end_time = store_previous_arrange_view()
            
            -- store previous vertical scroll position
            local prev_vertical_scroll_position = store_previous_vertical_scroll_position()
            
            -- move playhead to start of selected item
            move_playhead_to_start_of_selected_item()

            -- restore previous arrange view
            restore_previous_arrange_view(prev_start_time, prev_end_time)
            
            -- restore previous vertical scroll position
            restore_previous_vertical_scroll_position(prev_vertical_scroll_position)
        end
    end
    -- Update the previous mouse state
    prevClick = click
end

-- Add a function to check for selected items and move the playhead to the start of the selected items
local function check_for_selected_items()
    local selected_item_count = reaper.CountSelectedMediaItems(0)
    if selected_item_count > 0 and selected_item_count ~= prevSelectedItemCount then
        -- store previous arrange view
        local prev_start_time, prev_end_time = store_previous_arrange_view()
        
        -- store previous vertical scroll position
        local prev_vertical_scroll_position = store_previous_vertical_scroll_position()
        
        -- move playhead to start of selected item
        move_playhead_to_start_of_selected_item()

        -- restore previous arrange view
        restore_previous_arrange_view(prev_start_time, prev_end_time)
        
        -- restore previous vertical scroll position
        restore_previous_vertical_scroll_position(prev_vertical_scroll_position)
    end
    -- Update the previous selection state
    prevSelectedItemCount = selected_item_count
end

local function defer()
    media_item_left_click()
    check_for_selected_items()
    reaper.defer(defer)
end

function setup()
  reaper.SetToggleCommandState( section, cmdID, 1 )
  reaper.RefreshToolbar2( section, cmdID )
end

function exit()
  reaper.SetToggleCommandState( section, cmdID, 0 )
  reaper.RefreshToolbar2( section, cmdID )
  return reaper.defer(function() end)
end

setup()
reaper.atexit(exit)

-- run the script in the background
--reaper.atexit(function() end) -- disable atexit function
defer() -- start main function

