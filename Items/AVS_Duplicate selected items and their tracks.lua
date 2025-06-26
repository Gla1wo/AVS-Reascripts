-- @description Duplicate selected items along with their track (excluding un-selected items)
-- @version 1.0
-- @author AVS
-- @changelog Initial release
-- @provides
--   [main] .
-- @about
--   • Looks at every selected media item in the project.  
--   • For each track that has ≥ 1 selected item:
--       – Inserts a brand-new track just below it and copies all track settings (FX, routing, envelopes, color, name, etc.).  
--       – Duplicates the selected items onto that new track, preserving positions, takes, fades, stretch markers, everything.  
--       – Leaves un-selected items on the source track untouched.  
--   • Works with multiple tracks of selected items at once.  
--   • Requires REAPER 6.0+

----------------------------------------------------------------
-- helper - strip <ITEM … > blocks from a track-state chunk
----------------------------------------------------------------
local function strip_items_from_chunk(chunk)
  local out, skip = {}, false
  for line in chunk:gmatch("[^\n]*\n?") do
    if line:match("^<ITEM")   then skip = true end   -- enter an ITEM block
    if not skip               then out[#out+1] = line end
    if skip and line:match("^>") then skip = false end -- exit ITEM block
  end
  return table.concat(out)
end

----------------------------------------------------------------
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- gather selected items by their parent track
local sel_by_track = {}        -- { [track_ptr] = {item1,item2,…}, order = {track_ptr,…} }
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
  local item  = reaper.GetSelectedMediaItem(0, i)
  local track = reaper.GetMediaItem_Track(item)
  sel_by_track[track] = sel_by_track[track] or {}
  sel_by_track[track][#sel_by_track[track]+1] = item
end

-- early out
if next(sel_by_track) == nil then
  reaper.MB("No selected items found.", "Duplicate Selected Items & Track", 0)
  reaper.PreventUIRefresh(-1)
  return reaper.Undo_EndBlock("Duplicate selected items + track (nothing to do)", -1)
end

-- sort source tracks by index (descending) to keep indices stable while inserting
local tracks_sorted = {}
for tr in pairs(sel_by_track) do tracks_sorted[#tracks_sorted+1] = tr end
table.sort(tracks_sorted, function(a,b)
  return reaper.GetMediaTrackInfo_Value(a,"IP_TRACKNUMBER") > 
         reaper.GetMediaTrackInfo_Value(b,"IP_TRACKNUMBER")
end)

for _, src_tr in ipairs(tracks_sorted) do
  local src_idx = reaper.GetMediaTrackInfo_Value(src_tr, "IP_TRACKNUMBER") - 1
  -- 1) insert blank track underneath
  reaper.InsertTrackAtIndex(src_idx + 1, true)
  local dst_tr = reaper.GetTrack(0, src_idx + 1)

  -- 2) copy all track settings minus items
  local ok, chunk = reaper.GetTrackStateChunk(src_tr, "", false)
  if ok then
    local stripped = strip_items_from_chunk(chunk)
    reaper.SetTrackStateChunk(dst_tr, stripped, true)
  end

  -- 3) duplicate the selected items onto the new track
  for _, item in ipairs(sel_by_track[src_tr]) do
    local ok_it, it_chunk = reaper.GetItemStateChunk(item, "", false)
    if ok_it then
      local new_item = reaper.AddMediaItemToTrack(dst_tr)
      reaper.SetItemStateChunk(new_item, it_chunk, true)
    end
  end
end

reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Duplicate selected items + their track (excl. others)", -1)

