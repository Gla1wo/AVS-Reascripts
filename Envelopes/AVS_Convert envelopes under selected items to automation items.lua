-- @description Convert envelopes under selected items to automation items (full length + tail)
-- @version 1.2
-- @author AVS
-- @changelog
--   v1.2 • “Next‑item” search now scans every track item (not just selected ones).
--         • When no later item exists, range ends at last envelope point on the lane.
-- @provides
--   [main] .
-- @about
--   For each selected media item, create an automation item on every track envelope
--   that covers:
--       • 0.5 s before the item’s start
--       • The entire item length
--       • Up to 0.5 s before the next later item on that track (if any)
--       • If there is **no** later item, the window extends through the last
--         envelope point so post‑item automation is preserved.

local proj      = 0
local sel_cnt   = reaper.CountSelectedMediaItems(proj)
if sel_cnt == 0 then return end

-- Gather selected items (sorted by start time)
local sel_items = {}
for i = 0, sel_cnt - 1 do
  local it  = reaper.GetSelectedMediaItem(proj, i)
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  table.insert(sel_items, {it = it, pos = pos, len = len})
end
table.sort(sel_items, function(a, b) return a.pos < b.pos end)

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for _, data in ipairs(sel_items) do
  local item        = data.it
  local trk         = reaper.GetMediaItem_Track(item)
  local item_start  = data.pos
  local item_end    = data.pos + data.len
  local range_start = math.max(0, item_start - 0.5)

  -- ── Find the next later item on this track (if any) ──────────────────────────
  local next_start  = nil
  local trk_cnt     = reaper.CountTrackMediaItems(trk)
  for j = 0, trk_cnt - 1 do
    local it2  = reaper.GetTrackMediaItem(trk, j)
    local pos2 = reaper.GetMediaItemInfo_Value(it2, "D_POSITION")
    if pos2 > item_start + 1e-10 then               -- later than this item’s start
      if not next_start or pos2 < next_start then
        next_start = pos2
      end
    end
  end

  -- ── Determine window end ─────────────────────────────────────────────────────
  local range_end
  if next_start then
    range_end = math.max(item_end, next_start - 0.5)
  else
    -- No later item: extend to the last envelope point on any lane
    local env_last = item_end
    local env_cnt  = reaper.CountTrackEnvelopes(trk)
    for e = 0, env_cnt - 1 do
      local env      = reaper.GetTrackEnvelope(trk, e)
      local pt_cnt   = reaper.CountEnvelopePoints(env)
      if pt_cnt > 0 then
        local _, t = reaper.GetEnvelopePoint(env, pt_cnt - 1)
        env_last   = math.max(env_last, t)
      end
    end
    range_end = env_last
  end

  if range_end - range_start > 0 then
    local env_cnt = reaper.CountTrackEnvelopes(trk)
    for e = 0, env_cnt - 1 do
      local env = reaper.GetTrackEnvelope(trk, e)
      reaper.InsertAutomationItem(env, -1, range_start, range_end - range_start)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Convert envelopes under selected items → automation items (v1.2)", -1)

