-- @description Match Length and Fade-Out to First Selected Item on Each Track, Ignoring Crossfades
-- @version 1.0
-- @author AVS
-- @changelog Initial release
-- @about
--   This script adjusts the length and fade-out of each selected media item on a given track 
--   to match the length and fade-out of the first selected item on that same track, while 
--   avoiding adjusting items involved in crossfades.
--
--   - Requires at least two selected media items.
--   - Groups selected items by track and uses the first selected item as a reference.
--   - Ignores items that are involved in crossfades.
-- @provides
--   Items/AVS_Match item length and fadeout to first item.lua
--   [main] .lua
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0


function main()
    local totalSelItems = reaper.CountSelectedMediaItems(0)
    if totalSelItems < 2 then
        reaper.ShowMessageBox("You need to select at least two items in total for this script to work.", "Not Enough Items Selected", 0)
        return
    end

    -- Group selected items by track and record the first selected item on each track as the reference.
    local trackItems = {}    -- key: track pointer, value: array of selected items on that track
    local trackRefItem = {}  -- key: track pointer, value: first selected item on that track

    for i = 0, totalSelItems - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        if not trackItems[track] then
            trackItems[track] = {}
            trackRefItem[track] = item  -- The first encountered item on this track becomes the reference.
        end
        table.insert(trackItems[track], item)
    end

    -- For each track, sort the items by their start position for a reliable crossfade check.
    for track, items in pairs(trackItems) do
        table.sort(items, function(a, b)
            return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
        end)
    end

    -- Process each track group.
    for track, items in pairs(trackItems) do
        local refItem = trackRefItem[track]
        local refLength = reaper.GetMediaItemInfo_Value(refItem, "D_LENGTH")
        local refFadeOut = reaper.GetMediaItemInfo_Value(refItem, "D_FADEOUTLEN")

        -- Iterate over the sorted items for this track.
        for idx, item in ipairs(items) do
            -- Skip the reference item.
            if item ~= refItem then
                local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local itemEnd = itemStart + itemLength

                -- Check for a crossfade with the next item in timeline order.
                local isCrossfade = false
                local nextItem = items[idx + 1]
                if nextItem then
                    local nextStart = reaper.GetMediaItemInfo_Value(nextItem, "D_POSITION")
                    if itemEnd > nextStart then
                        isCrossfade = true
                    end
                end

                -- Only adjust items not involved in a crossfade.
                if not isCrossfade then
                    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", refLength)
                    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", refFadeOut)
                end
            end
        end
    end

    reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Match Length and Fade-Out to First Selected Item on Each Track, Ignoring Crossfades", -1)

