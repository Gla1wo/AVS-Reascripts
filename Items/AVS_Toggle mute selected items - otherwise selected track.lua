--[[
-- @description Toggle Mute on Selected Items or Selected Tracks
--  Toggles mute state: 
--  - If media items are selected, toggles mute on those items.
--  - If no items are selected and tracks are selected, toggles mute on those tracks.
--  - If nothing is selected, does nothing.
-- @version 1.1
-- @author AVS
-- @changelog
--   + Initial release
--]]

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local itemCount = reaper.CountSelectedMediaItems(0)

if itemCount > 0 then
    -- Toggle mute state for each selected media item
    for i = 0, itemCount - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
            reaper.SetMediaItemInfo_Value(item, "B_MUTE", muted == 0 and 1 or 0)
        end
    end
else
    local trackCount = reaper.CountSelectedTracks(0)
    if trackCount > 0 then
        -- Toggle mute state for each selected track
        for j = 0, trackCount - 1 do
            local track = reaper.GetSelectedTrack(0, j)
            if track then
                local muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
                reaper.SetMediaTrackInfo_Value(track, "B_MUTE", muted == 0 and 1 or 0)
            end
        end
    end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Toggle mute on selected items or tracks", -1)

