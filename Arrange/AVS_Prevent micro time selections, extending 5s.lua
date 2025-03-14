---- @description Prevent micro time selections, extending 5s
---- @version 1.3
---- @author AVS
---- @changelog
----   - Fixed issue where an unwanted time selection was created at the start of the timeline when none existed.
----   - Now only extends an existing time selection if it is shorter than 50ms.
----   - Ensured compatibility with background execution.
---- @about
----   This script extends the loop playback if the loop selection is less than 50 milliseconds.
----   It adds 5 additional seconds of playback past the loop end point.
----   It avoids creating a time selection when none exists.
-- @provides
--   [main] .
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0

local _, _, section, cmdID = reaper.get_action_context()

function main()
  if reaper.GetPlayState() > 0 then
    local loop_start, loop_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false) -- get loop selection
    
    -- Ensure a time selection exists before modifying it
    if loop_start ~= loop_end then
      local loop_length = loop_end - loop_start -- calculate loop length
      if loop_length < 0.05 then -- check if loop length is less than 50 milliseconds
        reaper.GetSet_LoopTimeRange(true, false, loop_start, loop_end + 5, false) -- extend loop end by 5 seconds
      end
    end
  end
  reaper.defer(main)
end

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
reaper.defer(main) -- run the script in the background

