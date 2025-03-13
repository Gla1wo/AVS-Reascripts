--[[
    Description: Skip Empty Space Between Items on Selected Track and Loop Back to First Item
    Author: AVS
    Version: 1.0
    About: This script runs in the background, skipping any empty space between items on the selected track on playback.
           After the final item has finished playing, playback jumps back to the first item and continues skipping silence.
--]]

local _, _, section, cmdID = reaper.get_action_context()

local lastGapEnd = nil -- Track the end of the last gap to avoid repeated skips

local function SkipEmptySpace()
    local isPlaying = reaper.GetPlayState() == 1 -- Check if REAPER is currently playing
    if not isPlaying then
        lastGapEnd = nil -- Reset when playback stops
        return
    end

    local track = reaper.GetSelectedTrack(0, 0) -- Get the first selected track
    if not track then return end -- Exit if no track is selected

    local playPos = reaper.GetPlayPosition() -- Get current playback position
    local numItems = reaper.CountTrackMediaItems(track) -- Get number of items on the track
    if numItems == 0 then return end -- Exit if no items exist

    local firstItem = reaper.GetTrackMediaItem(track, 0)
    local firstItemStart = reaper.GetMediaItemInfo_Value(firstItem, "D_POSITION")

    local lastItem = reaper.GetTrackMediaItem(track, numItems - 1)
    local lastItemStart = reaper.GetMediaItemInfo_Value(lastItem, "D_POSITION")
    local lastItemEnd = lastItemStart + reaper.GetMediaItemInfo_Value(lastItem, "D_LENGTH")

    for i = 0, numItems - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

        -- Check if playback cursor is in a gap before this item
        if playPos < itemStart and (i == 0 or playPos > reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(track, i - 1), "D_POSITION") + reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(track, i - 1), "D_LENGTH")) then
            if not lastGapEnd or playPos >= lastGapEnd then
                reaper.SetEditCurPos(itemStart, true, false) -- Move playback to the start of the next item
                reaper.OnPlayButton()
                lastGapEnd = itemStart -- Mark the end of this gap
            end
            return
        end
    end

    -- If playback goes past the last item, jump to the first item and continue skipping silence
    if playPos >= lastItemEnd then
        reaper.SetEditCurPos(firstItemStart, true, false) -- Move playback to the start of the first item
        reaper.OnPlayButton()
        lastGapEnd = nil -- Reset to ensure silence skipping continues
    end
end

local function Main()
    SkipEmptySpace()
    reaper.defer(Main) -- Continue running in the background
end

Main() -- Start the script

function setup()
    reaper.SetToggleCommandState(section, cmdID, 1)
    reaper.RefreshToolbar2(section, cmdID)
end

function exit()
    reaper.SetToggleCommandState(section, cmdID, 0)
    reaper.RefreshToolbar2(section, cmdID)
    return reaper.defer(function() end)
end

setup()
reaper.atexit(exit)

