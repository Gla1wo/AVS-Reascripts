-- @description Enable PM on selected tracks + main-input side-chain for last-touched param (-52 dB ➜ -21 dB)
-- @version 1.1
-- @author AVS + MPL
-- @changelog
--   + v1.1 – sets Audio-control Min dB = -52 and Max dB = -21
-- @about
--   • Touch any parameter, then run the script.
--       – That parameter gets PM enabled, Audio-control (side-chain) on L+R,
--         with min/max level window preset to -52 → -21 dB.
--   • Every saved PM block on *selected tracks* is re-enabled too.
--   • Ignores take-FX (GetLastTouchedFX can’t see them).
--   • REAPER ≥ 6.73 required (TrackFX_SetNamedConfigParm).

--------------------------------------------------------------------------------
for k in pairs(reaper) do _G[k] = reaper[k] end            -- MPL shorthand

local MIN_REAPER_VERSION = 6.73
local DB_MIN, DB_MAX     = -52, -21                        -- ← tweak here
--------------------------------------------------------------------------------
local function check_reaper_version(min_v, show)
  local v = tonumber(GetAppVersion():match("[%d%.]+"))
  if v and v >= min_v then return true end
  if show then MB("Update REAPER to version "..min_v.." or newer", "", 0) end
end

--------------------------------------------------------------------------------
-- 1.  MAIN-INPUT AUDIO-CONTROL ➜ LAST-TOUCHED PARAMETER
--------------------------------------------------------------------------------
local function sidechain_last_touched()
  local ok, tr_code, fx_idx, parm_idx = GetLastTouchedFX()
  if not ok then return end

  local track_id =  tr_code       & 0xFFFF
  local take_id  = (tr_code >>16) & 0xFFFF
  if take_id > 0 then return end  -- skip take-FX

  local tr = (track_id == 0) and GetMasterTrack(0) or GetTrack(0, track_id-1)
  if not tr then return end

  local key = ("param.%d."):format(parm_idx)

  -- keep current value as baseline
  local _, cur_val = TrackFX_GetParam(tr, fx_idx, parm_idx)
  TrackFX_SetNamedConfigParm(tr, fx_idx, key.."mod.baseline", cur_val)

  -- show panel + enable PM
  TrackFX_SetNamedConfigParm(tr, fx_idx, key.."mod.visible", 1)
  TrackFX_SetNamedConfigParm(tr, fx_idx, key.."mod.active" , 1)

  -- audio-control section
  TrackFX_SetNamedConfigParm(tr, fx_idx, key.."acs.active" , 1)      -- tick box
  TrackFX_SetNamedConfigParm(tr, fx_idx, key.."acs.chan"   , 1)      -- ch 1
  TrackFX_SetNamedConfigParm(tr, fx_idx, key.."acs.stereo" , 1)      -- L+R
  TrackFX_SetNamedConfigParm(tr, fx_idx, key.."acs.dblo"   , DB_MIN) -- min dB
  TrackFX_SetNamedConfigParm(tr, fx_idx, key.."acs.dbhi"   , DB_MAX) -- max dB
end

--------------------------------------------------------------------------------
-- 2.  RE-ENABLE EXISTING PM BLOCKS ON SELECTED TRACKS
--------------------------------------------------------------------------------
local function enable_pm_on_selected_tracks()
  for i = 0, CountSelectedTracks(0)-1 do
    local tr = GetSelectedTrack(0, i)
    for fx = 0, TrackFX_GetCount(tr)-1 do
      for p = 0, TrackFX_GetNumParams(tr, fx)-1 do
        local key = ("param.%d.mod.active"):format(p)
        if TrackFX_GetNamedConfigParm(tr, fx, key) then           -- has PM saved
          TrackFX_SetNamedConfigParm(tr, fx, key, 1)              -- enable it
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- MAIN ENTRY
--------------------------------------------------------------------------------
if check_reaper_version(MIN_REAPER_VERSION, true) then
  Undo_BeginBlock2(0)
    sidechain_last_touched()
    enable_pm_on_selected_tracks()
  Undo_EndBlock2(0,
    "Enable PM on selected tracks + side-chain last-touched param (-52→-21 dB)",
    0xFFFFFFFF)
end

