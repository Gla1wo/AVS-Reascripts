-- @description Zoom to Show All Items on Selected Track
-- @version 1.0
-- @author AVS
-- @changelog Initial release
-- @about
--   This script zooms and adjusts the arrange view to show all media items on the first selected track in REAPER.
--
--   - Requires at least one track to be selected.
--   - Finds the earliest start and latest end times of all items on the selected track.
--   - Adds a small padding to ensure items are comfortably visible.
--   - Adjusts the arrange view to fit all items within the viewport.
--
-- @provides
--  [main] .
--   Arrange/AVS_Zoom to all items on selected track.lua
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0


function main()
    -- Get the number of selected tracks (expecting at least one)
    local selectedTrackCount = reaper.CountSelectedTracks(0)
    if selectedTrackCount == 0 then
        reaper.ShowMessageBox("No track selected.", "Error", 0)
        return
    end

    -- Get the first selected track
    local track = reaper.GetSelectedTrack(0, 0)

    -- Initialize variables to track the earliest start and latest end among items
    local earliestStart = math.huge
    local latestEnd = -math.huge

    -- Get the number of items on the selected track
    local itemCount = reaper.CountTrackMediaItems(track)

    -- Iterate through all items to find the earliest start and latest end
    for i = 0, itemCount-1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local itemEnd = itemStart + itemLength
        
        if itemStart < earliestStart then earliestStart = itemStart end
        if itemEnd > latestEnd then latestEnd = itemEnd end
    end

    -- Check if we found any items
    if earliestStart == math.huge or latestEnd == -math.huge then
        reaper.ShowMessageBox("No items found on the selected track.", "Error", 0)
        return
    end

    -- Calculate the total time span to show all items comfortably by adding a little padding
    local padding = 0.1 -- 10% padding on each side
    local totalSpan = latestEnd - earliestStart
    local startPadding = earliestStart - (totalSpan * padding)
    local endPadding = latestEnd + (totalSpan * padding)

    -- Adjust the zoom to show all items
    reaper.GetSet_ArrangeView2(0, true, 0, 0, startPadding, endPadding)
    reaper.UpdateArrange()
end

-- Execute the main function
main()

