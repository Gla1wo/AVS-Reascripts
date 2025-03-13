-- @description Match Length of Selected Items to First Selected Item
-- @version 1.0
-- @author AVS
-- @changelog Initial release
-- @about
--   This script adjusts the length of each selected media item after the first one 
--   to match the length of the first selected item in REAPER.
--
--   - Requires at least two selected media items.
--   - The first selected item is used as the reference for length.
--   - All subsequent selected items will be adjusted to match the reference length.
-- @provides
--   Items/AVS_Match item length to first item.lua
--   [main] .lua
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0


function main()
    -- Check how many items are selected in the project
    local itemCount = reaper.CountSelectedMediaItems(0)
    if itemCount < 2 then
        reaper.ShowMessageBox("You need to select at least two items for this script to work.", "Not Enough Items Selected", 0)
        return
    end

    -- Get the first selected item and its length
    local firstItem = reaper.GetSelectedMediaItem(0, 0)
    local firstItemStart = reaper.GetMediaItemInfo_Value(firstItem, "D_POSITION")
    local firstItemLength = reaper.GetMediaItemInfo_Value(firstItem, "D_LENGTH")

    -- Iterate over the remaining selected items
    for i = 1, itemCount - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

        -- Set the end point of the item to match the length of the first item
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", firstItemLength)
    end

    -- Update the arrangement view and data structures
    reaper.UpdateArrange()
end

-- Prevent undo points being created for every small change
reaper.Undo_BeginBlock()

-- Run the main function
main()

-- Create a single undo point for the action taken
reaper.Undo_EndBlock("Match Length of Selected Items to First Selected Item", -1)

