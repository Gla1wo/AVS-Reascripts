-- @description Copy and Paste Envelope Points from First Selected Item to Others
-- @version 1.0
-- @author AVS
-- @changelog Initial release
-- @about
--   This script copies all envelope points from the first selected item and pastes them 
--   at the start of each subsequently selected item in REAPER.
--
--   - Requires at least two selected media items.
--   - Finds all envelope points within the first selected item's time range.
--   - Pastes the copied envelope points at the corresponding position in other selected items.
--   - Works across all tracks containing envelopes.
-- @provides
--   Envelopes/AVS_Copy first item envelopes to all subsequent selected items.lua
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0


function copyAndPasteEnvelopePoints()
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count < 2 then
        reaper.ShowMessageBox("You need at least two items selected to use this script.", "Not Enough Items", 0)
        return
    end

    local source_item = reaper.GetSelectedMediaItem(0, 0)
    local source_item_start = reaper.GetMediaItemInfo_Value(source_item, "D_POSITION")
    local source_item_end = source_item_start + reaper.GetMediaItemInfo_Value(source_item, "D_LENGTH")
    
    -- Loop through all tracks in the project
    for track_idx = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, track_idx)

        -- Loop through all envelopes in the track
        for env_idx = 0, reaper.CountTrackEnvelopes(track) - 1 do
            local env = reaper.GetTrackEnvelope(track, env_idx)
            local pointsToCopy = {}

            -- Find and store envelope points under the first selected item
            local pt_count = reaper.CountEnvelopePoints(env)
            for pt_idx = 0, pt_count - 1 do
                local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(env, pt_idx)
                if time >= source_item_start and time <= source_item_end then
                    table.insert(pointsToCopy, {time = time - source_item_start, value = value, shape = shape, tension = tension, selected = selected})
                end
            end

            -- Skip if no points to copy
            if #pointsToCopy == 0 then goto continue end

            -- Apply stored points to subsequent selected items
            for item_idx = 1, item_count - 1 do
                local item = reaper.GetSelectedMediaItem(0, item_idx)
                local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

                -- Optionally clear existing points in the target area before pasting
                -- This step is skipped in this script for simplicity, but can be added if needed

                for _, pt in ipairs(pointsToCopy) do
                    local new_time = item_start + pt.time
                    reaper.InsertEnvelopePoint(env, new_time, pt.value, pt.shape, pt.tension, pt.selected, true) -- Insert point
                end
                reaper.Envelope_SortPoints(env)
            end

            ::continue::
        end
    end

    reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
copyAndPasteEnvelopePoints()
reaper.Undo_EndBlock("Copy and Paste Envelope Points", -1)

