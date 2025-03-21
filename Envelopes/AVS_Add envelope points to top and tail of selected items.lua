-- @description Add Envelope Points at Start and End of Selected Items
-- @version 1.0
-- @author AVS
-- @changelog Initial release
-- @about
--   This script adds envelope points at the start and end of selected media items in REAPER.
--
--   - Retrieves the selected media items.
--   - Identifies the first visible envelope for the item's track.
--   - Finds the last envelope point value within the item's time range.
--   - Adds an envelope point at the item's start and end.
--   - Ensures envelope points are sorted and updates the arrangement.
--
-- @provides
--   [main] .lua
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0


local function get_last_envelope_point_value(env, start_time, end_time)
    local last_point_value = nil
    local num_points = reaper.CountEnvelopePoints(env)

    -- Iterate through all envelope points
    for i = 0, num_points - 1 do
        local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(env, i)
        -- Check if the point is within the item's time range
        if time >= start_time and time <= end_time then
            last_point_value = value -- Update the last point value
        elseif time > end_time then
            break -- Stop iterating once we're past the item's end time
        end
    end

    return last_point_value
end

-- Function to add an envelope point at a specific time with a specific value
local function add_envelope_point_at_time(env, time, value)
    reaper.InsertEnvelopePoint(env, time, value, 0, 0, false, true)
end

-- Function to process envelopes on a track for a given item
local function process_envelopes_for_item(track, item_pos, item_end)
    -- Iterate through all visible envelopes on the track
    local num_envelopes = reaper.CountTrackEnvelopes(track)
    for j = 0, num_envelopes - 1 do
        local envelope = reaper.GetTrackEnvelope(track, j)
        if envelope then
            -- Get the value of the last envelope point within the item's time range
            local last_point_value = get_last_envelope_point_value(envelope, item_pos, item_end)

            -- If no point exists within the item's time range, evaluate the envelope at the end time
            if not last_point_value then
                local retval, value = reaper.Envelope_Evaluate(envelope, item_end, 0, 0)
                last_point_value = value
            end

            -- Evaluate the envelope at the start of the item
            local retval, start_value = reaper.Envelope_Evaluate(envelope, item_pos, 0, 0)

            -- Add points at the beginning and end of the item
            add_envelope_point_at_time(envelope, item_pos, start_value) -- Start of the item
            add_envelope_point_at_time(envelope, item_end, last_point_value) -- End of the item

            -- Sort and update the envelope
            reaper.Envelope_SortPoints(envelope)
        end
    end
end

-- Main function to process all selected items
local function process_selected_items()
    -- Iterate through all selected items
    local num_items = reaper.CountSelectedMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            -- Get the item's position and length
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len

            -- Get the track that the item belongs to
            local track = reaper.GetMediaItem_Track(item)
            if track then
                -- Process all visible envelopes on the track
                process_envelopes_for_item(track, item_pos, item_end)
            end
        end
    end

    -- Update the arrange view
    reaper.UpdateArrange()
end

-- Run the script
reaper.Undo_BeginBlock()
process_selected_items()
reaper.Undo_EndBlock("Add envelope points to active envelopes based on selected items", -1)
