-- @description Shift Source Content of Selected Items to Left Edge
-- @version 1.0
-- @author AVS
-- @changelog Initial release
-- @about
--   This script shifts the start of the source content of selected items to their left edge without changing item bounds.
--
--   - Works on selected media items (excluding MIDI).
--   - Resets the take's start offset to 0, aligning the source content with the item's left edge.
--   - Does not modify item length or play rate.
--   - Updates the REAPER interface to reflect changes.
-- @provides
--   Items/AVS_Shift source content start to item left edge.lua
--   [main] .lua
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0


function main()
    -- Count the number of selected items
    local itemCount = reaper.CountSelectedMediaItems(0)

    if itemCount == 0 then
        return -- No selected items, exit the script
    end

    -- Begin undo block
    reaper.Undo_BeginBlock()

    for i = 0, itemCount-1 do
        -- Get the selected item
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            -- Get the active take in the item
            local take = reaper.GetActiveTake(item)
            if take and not reaper.TakeIsMIDI(take) then
                -- Set the take's start offset to 0 to align the source content's start with the item's left edge
                reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)

                -- Optional: Adjust the take's play rate if necessary to fit the item bounds
                -- This is not strictly required for this task but could be considered if adjusting play rate is desired
                -- local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                -- reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", <desired_play_rate>)
            end
        end
    end

    -- End undo block
    reaper.Undo_EndBlock("Shift Source Content of Selected Items to Left Edge", -1)

    -- Update REAPER's interface to reflect changes
    reaper.UpdateArrange()
end

-- Check if REAPER's main window is open (valid context for script execution)
if reaper.GetMainHwnd() then
    main()
end

