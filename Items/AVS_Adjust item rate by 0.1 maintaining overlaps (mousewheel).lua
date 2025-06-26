-- @description Adjust item rate with mouse-wheel (±0.1) while preserving overlaps/crossfades
-- @version 1.2
-- @author AVS
-- @changelog
--   +1.2  - Wheel delta uses 7-th return from get_action_context()
-- @about
--   Assign this to a mouse-wheel modifier (e.g. Alt-wheel on “Media item” context).
--   Wheel-up speeds selected items by +0.1, wheel-down slows by –0.1.
--   Items are stretched/shrunk and overlaps re-aligned so audio still meets in the same spot.
-- @provides
--   [main] .

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function sort_by_start(a, b)
  return reaper.GetMediaItemInfo_Value(a, "D_POSITION")
       < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
end

local function collect_selected_items_by_track()
  local by_track = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item  = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    by_track[track] = by_track[track] or {}
    by_track[track][#by_track[track]+1] = item
  end
  for _, list in pairs(by_track) do
    table.sort(list, sort_by_start)
  end
  return by_track
end

---------------------------------------------------------------------------
-- main
---------------------------------------------------------------------------
local BASE_STEP = 0.1
local MIN_RATE  = 0.001

-- wheel detection (slot 7)
local is_new, _, _, _, _, _, val = reaper.get_action_context()
if not is_new or val == 0 then return end
local RATE_DELTA = (val > 0) and  BASE_STEP or -BASE_STEP

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

local tracks_tbl = collect_selected_items_by_track()

-- pass 1: snapshot positions, lengths, rates, offsets
local track_data = {}
for track, list in pairs(tracks_tbl) do
  local t = {items = {}, offsets = {}}
  track_data[track] = t

  for i, item in ipairs(list) do
    local pos0  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len0  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local take  = reaper.GetActiveTake(item)
    local r0    = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
    local r1    = math.max(MIN_RATE, r0 + RATE_DELTA)

    t.items[i] = {item=item, pos0=pos0, len0=len0, rate0=r0, new_rate=r1}

    if i > 1 then
      local prev     = list[i-1]
      local prev_end = reaper.GetMediaItemInfo_Value(prev,"D_POSITION")
                     + reaper.GetMediaItemInfo_Value(prev,"D_LENGTH")
      t.offsets[i]   = pos0 - prev_end                -- negative = overlap
    end
  end
end

-- pass 2: update rates & lengths
for _, t in pairs(track_data) do
  for _, it in ipairs(t.items) do
    local item  = it.item
    local scale = it.rate0 / it.new_rate
    local len1  = it.len0 * scale

    for tk = 0, reaper.CountTakes(item)-1 do
      local take = reaper.GetTake(item, tk)
      if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", it.new_rate) end
    end
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len1)

    it.len1, it.scale = len1, scale
  end
end

-- pass 3: restore gaps / scaled overlaps
for _, t in pairs(track_data) do
  local items, offs = t.items, t.offsets
  items[1].new_pos = items[1].pos0
  reaper.SetMediaItemInfo_Value(items[1].item,"D_POSITION",items[1].new_pos)

  for i = 2, #items do
    local prev, cur = items[i-1], items[i]
    local off       = offs[i] or 0
    if off < 0 then off = off * prev.scale end        -- scale overlaps only
    cur.new_pos = prev.new_pos + prev.len1 + off
    reaper.SetMediaItemInfo_Value(cur.item, "D_POSITION", cur.new_pos)
  end
end

reaper.UpdateArrange()
local act = (RATE_DELTA > 0) and "Increase" or "Decrease"
reaper.Undo_EndBlock(act.." item rates by 0.1 (mouse-wheel)", -1)
reaper.PreventUIRefresh(-1)

