-- @description Remove All Pitch Envelope Points from Selected Items
-- @version 1.1
-- @author AVS
-- @changelog
--   # Fixed crash: replaced faulty point-deletion loop (used GetEnvelopePointByTime incorrectly)
--     with a single DeleteEnvelopePointRange over the full envelope span
--   # Added undo block and PreventUIRefresh for performance/safety
--   # Minor code clean-up and extra nil-checks
-- @about
--   Removes every pitch-envelope point from every take of each selected media item.
--   • Iterates through all selected items and all of their takes  
--   • If a take contains a “Pitch” envelope, deletes the entire envelope point range  
--   • Sorts envelopes, restores UI, and updates the arrange view  
--
-- @provides
--   [main] .lua
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0

local function Main()
  local item_count = reaper.CountSelectedMediaItems(0)
  if item_count == 0 then return end

  for i = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local take_count = reaper.CountTakes(item)
      for j = 0, take_count - 1 do
        local take = reaper.GetTake(item, j)
        if take then
          local pitch_env = reaper.GetTakeEnvelopeByName(take, "Pitch")
          if pitch_env then
            -- Delete *all* points: use an extremely wide range
            reaper.DeleteEnvelopePointRange(pitch_env, -math.huge, math.huge)
            reaper.Envelope_SortPoints(pitch_env)
          end
        end
      end
    end
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

Main()

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Remove all pitch envelope points from selected items", -1)

