-- @description Toggle bypass on ALL instances of: JS: AVS_Attenuator - Distance-Based Spatial DSP (Tracks + Master + Monitor)
-- @author AVS
-- @link https://ko-fi.com/avscott
-- @version 1.1
-- @about .
--   Toggles bypass for all instances of the AVS Attenuator JSFX across:
--     - All track FX chains
--     - All track Input/Record FX chains
--     - Master track FX chain
--     - Master track Input/Record FX chain
--     - Monitor FX chain (Master Monitor FX)
--
--   Toggle logic:
--     - If ANY instance is enabled -> BYPASS ALL
--     - Else (all bypassed) -> ENABLE ALL
--
--   Toolbar/Cycle Action highlight:
--     - ON  when instances are ENABLED (unbypassed)
--     - OFF when instances are BYPASSED
--
--   Matching is name-based (substring, case-insensitive). Adjust MATCH_TEXT if needed.

local MATCH_TEXT = "AVS_Attenuator - Distance-Based Spatial DSP"

-- Offsets for special chains
local REC_OFFSET     = 0x1000000 -- Track Input/Record FX
local MONITOR_OFFSET = 0x2000000 -- Monitor FX (on Master track)

-- Scan limits for monitor chain (REAPER API does not expose a direct "monitor FX count")
local MONITOR_MAX_SCAN = 512
local MONITOR_MISS_LIMIT = 16

-- -----------------------------
-- Helpers
-- -----------------------------
local function str_contains_ci(haystack, needle)
  if not haystack or not needle then return false end
  return haystack:lower():find(needle:lower(), 1, true) ~= nil
end

local function fx_name(track, fx_index)
  local ok, name = reaper.TrackFX_GetFXName(track, fx_index, "")
  if not ok then return nil end
  if not name or name == "" then return nil end
  return name
end

local function is_target_fx(track, fx_index)
  local name = fx_name(track, fx_index)
  if not name then return false end
  return str_contains_ci(name, MATCH_TEXT)
end

local function add_match(out, track, fx_index)
  out[#out + 1] = { track = track, fx = fx_index }
end

local function collect_normal_fx(track, out)
  local fx_count = reaper.TrackFX_GetCount(track)
  for i = 0, fx_count - 1 do
    if is_target_fx(track, i) then
      add_match(out, track, i)
    end
  end
end

local function collect_rec_fx(track, out)
  local rec_count = reaper.TrackFX_GetRecCount(track)
  for i = 0, rec_count - 1 do
    local fx_index = REC_OFFSET + i
    if is_target_fx(track, fx_index) then
      add_match(out, track, fx_index)
    end
  end
end

-- Monitor FX are hosted on the master track with index MONITOR_OFFSET + i.
-- There is no direct "GetMonitorCount" function, so we scan indices until
-- we hit a run of misses (MISS_LIMIT) or reach MAX_SCAN.
local function collect_monitor_fx(master_track, out)
  local misses = 0
  for i = 0, MONITOR_MAX_SCAN - 1 do
    local fx_index = MONITOR_OFFSET + i
    local name = fx_name(master_track, fx_index)

    if name then
      misses = 0
      if str_contains_ci(name, MATCH_TEXT) then
        add_match(out, master_track, fx_index)
      end
    else
      misses = misses + 1
      if misses >= MONITOR_MISS_LIMIT then
        break
      end
    end
  end
end

local function set_toolbar_toggle_state(state01)
  local _, _, sectionID, cmdID = reaper.get_action_context()
  if sectionID and cmdID then
    reaper.SetToggleCommandState(sectionID, cmdID, state01)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

-- -----------------------------
-- Main
-- -----------------------------
local matches = {}

-- All normal tracks
local track_count = reaper.CountTracks(0)
for t = 0, track_count - 1 do
  local tr = reaper.GetTrack(0, t)
  if tr then
    collect_normal_fx(tr, matches)
    collect_rec_fx(tr, matches)
  end
end

-- Master track (normal + rec + monitor)
local master = reaper.GetMasterTrack(0)
if master then
  collect_normal_fx(master, matches)
  collect_rec_fx(master, matches)
  collect_monitor_fx(master, matches)
end

-- If nothing found, force toolbar OFF and exit
if #matches == 0 then
  set_toolbar_toggle_state(0)
  return
end

-- Determine current aggregate state:
-- If ANY matched instance is enabled, we will bypass all.
local any_enabled = false
for i = 1, #matches do
  local tr = matches[i].track
  local fx = matches[i].fx
  if reaper.TrackFX_GetEnabled(tr, fx) then
    any_enabled = true
    break
  end
end

local enable_all = not any_enabled  -- if any enabled -> disable all; else enable all

reaper.Undo_BeginBlock2(0)

for i = 1, #matches do
  local tr = matches[i].track
  local fx = matches[i].fx
  reaper.TrackFX_SetEnabled(tr, fx, enable_all)
end

reaper.Undo_EndBlock2(
  0,
  enable_all
    and "Enable all AVS_Attenuator instances (Tracks + Master + Monitor)"
    or  "Bypass all AVS_Attenuator instances (Tracks + Master + Monitor)",
  -1
)

-- Toolbar highlight: ON when enabled, OFF when bypassed
set_toolbar_toggle_state(enable_all and 1 or 0)

