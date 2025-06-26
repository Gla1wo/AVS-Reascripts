-- @description Extend nearest item edge (under mouse) to the source bounds
-- @version 1.0
-- @author AVS
-- @changelog
--   + Initial release
-- @about
--   • Requires the SWS Extension (for BR_* mouse helpers).  
--   • Works on the media item located directly under the mouse cursor.  
--   • Chooses the closest edge to the cursor (left or right)  
--     – If the left edge is closer it rolls the item start back to 0 sec of the source.  
--     – If the right edge is closer it lengthens the item to the end of the source.  
--   • Preserves take play-rate when calculating the remaining length.  
-- @provides
--   [main] .

local function msg(s) reaper.ShowConsoleMsg(tostring(s) .. "\n") end -- (debug)

--‐------------------------------------------------------------
--  Helpers
--‐------------------------------------------------------------
local function get_item_under_mouse()
  -- Call once to initialise internal mouse-context state
  reaper.BR_GetMouseCursorContext()
  return reaper.BR_GetMouseCursorContext_Item()
end

local function get_mouse_proj_pos()
  return reaper.BR_GetMouseCursorContext_Position()
end

--‐------------------------------------------------------------
--  Main
--‐------------------------------------------------------------
reaper.Undo_BeginBlock()

local item = get_item_under_mouse()
if not item then
  reaper.Undo_EndBlock("Extend nearest item edge – no item under mouse", -1)
  return
end

local take = reaper.GetActiveTake(item)
if not take then
  reaper.Undo_EndBlock("Extend nearest item edge – item has no active take", -1)
  return
end

local mousePos   = get_mouse_proj_pos()
local itemPos    = reaper.GetMediaItemInfo_Value(item, "D_POSITION")      -- left edge (project sec)
local itemLen    = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")        -- length  (project sec)
local leftEdge   = itemPos
local rightEdge  = itemPos + itemLen

-- Decide which edge is closer
local useLeft = math.abs(mousePos - leftEdge) <= math.abs(mousePos - rightEdge)

-- Take parameters we’ll need
local startOffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")  -- sec into source
local playrate  = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
local source    = reaper.GetMediaItemTake_Source(take)
local srcLen    = ({reaper.GetMediaSourceLength(source)})[1]              -- returns len, QNflag

if useLeft then
  ------------------------------------------------------------
  -- EXTEND LEFT EDGE to the very start of the source
  ------------------------------------------------------------
  if startOffs > 0 then
    -- Move item earlier by the current start offset
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", itemPos - startOffs / playrate)
    -- Length grows by the same (in project seconds)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", itemLen + startOffs / playrate)
    -- Set take start offset to 0 (beginning of source)
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
  end
else
  ------------------------------------------------------------
  -- EXTEND RIGHT EDGE to the end of the source
  ------------------------------------------------------------
  local usedSrc = startOffs + itemLen * playrate          -- sec of source already in use
  local remain  = srcLen - usedSrc                        -- sec of source still available
  if remain > 0 then
    -- Add the remaining length (converted to project seconds) to the item
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", itemLen + remain / playrate)
  end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Extend nearest item edge to source bounds", -1)

