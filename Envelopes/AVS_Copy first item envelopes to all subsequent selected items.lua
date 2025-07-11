-- @description Copy envelope points from the first selected item to each additional selected item
-- @version 1.1
-- @author AVS
-- @changelog
--   v1.1 • Clears the target time-range and pastes once, preventing duplicates
--        • Only touches envelopes that belong to the destination item’s track/take
--        • Minor speed-ups (UI refresh suspend, single Undo point)
-- @about
--   • Select at least two items.  
--   • The script grabs every envelope point that lives inside the FIRST item’s bounds  
--     (track or take envelopes).  
--   • Those points are then pasted, once, at the start of every other selected item.  
--   • Existing points in the target range are wiped first, so each item ends up with
--     exactly the same number—and shape—of points as the source.  
-- @provides
--   [main] .
-- @link https://www.andrewvscott.com/
-- @minimum_reaper_version 6.0

----------------------------------------
-- HELPERS
----------------------------------------
local function copy_points_from_envelope(env, src_start, src_end)
  local pts = {}
  local cnt = reaper.CountEnvelopePoints(env)
  for i = 0, cnt - 1 do
    local ok, t, v, s, ten, sel = reaper.GetEnvelopePoint(env, i)
    if ok and t >= src_start and t <= src_end then
      pts[#pts + 1] = {off = t - src_start, val = v, shape = s, tens = ten, sel = sel}
    end
  end
  return pts
end

local function delete_and_paste(env, item_start, item_end, pts)
  -- blow away anything already in the target slot
  reaper.DeleteEnvelopePointRange(env, item_start, item_end)
  for _, p in ipairs(pts) do
    reaper.InsertEnvelopePoint(env,
      item_start + p.off, p.val, p.shape, p.tens, p.sel, true)
  end
  reaper.Envelope_SortPoints(env)
end

----------------------------------------
-- MAIN
----------------------------------------
local sel_cnt = reaper.CountSelectedMediaItems(0)
if sel_cnt < 2 then
  reaper.ShowMessageBox('Select at least TWO items.', 'Copy envelope points', 0)
  return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local src_item      = reaper.GetSelectedMediaItem(0, 0)
local src_track     = reaper.GetMediaItemTrack(src_item)
local src_take      = reaper.GetActiveTake(src_item)         -- may be nil
local src_start     = reaper.GetMediaItemInfo_Value(src_item, 'D_POSITION')
local src_end       = src_start + reaper.GetMediaItemInfo_Value(src_item, 'D_LENGTH')

-- 1. Harvest points from every visible envelope that belongs to the SOURCE item
local env_data = {}  -- [env_pointer] = {points=table, name=string, is_take=bool}

-- Track envelopes on the source track
for e = 0, reaper.CountTrackEnvelopes(src_track) - 1 do
  local env = reaper.GetTrackEnvelope(src_track, e)
  local pts = copy_points_from_envelope(env, src_start, src_end)
  if #pts > 0 then
    local _, name = reaper.GetEnvelopeName(env, '')
    env_data[#env_data + 1] = {name = name, points = pts, is_take = false}
  end
end

-- Take envelopes on the source take (if any)
if src_take then
  for e = 0, reaper.CountTakeEnvelopes(src_take) - 1 do
    local env = reaper.GetTakeEnvelope(src_take, e)
    local pts = copy_points_from_envelope(env, src_start, src_end)
    if #pts > 0 then
      local _, name = reaper.GetEnvelopeName(env, '')
      env_data[#env_data + 1] = {name = name, points = pts, is_take = true}
    end
  end
end

if #env_data == 0 then
  reaper.ShowMessageBox('No envelope points found in the first item.', 'Copy envelope points', 0)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock('Copy envelope points (no points)', -1)
  return
end

-- 2. Paste into every other selected item
for i = 1, sel_cnt - 1 do
  local dst_item   = reaper.GetSelectedMediaItem(0, i)
  local dst_track  = reaper.GetMediaItemTrack(dst_item)
  local dst_take   = reaper.GetActiveTake(dst_item)
  local dst_start  = reaper.GetMediaItemInfo_Value(dst_item, 'D_POSITION')
  local dst_end    = dst_start + reaper.GetMediaItemInfo_Value(dst_item, 'D_LENGTH')

  for _, ed in ipairs(env_data) do
    local target_env = nil

    if ed.is_take then
      if dst_take then
        target_env = reaper.GetTakeEnvelopeByName(dst_take, ed.name)
      end
    else
      -- track envelope: only touch if item sits on that track
      target_env = reaper.GetTrackEnvelopeByName(dst_track, ed.name)
    end

    if target_env then
      delete_and_paste(target_env, dst_start, dst_end, ed.points)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock('Copy envelope points to selected items', -1)
