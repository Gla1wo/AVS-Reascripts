--[[
    Description Skip Empty Space Between Items on Selected Track
    Author: AVS
    Version: 1.5
    About: This script runs in the background and skips any empty space between items on the selected track on playback.
                 
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

    for i = 0, numItems - 1 do
        local item = reaper.GetTrackMediaItem(track, i) -- Get the item
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION") -- Get item start position
        local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH") -- Get item end position

        -- Check if playback cursor is in the gap before this item
        if playPos < itemStart and (i == 0 or playPos > reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(track, i - 1), "D_POSITION") + reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(track, i - 1), "D_LENGTH")) then
            -- Ensure we only skip this gap once
            if not lastGapEnd or playPos >= lastGapEnd then
                reaper.SetEditCurPos(itemStart, true, false) -- Move edit cursor to the start of the item
                reaper.OnPlayButton() -- Ensure playback continues from the new position
                lastGapEnd = itemStart -- Mark the end of this gap
            end
            break
        end
    end
end

local function Main()
    SkipEmptySpace()
    reaper.defer(Main) -- Continue running in the background
end

Main() -- Start the script

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
