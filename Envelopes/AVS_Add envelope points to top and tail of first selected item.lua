-- @description Add Envelope Points at Start and End of First Selected Item (all track envelopes)
-- @version 1.1
-- @author AVS
-- @changelog
--   v1.1 • Now processes every track envelope lane under the first selected item, not just the first
-- @about
--   Adds an envelope point at the start and end of the first selected media item
--   for *every* envelope on that item’s track (volume, pan, FX params, etc.).
--
--   • Detects the first selected item and its time span.
--   • For each envelope found:
--       – Reads the envelope value at the item’s start and at (or just before) its end.
--       – Inserts points carrying those values at both boundaries.
--   • Sorts points, refreshes the UI, and wraps everything in an undo block.
--
-- @provides
--   [main] .
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0

------------------------------------------------
-- helpers
------------------------------------------------
local function get_last_envelope_value_in_range(env, start_time, end_time)
  local val = nil
  local cnt = reaper.CountEnvelopePoints(env)
  for i = 0, cnt - 1 do
    local _, pt_time, pt_val = reaper.GetEnvelopePoint(env, i)
    if pt_time >= start_time and pt_time <= end_time then
      val = pt_val                              -- keep updating until we step past end_time
    elseif pt_time > end_time then
      break
    end
  end
  return val
end

local function add_two_points(env, t_start, t_end)
  -- read values
  local _, start_val = reaper.Envelope_Evaluate(env, t_start, 0, 0)
  local last_val     = get_last_envelope_value_in_range(env, t_start, t_end)
  if not last_val then
    local _, v = reaper.Envelope_Evaluate(env, t_end, 0, 0)
    last_val = v
  end

  -- insert
  reaper.InsertEnvelopePoint(env, t_start, start_val, 0, 0, false, true)
  reaper.InsertEnvelopePoint(env, t_end,   last_val,  0, 0, false, true)

  reaper.Envelope_SortPoints(env)
end

------------------------------------------------
-- main
------------------------------------------------
local item = reaper.GetSelectedMediaItem(0, 0)
if not item then return end

local item_pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local item_end  = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
local track     = reaper.GetMediaItem_Track(item)
local env_cnt   = reaper.CountTrackEnvelopes(track)
if env_cnt == 0 then return end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

for i = 0, env_cnt - 1 do
  local env = reaper.GetTrackEnvelope(track, i)
  if env then add_two_points(env, item_pos, item_end) end
end

reaper.Undo_EndBlock("Add envelope points (all envelopes) at item bounds", -1)
reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
