-- @description Move playback instantly to a random item on the selected track
-- @version 1.1
-- @author AVS
-- @changelog
--   v1.1  - Jump is now truly instant during playback by pausing,
--             repositioning, and resuming instead of smooth-seeking.
--          - Dropped UI-refresh hold (no need anymore).
-- @about
--   Picks a random media item on the first selected track and
--   teleports the edit/play cursor there.  
--   - Works whether you’re stopped or playing.  
--   - Centers the arrange view on the new spot.  
--   - Gracefully aborts if nothing’s selected or the track is empty.
--
-- @provides
--   [main] .
-- @link https://www.andrewvscott.com/

------------------------------------------------
-- helpers
------------------------------------------------
local function abort(msg)
  reaper.Undo_EndBlock("Move playback to random item (aborted)", -1)
  reaper.ShowMessageBox(msg, "Random Item Playhead", 0)
  return
end

------------------------------------------------
-- main
------------------------------------------------
reaper.Undo_BeginBlock()

-- 1) Grab the first selected track
local track = reaper.GetSelectedTrack(0, 0)
if not track then abort("No track selected.") return end

-- 2) Verify it has items
local item_cnt = reaper.CountTrackMediaItems(track)
if item_cnt == 0 then abort("Selected track contains no media items.") return end

-- 3) Pick a random item
math.randomseed(reaper.time_precise() * 1e6)
local idx  = math.random(0, item_cnt - 1)
local item = reaper.GetTrackMediaItem(track, idx)
if not item then abort("Unable to retrieve random item.") return end
local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

-- 4) Instant-jump logic
local play_state = reaper.GetPlayState()
local is_playing = (play_state & 1) == 1  -- bit-wise: 1 == playing

if is_playing then
  reaper.OnPauseButton()              -- quick pause
end

reaper.SetEditCurPos(pos, true, false) -- move view/cursor, don't auto-seek

if is_playing then
  reaper.OnPauseButton()              -- un-pause (continues from new pos)
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Move playback instantly to random item on selected track", -1)

