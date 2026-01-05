-- @description AVS_Attenuator_Editor - Distance-Based Attenuation Curve Editor
-- @author AVS
-- @version 7.2
-- @link Ko-fi.com/avscott
-- @about
-- =============================================================================
-- AVS_Attenuator_Editor
-- Game-Audio Focused Distance Attenuation Editor for REAPER
-- =============================================================================
--
-- AVS_Attenuator_Editor is a visual, distance-based attenuation editor for
-- game-audio workflows inside REAPER. Inspired by
-- Wwise’s attenuation curves, it features a modern ReaImGui interface
-- and allows the user to easily/precisely
-- modulate multiple parameters via a customizable distance control.
--
-- ---------------------------------------------------------------------------
-- Included Attenuation Curves
-- ---------------------------------------------------------------------------
--
--   • Volume (dB)
--   • High-Pass Filter (Hz, logarithmic)
--   • Low-Pass Filter (Hz, logarithmic)
--   • Stereo Spread (%)
--
-- All curves are evaluated simultaneously from a single distance control and
-- update audio in real time.
--
-- Each curve supports:
--   • Click-to-add, drag-to-edit control points
--   • Linear or smooth (spline) interpolation
--   • Per-curve visibility toggling
--
-- ---------------------------------------------------------------------------
-- Custom FX Parameter Curves
-- ---------------------------------------------------------------------------
--
-- Modulate up to 8 FX parameters over distance using custom curves.
--
--   • Control any plugin parameter via last touched param (reverb sends, distortion, filters, etc.)
--   • Once added, they're automatically linked to a new, randomly colored curve in the graph.
--
-- ---------------------------------------------------------------------------
-- Presets and Persistence
-- ---------------------------------------------------------------------------
--
--   • Factory presets for common attenuation scenarios
--   • User presets saved as JSON files
--   • Presets store curves, base values, distance, and custom parameters
--
-- Editor state is automatically restored when reopening REAPER.
--
-- ---------------------------------------------------------------------------
-- Real-Time Audio Integration
-- ---------------------------------------------------------------------------
--
-- The editor communicates with its companion JSFX via shared memory and native
-- parameter linking, providing immediate audio feedback during playback.
--
-- The JSFX can be placed on tracks, the master track, or the monitor FX chain.
--
-- =============================================================================


-- Check for ReaImGui
local reaimgui_installed = reaper.APIExists("ImGui_CreateContext")
if not reaimgui_installed then
  reaper.MB("This script requires ReaImGui.\n\nPlease install it via ReaPack:\n  Extensions > ReaPack > Browse packages\n  Search for 'ReaImGui'", "ReaImGui Required", 0)
  return
end

-- =============================================================================
-- CONSTANTS
-- =============================================================================

local GMEM_NAMESPACE = "attenuator_shared"
local EXTSTATE_SECTION = "Attenuator"

-- gmem indices (must match JSFX)
local GMEM_VOLUME = 0
local GMEM_HPF = 1
local GMEM_LPF = 2
local GMEM_SPREAD = 3
local GMEM_DIRTY = 4
local GMEM_DISTANCE = 5
local GMEM_DISTANCE_DIRTY = 6

-- JSFX Custom parameter slider indices (0-indexed, slider6-slider13 = indices 5-12)
-- These are the "source" parameters for REAPER parameter linking
local JSFX_CUSTOM_SLOT_BASE = 5  -- First custom slot is slider index 5 (slider6)
local JSFX_CUSTOM_SLOT_COUNT = 8 -- 8 custom slots total

-- Distance range
local DISTANCE_MIN = 0.0
local DISTANCE_MAX = 100.0

-- UI dimensions
local WINDOW_MIN_W = 900
local WINDOW_MIN_H = 650
local GRAPH_MARGIN_L = 60   -- Left margin for Y-axis labels
local GRAPH_MARGIN_R = 20   -- Right margin
local GRAPH_MARGIN_T = 40   -- Top margin
local GRAPH_MARGIN_B = 50   -- Bottom margin for X-axis labels
local CONTROL_PANEL_H = 195 -- Height of control panel below graph

-- Point interaction
local POINT_RADIUS = 6
local POINT_HOVER_RADIUS = 10
local POINT_HIT_RADIUS = 12
local DRAG_THRESHOLD = 5  -- Pixels to move before dragging starts

-- Curve rendering
local CURVE_SAMPLE_COUNT = 200

-- Update rate limiting
local UPDATE_INTERVAL = 0.05  -- 50ms = 20Hz

-- Colors (Updated to ImGui 0xRRGGBBAA format - Alpha is the last two bytes)
local COLORS = {
  bg = 0x1E1E24FF,              -- Dark background
  graph_bg = 0x14141AFF,        -- Darker graph background
  grid = 0x505060FF,            -- Subtle grid lines
  grid_major = 0x606070FF,      -- Major grid lines
  axis = 0x808090FF,            -- Axis lines
  text = 0xE0E0F0FF,            -- Text
  text_dim = 0xA0A0B0FF,        -- Dimmed text
  distance_line = 0xFFFFFFFF,   -- Current distance indicator

  -- Curve colors
  volume = 0xFF4C4CFF,          -- Red
  hpf = 0x4CFF4CFF,             -- Green
  lpf = 0x4C4CFFFF,             -- Blue
  spread = 0xFFFF4CFF,          -- Yellow

  -- Point states
  point_normal = 0xFFFFFFFF,    -- White
  point_hovered = 0x00FFFFFF,   -- Cyan
  point_selected = 0x00FF00FF,  -- Green
  point_outline = 0x000000FF,   -- Black outline
}

-- =============================================================================
-- CURVE DEFINITIONS
-- =============================================================================

local CURVE_DEFS = {
  {
    id = "volume",
    label = "Volume",
    unit = "dB",
    y_min = -96,
    y_max = 12,
    y_scale = "linear",
    color = COLORS.volume,
    gmem_index = GMEM_VOLUME,
    default_points = {
      {x = 0, y = 0},
      {x = 10, y = -12},
      {x = 50, y = -48},
      {x = 100, y = -96}
    }
  },
  {
    id = "hpf",
    label = "High-Pass",
    unit = "Hz",
    y_min = 20,
    y_max = 20000,
    y_scale = "log",
    color = COLORS.hpf,
    gmem_index = GMEM_HPF,
    default_points = {
      {x = 0, y = 20},
      {x = 50, y = 200},
      {x = 100, y = 500}
    }
  },
  {
    id = "lpf",
    label = "Low-Pass",
    unit = "Hz",
    y_min = 20,
    y_max = 20000,
    y_scale = "log",
    color = COLORS.lpf,
    gmem_index = GMEM_LPF,
    default_points = {
      {x = 0, y = 20000},
      {x = 50, y = 8000},
      {x = 100, y = 2000}
    }
  },
  {
    id = "spread",
    label = "Spread",
    unit = "%",
    y_min = 0,
    y_max = 100,
    y_scale = "linear",
    color = COLORS.spread,
    gmem_index = GMEM_SPREAD,
    default_points = {
      {x = 0, y = 100},
      {x = 20, y = 50},
      {x = 100, y = 0}
    }
  }
}

-- =============================================================================
-- STATE
-- =============================================================================

local state = {
  ctx = nil,                    -- ImGui context

  curves = {},                  -- Array of curve data
  active_curve = 1,             -- Currently active curve (1-4)
  curve_visible = {true, true, true, true},
  curve_enabled = {true, true, true, true},  -- Whether curve affects output (false = bypass)

  current_distance = 10.0,      -- Current evaluation distance (internal 0-100 scale)
  display_max_distance = 100.0, -- Max distance for display purposes (affects UI labels only)
  evaluated_values = {},        -- Cached evaluated values at current distance
  output_values = {},           -- Final output values (curve + base offset, clamped)

  -- Base attenuation values (displayed as absolute values, offset calculated from reference)
  -- Reference values (unattenuated): Volume=0, HP=20, LP=20000, Spread=100
  base = {
    volume_db = 0.0,            -- Volume base value in dB (reference: 0.0)
    hp_hz = 20.0,               -- High-pass base value in Hz (reference: 20)
    lp_hz = 20000.0,            -- Low-pass base value in Hz (reference: 20000)
    spread_pct = 100.0          -- Spread base value in % (reference: 100)
  },

  -- Interaction state
  selected_point = nil,         -- {curve_idx, point_idx}
  hovered_point = nil,          -- {curve_idx, point_idx}
  dragging = false,             -- Mouse is held down on a point
  drag_active = false,          -- Threshold exceeded, actually moving the point
  drag_start_mouse = nil,       -- Screen position where drag started {x, y}
  drag_start_point = nil,       -- Original point position {x, y}

  -- Graph transform state
  graph_rect = {x = 0, y = 0, w = 0, h = 0},

  -- Update timing
  last_update_time = 0,
  dirty = true,                 -- Need to send to JSFX?

  -- Window state
  window_open = true,

  -- Auto-bypass on exit
  auto_bypass_on_exit = false,

  -- Custom FX parameter curves
  custom_params = {},           -- Array of custom param entries
  selected_custom_id = nil,     -- ID of currently selected custom param
  custom_slot_used = {},        -- Tracks which slots (1-8) are in use
}

-- Forward declarations (defined later, but needed by preset system)
local save_state
local force_update_jsfx
local get_jsfx_bypass_state
local toggle_jsfx_bypass

-- Forward declarations for custom param functions (defined in CUSTOM FX PARAMETER CURVES section)
local init_custom_slots
local generate_custom_id
local generate_random_curve_color
local create_default_custom_curve
local resolve_custom_param
local remove_param_link
local resolve_and_link_all_custom_params

-- =============================================================================
-- PRESET SYSTEM
-- =============================================================================
-- Implements factory and user presets with JSON serialization.
-- User presets stored in: REAPER/Data/AVS_Attenuator_Editor/Presets/

-- -----------------------------------------------------------------------------
-- JSON Module (Embedded minimal implementation)
-- -----------------------------------------------------------------------------
local json = {}

local function json_encode_string(s)
  local escape_map = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'
  }
  return '"' .. s:gsub('[%z\1-\31"\\]', function(c)
    return escape_map[c] or string.format('\\u%04x', c:byte())
  end) .. '"'
end

local function json_encode_value(val, indent, depth)
  local t = type(val)
  if val == nil then
    return 'null'
  elseif t == 'boolean' then
    return val and 'true' or 'false'
  elseif t == 'number' then
    if val ~= val then return 'null' end -- NaN
    if val == math.huge or val == -math.huge then return 'null' end
    return string.format('%.10g', val)
  elseif t == 'string' then
    return json_encode_string(val)
  elseif t == 'table' then
    local is_array = true
    local max_idx = 0
    for k, _ in pairs(val) do
      if type(k) ~= 'number' or k < 1 or math.floor(k) ~= k then
        is_array = false
        break
      end
      if k > max_idx then max_idx = k end
    end
    if is_array and max_idx > 0 then
      for i = 1, max_idx do
        if val[i] == nil then is_array = false; break end
      end
    end
    if is_array and max_idx == 0 then is_array = #val == 0 end

    local new_indent = indent and (indent .. '  ') or nil
    local nl = indent and '\n' or ''
    local sep = indent and ', ' or ','
    local parts = {}

    if is_array then
      for i = 1, max_idx do
        parts[i] = json_encode_value(val[i], new_indent, (depth or 0) + 1)
      end
      if #parts == 0 then return '[]' end
      if indent then
        return '[\n' .. new_indent .. table.concat(parts, ',\n' .. new_indent) .. '\n' .. indent .. ']'
      else
        return '[' .. table.concat(parts, ',') .. ']'
      end
    else
      for k, v in pairs(val) do
        if type(k) == 'string' then
          local encoded = json_encode_string(k) .. ':' .. (indent and ' ' or '') .. json_encode_value(v, new_indent, (depth or 0) + 1)
          table.insert(parts, encoded)
        end
      end
      table.sort(parts)
      if #parts == 0 then return '{}' end
      if indent then
        return '{\n' .. new_indent .. table.concat(parts, ',\n' .. new_indent) .. '\n' .. indent .. '}'
      else
        return '{' .. table.concat(parts, ',') .. '}'
      end
    end
  else
    return 'null'
  end
end

function json.encode(value, opts)
  local indent = opts and opts.pretty and '' or nil
  return json_encode_value(value, indent, 0)
end

function json.decode(str)
  if type(str) ~= 'string' then return nil, 'expected string' end
  local pos = 1
  local len = #str

  local function skip_ws()
    while pos <= len do
      local c = str:sub(pos, pos)
      if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
        pos = pos + 1
      else
        break
      end
    end
  end

  local function parse_value()
    skip_ws()
    if pos > len then return nil, 'unexpected end of input' end
    local c = str:sub(pos, pos)

    if c == '"' then
      pos = pos + 1
      local result = {}
      while pos <= len do
        local ch = str:sub(pos, pos)
        if ch == '"' then
          pos = pos + 1
          return table.concat(result)
        elseif ch == '\\' then
          pos = pos + 1
          if pos > len then return nil, 'unexpected end in string' end
          local esc = str:sub(pos, pos)
          local esc_map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
          if esc_map[esc] then
            table.insert(result, esc_map[esc])
            pos = pos + 1
          elseif esc == 'u' then
            local hex = str:sub(pos + 1, pos + 4)
            if #hex == 4 and hex:match('^%x+$') then
              local code = tonumber(hex, 16)
              if code < 128 then
                table.insert(result, string.char(code))
              else
                table.insert(result, '?')
              end
              pos = pos + 5
            else
              return nil, 'invalid unicode escape'
            end
          else
            return nil, 'invalid escape'
          end
        else
          table.insert(result, ch)
          pos = pos + 1
        end
      end
      return nil, 'unterminated string'
    elseif c == '{' then
      pos = pos + 1
      local obj = {}
      skip_ws()
      if pos <= len and str:sub(pos, pos) == '}' then
        pos = pos + 1
        return obj
      end
      while true do
        skip_ws()
        local key, err = parse_value()
        if err then return nil, err end
        if type(key) ~= 'string' then return nil, 'expected string key' end
        skip_ws()
        if pos > len or str:sub(pos, pos) ~= ':' then return nil, 'expected colon' end
        pos = pos + 1
        local val
        val, err = parse_value()
        if err then return nil, err end
        obj[key] = val
        skip_ws()
        if pos > len then return nil, 'unexpected end in object' end
        local sep = str:sub(pos, pos)
        if sep == '}' then pos = pos + 1; return obj end
        if sep ~= ',' then return nil, 'expected comma or }' end
        pos = pos + 1
      end
    elseif c == '[' then
      pos = pos + 1
      local arr = {}
      skip_ws()
      if pos <= len and str:sub(pos, pos) == ']' then
        pos = pos + 1
        return arr
      end
      while true do
        local val, err = parse_value()
        if err then return nil, err end
        table.insert(arr, val)
        skip_ws()
        if pos > len then return nil, 'unexpected end in array' end
        local sep = str:sub(pos, pos)
        if sep == ']' then pos = pos + 1; return arr end
        if sep ~= ',' then return nil, 'expected comma or ]' end
        pos = pos + 1
      end
    elseif str:sub(pos, pos + 3) == 'true' then
      pos = pos + 4
      return true
    elseif str:sub(pos, pos + 4) == 'false' then
      pos = pos + 5
      return false
    elseif str:sub(pos, pos + 3) == 'null' then
      pos = pos + 4
      return nil
    elseif c == '-' or (c >= '0' and c <= '9') then
      local start = pos
      if str:sub(pos, pos) == '-' then pos = pos + 1 end
      while pos <= len and str:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
      if pos <= len and str:sub(pos, pos) == '.' then
        pos = pos + 1
        while pos <= len and str:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
      end
      if pos <= len and str:sub(pos, pos):lower() == 'e' then
        pos = pos + 1
        if pos <= len and (str:sub(pos, pos) == '+' or str:sub(pos, pos) == '-') then
          pos = pos + 1
        end
        while pos <= len and str:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
      end
      local num_str = str:sub(start, pos - 1)
      local num = tonumber(num_str)
      if num then return num end
      return nil, 'invalid number'
    else
      return nil, 'unexpected character: ' .. c
    end
  end

  local result, err = parse_value()
  if err then return nil, err end
  skip_ws()
  if pos <= len then return nil, 'trailing content' end
  return result
end

-- -----------------------------------------------------------------------------
-- Filesystem Utilities
-- -----------------------------------------------------------------------------
local PATH_SEP = package.config:sub(1, 1)

local function avs_join_path(a, b)
  if not a or a == '' then return b or '' end
  if not b or b == '' then return a end
  local last = a:sub(-1)
  if last == '/' or last == '\\' then
    return a .. b
  else
    return a .. PATH_SEP .. b
  end
end

local function avs_ensure_dir(path)
  -- Try to create directory; if it fails, try creating parent first
  local ok = reaper.RecursiveCreateDirectory(path, 0)
  return ok ~= 0
end

local function avs_get_user_preset_dir()
  local resource_path = reaper.GetResourcePath()
  local data_dir = avs_join_path(resource_path, 'Data')
  local app_dir = avs_join_path(data_dir, 'AVS_Attenuator_Editor')
  local preset_dir = avs_join_path(app_dir, 'Presets')
  avs_ensure_dir(preset_dir)
  return preset_dir
end

local function avs_enumerate_user_preset_files()
  local dir = avs_get_user_preset_dir()
  local files = {}
  local i = 0
  while true do
    local filename = reaper.EnumerateFiles(dir, i)
    if not filename or filename == '' then break end
    if filename:lower():match('%.json$') then
      table.insert(files, avs_join_path(dir, filename))
    end
    i = i + 1
  end
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  return files
end

-- -----------------------------------------------------------------------------
-- Preset Data Model
-- -----------------------------------------------------------------------------
local PRESET_SCHEMA_VERSION = 1

local FACTORY_PRESETS = {
  {
    name = "Factory: Default",
    data = {
      curves = {
        { id = "volume", interpolation = "smooth", points = {{x=0,y=0},{x=10,y=-12},{x=50,y=-48},{x=100,y=-96}} },
        { id = "hpf", interpolation = "smooth", points = {{x=0,y=20},{x=50,y=200},{x=100,y=500}} },
        { id = "lpf", interpolation = "smooth", points = {{x=0,y=20000},{x=50,y=8000},{x=100,y=2000}} },
        { id = "spread", interpolation = "smooth", points = {{x=0,y=100},{x=20,y=50},{x=100,y=0}} }
      },
      current_distance = 10.0,
      curve_visible = {true, true, true, true}
    }
  },
  {
    name = "Factory: Linear Falloff",
    data = {
      curves = {
        { id = "volume", interpolation = "linear", points = {{x=0,y=0},{x=100,y=-60}} },
        { id = "hpf", interpolation = "linear", points = {{x=0,y=20},{x=100,y=200}} },
        { id = "lpf", interpolation = "linear", points = {{x=0,y=20000},{x=100,y=5000}} },
        { id = "spread", interpolation = "linear", points = {{x=0,y=100},{x=100,y=0}} }
      },
      current_distance = 10.0,
      curve_visible = {true, true, true, true}
    }
  },
  {
    name = "Factory: Close Mic",
    data = {
      curves = {
        { id = "volume", interpolation = "smooth", points = {{x=0,y=0},{x=5,y=-3},{x=20,y=-24},{x=100,y=-96}} },
        { id = "hpf", interpolation = "smooth", points = {{x=0,y=20},{x=100,y=80}} },
        { id = "lpf", interpolation = "smooth", points = {{x=0,y=20000},{x=100,y=16000}} },
        { id = "spread", interpolation = "smooth", points = {{x=0,y=100},{x=100,y=80}} }
      },
      current_distance = 5.0,
      curve_visible = {true, true, true, true}
    }
  },
  {
    name = "Factory: Distant Ambience",
    data = {
      curves = {
        { id = "volume", interpolation = "smooth", points = {{x=0,y=-12},{x=30,y=-24},{x=100,y=-48}} },
        { id = "hpf", interpolation = "smooth", points = {{x=0,y=80},{x=50,y=300},{x=100,y=800}} },
        { id = "lpf", interpolation = "smooth", points = {{x=0,y=12000},{x=50,y=6000},{x=100,y=2500}} },
        { id = "spread", interpolation = "smooth", points = {{x=0,y=60},{x=50,y=30},{x=100,y=10}} }
      },
      current_distance = 50.0,
      curve_visible = {true, true, true, true}
    }
  }
}

local function avs_state_to_preset_data(src_state)
  local data = {
    curves = {},
    current_distance = src_state.current_distance or 10.0,
    curve_visible = {},
    curve_enabled = {},
    -- Include base attenuation values (default to unattenuated reference values)
    base = {
      volume_db = src_state.base and src_state.base.volume_db or 0.0,
      hp_hz = src_state.base and src_state.base.hp_hz or 20.0,
      lp_hz = src_state.base and src_state.base.lp_hz or 20000.0,
      spread_pct = src_state.base and src_state.base.spread_pct or 100.0
    },
    -- Include custom parameters
    custom_params = {}
  }
  for i, curve in ipairs(src_state.curves) do
    local curve_data = {
      id = curve.id,
      interpolation = curve.interpolation or "smooth",
      points = {}
    }
    for _, p in ipairs(curve.points) do
      table.insert(curve_data.points, { x = p.x, y = p.y })
    end
    table.insert(data.curves, curve_data)
    data.curve_visible[i] = src_state.curve_visible[i] ~= false
    data.curve_enabled[i] = src_state.curve_enabled[i] ~= false
  end

  -- Save custom parameters to preset
  if src_state.custom_params then
    for _, param in ipairs(src_state.custom_params) do
      table.insert(data.custom_params, {
        id = param.id,
        track_guid = param.track_guid,
        fx_guid = param.fx_guid,
        jsfx_guid = param.jsfx_guid,
        param_index = param.param_index,
        jsfx_slot = param.jsfx_slot,
        name_short = param.name_short,
        name_full = param.name_full,
        fx_name = param.fx_name,
        track_name = param.track_name,
        curve = param.curve,
        interpolation = param.interpolation,
        color = param.color,
        enabled = param.enabled
      })
    end
  end

  return data
end

local function avs_apply_preset_data_to_state(dst_state, preset_data)
  if not preset_data then return end

  -- Apply current_distance
  if preset_data.current_distance then
    dst_state.current_distance = preset_data.current_distance
  end

  -- Apply curve visibility
  if preset_data.curve_visible then
    for i = 1, 4 do
      if preset_data.curve_visible[i] ~= nil then
        dst_state.curve_visible[i] = preset_data.curve_visible[i]
      end
    end
  end

  -- Apply curve enabled state
  if preset_data.curve_enabled then
    for i = 1, 4 do
      if preset_data.curve_enabled[i] ~= nil then
        dst_state.curve_enabled[i] = preset_data.curve_enabled[i]
      end
    end
  else
    -- Preset doesn't have enabled state (e.g., old preset) - default to all enabled
    for i = 1, 4 do
      dst_state.curve_enabled[i] = true
    end
  end

  -- Apply base attenuation values (default to unattenuated reference values if not present)
  -- Reference values: Volume=0, HP=20, LP=20000, Spread=100
  if preset_data.base then
    dst_state.base.volume_db = tonumber(preset_data.base.volume_db) or 0.0
    dst_state.base.hp_hz = tonumber(preset_data.base.hp_hz) or 20.0
    dst_state.base.lp_hz = tonumber(preset_data.base.lp_hz) or 20000.0
    dst_state.base.spread_pct = tonumber(preset_data.base.spread_pct) or 100.0
  else
    -- Preset doesn't have base values (e.g., old preset or factory preset) - use unattenuated defaults
    dst_state.base.volume_db = 0.0
    dst_state.base.hp_hz = 20.0
    dst_state.base.lp_hz = 20000.0
    dst_state.base.spread_pct = 100.0
  end

  -- Apply curve data
  if preset_data.curves then
    for _, preset_curve in ipairs(preset_data.curves) do
      -- Find matching curve by id
      for i, curve in ipairs(dst_state.curves) do
        if curve.id == preset_curve.id then
          -- Apply interpolation
          if preset_curve.interpolation then
            curve.interpolation = preset_curve.interpolation
          end
          -- Apply points
          if preset_curve.points and #preset_curve.points >= 2 then
            curve.points = {}
            for _, p in ipairs(preset_curve.points) do
              table.insert(curve.points, { x = p.x, y = p.y })
            end
          end
          break
        end
      end
    end
  end

  -- Apply custom parameters from preset
  if preset_data.custom_params and type(preset_data.custom_params) == "table" then
    -- First, remove all existing custom params and free their slots
    for _, param in ipairs(dst_state.custom_params or {}) do
      -- Try to remove link
      local resolved, track, fx_idx = resolve_custom_param(param)
      if resolved and track and fx_idx then
        remove_param_link(track, fx_idx, param.param_index)
      end
    end

    -- Reset slot tracking and custom params
    dst_state.custom_params = {}
    init_custom_slots()

    -- Load custom params from preset
    for _, data in ipairs(preset_data.custom_params) do
      local param = {
        id = data.id or generate_custom_id(),
        track_guid = data.track_guid,
        fx_guid = data.fx_guid,
        jsfx_guid = data.jsfx_guid,
        param_index = data.param_index,
        jsfx_slot = data.jsfx_slot,
        name_short = data.name_short,
        name_full = data.name_full,
        fx_name = data.fx_name,
        track_name = data.track_name,
        curve = data.curve or create_default_custom_curve(),
        interpolation = data.interpolation or "smooth",
        color = data.color or generate_random_curve_color(),
        enabled = data.enabled ~= false,  -- Default to true for backwards compatibility
        resolved = false
      }

      -- Mark slot as used
      if param.jsfx_slot and param.jsfx_slot >= 1 and param.jsfx_slot <= JSFX_CUSTOM_SLOT_COUNT then
        dst_state.custom_slot_used[param.jsfx_slot] = true
      end

      table.insert(dst_state.custom_params, param)
    end

    -- Resolve and recreate links
    resolve_and_link_all_custom_params()

    -- Clear selection
    dst_state.selected_custom_id = nil
    if #dst_state.custom_params > 0 then
      dst_state.selected_custom_id = dst_state.custom_params[1].id
    end
  end

  -- Mark state as dirty to trigger JSFX update
  dst_state.dirty = true
end

local function avs_migrate_preset_payload(payload)
  if not payload then return nil end

  -- Ensure schema field exists
  if not payload.schema then
    payload.schema = 1
  end

  -- Schema v1: current format, no migration needed
  if payload.schema == 1 then
    return payload
  end

  -- Future schema migrations would go here:
  -- if payload.schema == 2 then ... migrate to v2 ... end

  -- If schema is unknown/newer, try to use as-is
  return payload
end

-- -----------------------------------------------------------------------------
-- Preset I/O
-- -----------------------------------------------------------------------------
local function avs_sanitize_preset_name(name)
  if not name then return "Untitled" end
  -- Trim whitespace
  name = name:match("^%s*(.-)%s*$") or ""
  if name == "" then return "Untitled" end
  -- Replace invalid filename characters
  name = name:gsub('[<>:"/\\|%?%*]', '_')
  -- Limit length
  if #name > 100 then name = name:sub(1, 100) end
  return name
end

local function avs_make_unique_preset_path(dir, base_name)
  local sanitized = avs_sanitize_preset_name(base_name)
  local path = avs_join_path(dir, sanitized .. '.json')

  -- Check if file exists using io.open
  local f = io.open(path, 'r')
  if not f then
    return path
  end
  f:close()

  -- Add suffix to make unique
  local suffix = 2
  while true do
    path = avs_join_path(dir, sanitized .. ' (' .. suffix .. ').json')
    f = io.open(path, 'r')
    if not f then
      return path
    end
    f:close()
    suffix = suffix + 1
    if suffix > 1000 then
      -- Fallback with timestamp
      path = avs_join_path(dir, sanitized .. '_' .. os.time() .. '.json')
      return path
    end
  end
end

local function avs_load_user_preset_file(path)
  local f, err = io.open(path, 'r')
  if not f then
    reaper.ShowConsoleMsg('[AVS_Attenuator] Could not open preset: ' .. path .. ' (' .. (err or 'unknown') .. ')\n')
    return nil, err
  end

  local content = f:read('*a')
  f:close()

  if not content or content == '' then
    reaper.ShowConsoleMsg('[AVS_Attenuator] Empty preset file: ' .. path .. '\n')
    return nil, 'empty file'
  end

  local payload, json_err = json.decode(content)
  if not payload then
    reaper.ShowConsoleMsg('[AVS_Attenuator] Invalid JSON in preset: ' .. path .. ' (' .. (json_err or 'parse error') .. ')\n')
    return nil, json_err
  end

  -- Migrate to current schema
  payload = avs_migrate_preset_payload(payload)
  if not payload then
    reaper.ShowConsoleMsg('[AVS_Attenuator] Could not migrate preset: ' .. path .. '\n')
    return nil, 'migration failed'
  end

  -- Always use filename for display (ensures unique names like "test 02 (2)")
  -- The filename is guaranteed unique on disk, while internal names may conflict
  local filename = path:match('[/\\]([^/\\]+)%.json$') or 'Untitled'
  local name = filename

  return {
    source = 'user',
    name = name,
    path = path,
    data = payload.data or {}
  }
end

local function avs_build_preset_catalog()
  local catalog = {}

  -- Add factory presets
  for _, fp in ipairs(FACTORY_PRESETS) do
    table.insert(catalog, {
      source = 'factory',
      name = fp.name,
      data = fp.data
    })
  end

  -- Add user presets
  local user_files = avs_enumerate_user_preset_files()
  for _, filepath in ipairs(user_files) do
    local preset = avs_load_user_preset_file(filepath)
    if preset then
      table.insert(catalog, preset)
    end
  end

  return catalog
end

local function avs_save_user_preset(dir, preset_name, preset_data)
  local path = avs_make_unique_preset_path(dir, preset_name)

  local payload = {
    schema = PRESET_SCHEMA_VERSION,
    name = preset_name,
    created_utc = os.time(),
    data = preset_data
  }

  local json_str = json.encode(payload, { pretty = true })
  if not json_str then
    return false, 'JSON encoding failed'
  end

  local f, err = io.open(path, 'w')
  if not f then
    return false, 'Could not create file: ' .. (err or 'unknown')
  end

  f:write(json_str)
  f:close()

  return true, path
end

-- -----------------------------------------------------------------------------
-- Preset UI State
-- -----------------------------------------------------------------------------
local preset_ui = {
  catalog = nil,
  catalog_dirty = true,
  selected_name = nil,
  save_popup_open = false,
  save_name_buffer = '',
  last_saved_path = nil
}

-- Check for optional extensions
local function avs_has_sws()
  return reaper.CF_ShellExecute ~= nil
end

local function avs_has_js()
  return reaper.JS_Shell_Execute ~= nil
end

local function avs_open_preset_folder()
  local dir = avs_get_user_preset_dir()
  if avs_has_sws() then
    reaper.CF_ShellExecute(dir)
    return true
  elseif avs_has_js() then
    reaper.JS_Shell_Execute(dir)
    return true
  end
  return false
end

-- -----------------------------------------------------------------------------
-- Preset UI Rendering
-- -----------------------------------------------------------------------------
local function avs_presets_ui(ctx, app_state)
  local ImGui = _G.ImGui or {}
  -- Populate ImGui if needed (it should already be populated in init_imgui)
  if not ImGui.Text then
    for name, func in pairs(reaper) do
      if name:match("^ImGui_") then
        ImGui[name:sub(7)] = func
      end
    end
  end

  -- Rebuild catalog if dirty
  if preset_ui.catalog_dirty or not preset_ui.catalog then
    preset_ui.catalog = avs_build_preset_catalog()
    preset_ui.catalog_dirty = false
  end

  -- Get current selection display name
  local current_display = preset_ui.selected_name or "Select Preset..."

  -- Preset dropdown
  ImGui.Text(ctx, "Preset:")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 200)

  if ImGui.BeginCombo(ctx, "##preset_combo", current_display) then
    -- Save action at top
    if ImGui.Selectable(ctx, "Save current as preset...", false) then
      preset_ui.save_popup_open = true
      preset_ui.save_name_buffer = ''
    end

    ImGui.Separator(ctx)

    -- Factory presets section
    ImGui.TextDisabled(ctx, "-- Factory Presets --")
    for i, preset in ipairs(preset_ui.catalog) do
      if preset.source == 'factory' then
        local is_selected = preset_ui.selected_name == preset.name
        if ImGui.Selectable(ctx, preset.name .. "##factory_" .. i, is_selected) then
          preset_ui.selected_name = preset.name
          avs_apply_preset_data_to_state(app_state, preset.data)
          save_state()
          force_update_jsfx()
        end
      end
    end

    ImGui.Separator(ctx)

    -- User presets section
    ImGui.TextDisabled(ctx, "-- User Presets --")
    local has_user = false
    for i, preset in ipairs(preset_ui.catalog) do
      if preset.source == 'user' then
        has_user = true
        local is_selected = preset_ui.selected_name == preset.name
        if ImGui.Selectable(ctx, preset.name .. "##user_" .. i, is_selected) then
          preset_ui.selected_name = preset.name
          avs_apply_preset_data_to_state(app_state, preset.data)
          save_state()
          force_update_jsfx()
        end
      end
    end
    if not has_user then
      ImGui.TextDisabled(ctx, "(no user presets)")
    end

    ImGui.EndCombo(ctx)
  end

  -- Open folder button (if extensions available)
  ImGui.SameLine(ctx)
  if avs_has_sws() or avs_has_js() then
    if ImGui.SmallButton(ctx, "Open Folder") then
      avs_open_preset_folder()
    end
  else
    -- Show tooltip with path instead
    ImGui.TextDisabled(ctx, "[?]")
    if ImGui.IsItemHovered(ctx) then
      ImGui.BeginTooltip(ctx)
      ImGui.Text(ctx, "User presets folder:")
      ImGui.Text(ctx, avs_get_user_preset_dir())
      ImGui.EndTooltip(ctx)
    end
  end

  -- Add JSFX buttons
  ImGui.SameLine(ctx, 0, 20)
  if ImGui.SmallButton(ctx, "+ Monitor FX") then
    local master = reaper.GetMasterTrack(0)
    if master then
      -- Add to monitor FX chain (0x1000000 offset + position 0 = add at end of monitor chain)
      local fx_idx = reaper.TrackFX_AddByName(master, "AVS_Attenuator", true, -1)
      if fx_idx >= 0 then
        reaper.TrackFX_Show(master, 0x1000000 + fx_idx, 3)  -- Show floating window
      end
    end
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, "Add AVS_Attenuator to Monitor FX chain")
    ImGui.EndTooltip(ctx)
  end

  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "+ Track FX") then
    local track = reaper.GetSelectedTrack(0, 0)
    if track then
      local fx_idx = reaper.TrackFX_AddByName(track, "AVS_Attenuator", false, -1)
      if fx_idx >= 0 then
        reaper.TrackFX_Show(track, fx_idx, 3)  -- Show floating window
      end
    else
      reaper.ShowMessageBox("Please select a track first.", "No Track Selected", 0)
    end
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, "Add AVS_Attenuator to selected track")
    ImGui.EndTooltip(ctx)
  end

  -- Bypass toggle button
  ImGui.SameLine(ctx, 0, 20)
  local is_bypassed = get_jsfx_bypass_state()
  local jsfx_found = is_bypassed ~= nil

  if not jsfx_found then
    ImGui.BeginDisabled(ctx)
  end

  -- Color the button red when bypassed
  if is_bypassed then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), 0xCC3333FF)        -- Red
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), 0xDD4444FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), 0xEE5555FF)
  end

  local bypass_label = is_bypassed and "Bypassed" or "Bypass"
  if ImGui.SmallButton(ctx, bypass_label) then
    toggle_jsfx_bypass()
  end

  if is_bypassed then
    ImGui.PopStyleColor(ctx, 3)
  end

  if not jsfx_found then
    ImGui.EndDisabled(ctx)
  end

  if ImGui.IsItemHovered(ctx) then
    ImGui.BeginTooltip(ctx)
    if jsfx_found then
      ImGui.Text(ctx, is_bypassed and "Click to enable AVS_Attenuator" or "Click to bypass AVS_Attenuator")
    else
      ImGui.Text(ctx, "No AVS_Attenuator instance found")
    end
    ImGui.EndTooltip(ctx)
  end

  -- Auto-bypass checkbox
  ImGui.SameLine(ctx)
  local auto_changed, auto_val = ImGui.Checkbox(ctx, "Auto", state.auto_bypass_on_exit)
  if auto_changed then
    state.auto_bypass_on_exit = auto_val
    save_state()
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, "Automatically bypass all AVS_Attenuator instances on script exit")
    ImGui.EndTooltip(ctx)
  end

  -- Save popup modal
  if preset_ui.save_popup_open then
    ImGui.OpenPopup(ctx, "Save Preset##modal")
    preset_ui.save_popup_open = false
  end

  local popup_flags = ImGui.WindowFlags_AlwaysAutoResize()
  if ImGui.BeginPopupModal(ctx, "Save Preset##modal", true, popup_flags) then
    ImGui.Text(ctx, "Enter preset name:")
    ImGui.SetNextItemWidth(ctx, 250)

    -- InputText returns (changed, buffer) - buffer is always the current text
    local changed, buf = ImGui.InputText(ctx, "##preset_name_input", preset_ui.save_name_buffer)
    if buf then
      preset_ui.save_name_buffer = buf
    end

    -- Focus the input on first frame
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx, -1)
    end

    -- Check for Enter key press while focused
    local enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter()) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter())

    ImGui.Spacing(ctx)

    -- Check if there's non-whitespace content
    local trimmed = preset_ui.save_name_buffer:gsub("^%s+", ""):gsub("%s+$", "")
    local can_save = #trimmed > 0

    if not can_save then
      ImGui.BeginDisabled(ctx)
    end
    if ImGui.Button(ctx, "Save", 80, 0) or (enter_pressed and can_save) then
      local dir = avs_get_user_preset_dir()
      local preset_data = avs_state_to_preset_data(app_state)
      local ok, path_or_err = avs_save_user_preset(dir, preset_ui.save_name_buffer, preset_data)
      if ok then
        preset_ui.catalog_dirty = true
        preset_ui.last_saved_path = path_or_err
        -- Extract saved name from catalog after refresh
        preset_ui.catalog = avs_build_preset_catalog()
        preset_ui.catalog_dirty = false
        -- Find and select the new preset
        for _, p in ipairs(preset_ui.catalog) do
          if p.path == path_or_err then
            preset_ui.selected_name = p.name
            break
          end
        end
        ImGui.CloseCurrentPopup(ctx)
      else
        reaper.ShowConsoleMsg('[AVS_Attenuator] Save failed: ' .. (path_or_err or 'unknown error') .. '\n')
      end
    end
    if not can_save then
      ImGui.EndDisabled(ctx)
    end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 80, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  ImGui.Separator(ctx)
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

local function clamp(value, min_val, max_val)
  return math.max(min_val, math.min(max_val, value))
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function inverse_lerp(a, b, value)
  if b == a then return 0 end
  return (value - a) / (b - a)
end

-- Deep copy a table
local function deep_copy(t)
  if type(t) ~= "table" then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- Simple JSON encode for tables of points
local function json_encode_points(points)
  local parts = {}
  for _, p in ipairs(points) do
    table.insert(parts, string.format("{\"x\":%.6f,\"y\":%.6f}", p.x, p.y))
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

-- Simple JSON decode for points
local function json_decode_points(str)
  local points = {}
  for x, y in str:gmatch('{%s*"x"%s*:%s*([%d%.%-]+)%s*,%s*"y"%s*:%s*([%d%.%-]+)%s*}') do
    table.insert(points, {x = tonumber(x), y = tonumber(y)})
  end
  return points
end

-- Format value with appropriate precision
local function format_value(value, unit)
  if unit == "dB" then
    return string.format("%.1f %s", value, unit)
  elseif unit == "Hz" then
    if value >= 1000 then
      return string.format("%.1f kHz", value / 1000)
    else
      return string.format("%.0f Hz", value)
    end
  elseif unit == "%" then
    return string.format("%.0f%%", value)
  else
    return string.format("%.1f %s", value, unit)
  end
end

-- Convert internal distance (0-100) to display distance (0-display_max)
local function to_display_distance(internal_dist)
  return internal_dist * state.display_max_distance / DISTANCE_MAX
end

-- Convert display distance to internal distance (0-100)
local function from_display_distance(display_dist)
  return display_dist * DISTANCE_MAX / state.display_max_distance
end

-- =============================================================================
-- CURVE FUNCTIONS
-- =============================================================================

-- Initialize curves from defaults or saved state
local function init_curves()
  for i, def in ipairs(CURVE_DEFS) do
    state.curves[i] = {
      id = def.id,
      label = def.label,
      unit = def.unit,
      y_min = def.y_min,
      y_max = def.y_max,
      y_scale = def.y_scale,
      color = def.color,
      gmem_index = def.gmem_index,
      points = deep_copy(def.default_points),
      interpolation = "smooth"  -- "linear" or "smooth"
    }
  end
end

-- Sort curve points by X coordinate
local function sort_curve_points(curve)
  table.sort(curve.points, function(a, b) return a.x < b.x end)
end

-- Find segment index for a given X value (binary search)
local function find_segment(curve, x)
  local points = curve.points
  local n = #points

  if n == 0 then return 0 end
  if x <= points[1].x then return 0 end
  if x >= points[n].x then return n end

  -- Binary search for segment
  local lo, hi = 1, n
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if points[mid].x < x then
      lo = mid + 1
    else
      hi = mid
    end
  end

  return lo - 1
end

-- Catmull-Rom spline interpolation
local function catmull_rom(t, p0, p1, p2, p3)
  local t2 = t * t
  local t3 = t2 * t

  return 0.5 * (
    (2 * p1) +
    (-p0 + p2) * t +
    (2*p0 - 5*p1 + 4*p2 - p3) * t2 +
    (-p0 + 3*p1 - 3*p2 + p3) * t3
  )
end

-- Evaluate curve at a given X position (Updated for Logarithmic safety)
local function curve_evaluate(curve, x)
  local points = curve.points
  local n = #points

  if n == 0 then
    return (curve.y_min + curve.y_max) / 2
  end

  if n == 1 then
    return points[1].y
  end

  -- Clamp X to curve range
  if x <= points[1].x then return points[1].y end
  if x >= points[n].x then return points[n].y end

  -- Find the segment containing x
  local seg = find_segment(curve, x)
  if seg < 1 then seg = 1 end
  if seg >= n then seg = n - 1 end

  local p1 = points[seg]
  local p2 = points[seg + 1]

  -- Parameter t within segment [0, 1]
  local t = inverse_lerp(p1.x, p2.x, x)

  -- HELPER: Get value in correct domain (Linear or Log)
  local function get_y(p)
    if curve.y_scale == "log" then
      return math.log(math.max(p.y, 0.0001)) -- Protect against log(0)
    else
      return p.y
    end
  end

  local val
  if curve.interpolation == "linear" then
    local y1, y2 = get_y(p1), get_y(p2)
    val = lerp(y1, y2, t)
  else
    -- Catmull-Rom spline
    local p0 = seg > 1 and points[seg - 1] or {x = p1.x - 1, y = p1.y}
    local p3 = seg + 2 <= n and points[seg + 2] or {x = p2.x + 1, y = p2.y}
    
    local y0, y1, y2, y3 = get_y(p0), get_y(p1), get_y(p2), get_y(p3)
    val = catmull_rom(t, y0, y1, y2, y3)
  end

  -- Convert back from Log domain if necessary
  if curve.y_scale == "log" then
    val = math.exp(val)
  end

  -- Final safety clamp
  return clamp(val, curve.y_min, curve.y_max)
end

-- Add a point to a curve
local function curve_add_point(curve, x, y)
  -- Clamp to valid ranges
  x = clamp(x, DISTANCE_MIN, DISTANCE_MAX)
  y = clamp(y, curve.y_min, curve.y_max)

  -- Don't add if too close to existing point
  for _, p in ipairs(curve.points) do
    if math.abs(p.x - x) < 0.5 then
      return false
    end
  end

  table.insert(curve.points, {x = x, y = y})
  sort_curve_points(curve)
  state.dirty = true
  return true
end

-- Move a point on a curve
local function curve_move_point(curve, point_idx, new_x, new_y)
  local point = curve.points[point_idx]
  if not point then return false end

  local n = #curve.points

  -- Constrain X to stay between neighbors
  local min_x = DISTANCE_MIN
  local max_x = DISTANCE_MAX

  if point_idx > 1 then
    min_x = curve.points[point_idx - 1].x + 0.5
  end
  if point_idx < n then
    max_x = curve.points[point_idx + 1].x - 0.5
  end

  point.x = clamp(new_x, min_x, max_x)
  point.y = clamp(new_y, curve.y_min, curve.y_max)
  state.dirty = true
  return true
end

-- Remove a point from a curve
local function curve_remove_point(curve, point_idx)
  -- Must keep at least 2 points
  if #curve.points <= 2 then
    return false
  end

  table.remove(curve.points, point_idx)
  state.dirty = true
  return true
end

-- Evaluate all curves at current distance
local function evaluate_all_curves()
  for i, curve in ipairs(state.curves) do
    state.evaluated_values[i] = curve_evaluate(curve, state.current_distance)
  end
end

-- Compute final output values (curve + base offset, clamped)
-- This is the single authoritative function for computing values sent to JSFX and displayed in UI
-- Base values are displayed as absolute values; offset is calculated from unattenuated reference:
--   Volume reference: 0 dB, HP reference: 20 Hz, LP reference: 20000 Hz, Spread reference: 100%
local function compute_output_values()
  -- First evaluate all curves at current distance
  evaluate_all_curves()

  -- Calculate offsets from reference values and apply to curve values
  -- If a curve is disabled, output its reference value (no effect)

  -- Index 1 = Volume (dB): reference is 0, so offset = base_value - 0 = base_value
  if state.curve_enabled[1] then
    local vol_offset = state.base.volume_db  -- reference: 0
    local vol_result = state.evaluated_values[1] + vol_offset
    state.output_values[1] = clamp(vol_result, state.curves[1].y_min, state.curves[1].y_max)
  else
    state.output_values[1] = 0  -- Reference: no volume attenuation
  end

  -- Index 2 = HPF (Hz): reference is 20, offset = base_value - 20
  if state.curve_enabled[2] then
    local hp_offset = state.base.hp_hz - 20  -- reference: 20
    local hp_result = state.evaluated_values[2] + hp_offset
    state.output_values[2] = clamp(hp_result, 20, 20000)
  else
    state.output_values[2] = 20  -- Reference: HPF at lowest (off)
  end

  -- Index 3 = LPF (Hz): reference is 20000, offset = base_value - 20000
  if state.curve_enabled[3] then
    local lp_offset = state.base.lp_hz - 20000  -- reference: 20000
    local lp_result = state.evaluated_values[3] + lp_offset
    state.output_values[3] = clamp(lp_result, 20, 20000)
  else
    state.output_values[3] = 20000  -- Reference: LPF at highest (off)
  end

  -- Index 4 = Spread (%): reference is 100, offset = base_value - 100
  if state.curve_enabled[4] then
    local spread_offset = state.base.spread_pct - 100  -- reference: 100
    local spread_result = state.evaluated_values[4] + spread_offset
    state.output_values[4] = clamp(spread_result, 0, 100)
  else
    state.output_values[4] = 100  -- Reference: full stereo spread
  end
end

-- =============================================================================
-- CUSTOM FX PARAMETER CURVES
-- =============================================================================
-- Allows users to capture arbitrary FX parameters and drive them over distance
-- using custom curves. Links are created via REAPER parameter linking.

-- Generate a unique ID for custom params
local custom_param_id_counter = 0
generate_custom_id = function()
  custom_param_id_counter = custom_param_id_counter + 1
  return string.format("custom_%d_%d", os.time(), custom_param_id_counter)
end

-- Generate a random color that contrasts with the graph background (0x14141AFF)
-- Avoids colors too close to black/dark gray
generate_random_curve_color = function()
  local function rand_channel()
    return math.random(100, 255)  -- Avoid dark colors
  end
  local r = rand_channel()
  local g = rand_channel()
  local b = rand_channel()
  -- Ensure at least one channel is bright
  if r < 150 and g < 150 and b < 150 then
    local boost = math.random(1, 3)
    if boost == 1 then r = 200 + math.random(55)
    elseif boost == 2 then g = 200 + math.random(55)
    else b = 200 + math.random(55) end
  end
  -- Return in 0xRRGGBBAA format
  return (r * 0x1000000) + (g * 0x10000) + (b * 0x100) + 0xFF
end

-- Initialize custom slot tracking
init_custom_slots = function()
  for i = 1, JSFX_CUSTOM_SLOT_COUNT do
    state.custom_slot_used[i] = false
  end
end

-- Allocate first available custom slot (1-8)
-- Returns slot number (1-8) or nil if all used
local function allocate_custom_slot()
  for i = 1, JSFX_CUSTOM_SLOT_COUNT do
    if not state.custom_slot_used[i] then
      state.custom_slot_used[i] = true
      return i
    end
  end
  return nil
end

-- Free a custom slot
local function free_custom_slot(slot)
  if slot and slot >= 1 and slot <= JSFX_CUSTOM_SLOT_COUNT then
    state.custom_slot_used[slot] = false
  end
end

-- Find track by GUID
local function find_track_by_guid(guid)
  if not guid then return nil end
  local num_tracks = reaper.CountTracks(0)
  for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    if track then
      local track_guid = reaper.GetTrackGUID(track)
      if track_guid == guid then
        return track
      end
    end
  end
  -- Check master track
  local master = reaper.GetMasterTrack(0)
  if master and reaper.GetTrackGUID(master) == guid then
    return master
  end
  return nil
end

-- Find FX index by FX GUID on a track
-- Returns fx_index or nil if not found
local function find_fx_by_guid(track, fx_guid)
  if not track or not fx_guid then return nil end
  local MONITOR_FX_OFFSET = 0x1000000

  -- Check regular FX chain
  local fx_count = reaper.TrackFX_GetCount(track)
  for i = 0, fx_count - 1 do
    local guid = reaper.TrackFX_GetFXGUID(track, i)
    if guid == fx_guid then
      return i
    end
  end

  -- Check monitor FX chain (for master track)
  local mon_fx_count = reaper.TrackFX_GetRecCount(track)
  for i = 0, mon_fx_count - 1 do
    local guid = reaper.TrackFX_GetFXGUID(track, MONITOR_FX_OFFSET + i)
    if guid == fx_guid then
      return MONITOR_FX_OFFSET + i
    end
  end

  return nil
end

-- Find AVS_Attenuator JSFX on a specific track
-- Returns fx_index or nil
local function find_jsfx_on_track(track)
  if not track then return nil end
  local MONITOR_FX_OFFSET = 0x1000000

  -- Check regular FX chain
  local fx_count = reaper.TrackFX_GetCount(track)
  for i = 0, fx_count - 1 do
    local _, name = reaper.TrackFX_GetFXName(track, i, "")
    if name:lower():match("avs_attenuator") then
      return i
    end
  end

  -- Check monitor FX chain (for master track)
  local mon_fx_count = reaper.TrackFX_GetRecCount(track)
  for i = 0, mon_fx_count - 1 do
    local _, name = reaper.TrackFX_GetFXName(track, MONITOR_FX_OFFSET + i, "")
    if name:lower():match("avs_attenuator") then
      return MONITOR_FX_OFFSET + i
    end
  end

  return nil
end

-- Get the JSFX GUID for storing (more stable than index)
local function get_jsfx_guid_on_track(track)
  local jsfx_idx = find_jsfx_on_track(track)
  if jsfx_idx then
    return reaper.TrackFX_GetFXGUID(track, jsfx_idx)
  end
  return nil
end

-- Get track name for display
local function get_track_display_name(track)
  if not track then return "Unknown Track" end
  if track == reaper.GetMasterTrack(0) then
    return "Master"
  end
  local _, name = reaper.GetTrackName(track)
  local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  if name and name ~= "" then
    return string.format("Track %d: %s", math.floor(idx), name)
  else
    return string.format("Track %d", math.floor(idx))
  end
end

-- Create a parameter link from JSFX custom slot to target FX parameter
-- Uses REAPER's TrackFX_SetNamedConfigParm to configure the link
-- Link semantics: target param linked FROM source param (JSFX slot)
local function create_param_link(track, dest_fx_idx, dest_param_idx, source_fx_idx, source_param_idx)
  if not track or not dest_fx_idx or not dest_param_idx then
    return false, "Invalid parameters"
  end

  local MONITOR_FX_OFFSET = 0x1000000

  -- The parameter link is configured on the DESTINATION parameter
  -- REAPER's param linking: destination is controlled by source
  -- Configuration via plink.active, plink.effect, plink.param, plink.scale, plink.offset

  -- For plink.effect, REAPER expects the raw FX index within the chain.
  -- When both FX are in the monitor chain, strip the offset from source_fx_idx.
  local dest_is_monitor = dest_fx_idx >= MONITOR_FX_OFFSET
  local source_is_monitor = source_fx_idx >= MONITOR_FX_OFFSET
  local plink_effect_idx = source_fx_idx
  if dest_is_monitor and source_is_monitor then
    plink_effect_idx = source_fx_idx - MONITOR_FX_OFFSET
  end

  -- Activate the link
  local ok1 = reaper.TrackFX_SetNamedConfigParm(track, dest_fx_idx, "param." .. dest_param_idx .. ".plink.active", "1")

  -- Set source FX (the JSFX) - use raw index within chain
  local ok2 = reaper.TrackFX_SetNamedConfigParm(track, dest_fx_idx, "param." .. dest_param_idx .. ".plink.effect", tostring(plink_effect_idx))

  -- Set source parameter (the custom slot)
  local ok3 = reaper.TrackFX_SetNamedConfigParm(track, dest_fx_idx, "param." .. dest_param_idx .. ".plink.param", tostring(source_param_idx))

  -- Set scale (1.0 = full range)
  local ok4 = reaper.TrackFX_SetNamedConfigParm(track, dest_fx_idx, "param." .. dest_param_idx .. ".plink.scale", "1.0")

  -- Set offset (0.0 = no offset)
  local ok5 = reaper.TrackFX_SetNamedConfigParm(track, dest_fx_idx, "param." .. dest_param_idx .. ".plink.offset", "0.0")

  -- Set mirror to 0 (no reverse scaling)
  reaper.TrackFX_SetNamedConfigParm(track, dest_fx_idx, "param." .. dest_param_idx .. ".plink.mirror", "0")

  if ok1 and ok2 and ok3 and ok4 and ok5 then
    return true
  else
    return false, "Failed to set link parameters"
  end
end

-- Remove parameter link from a target FX parameter
remove_param_link = function(track, dest_fx_idx, dest_param_idx)
  if not track or not dest_fx_idx or not dest_param_idx then
    return false
  end

  -- Deactivate the link
  local ok = reaper.TrackFX_SetNamedConfigParm(track, dest_fx_idx, "param." .. dest_param_idx .. ".plink.active", "0")
  return ok
end

-- Get last touched FX parameter
-- Returns: success, track, fx_idx, param_idx, is_take_fx
local function get_last_touched_param()
  local MONITOR_FX_OFFSET = 0x1000000

  local retval, track_number, fx_number, param_number = reaper.GetLastTouchedFX()
  if not retval then
    -- Fallback: try GetTouchedOrFocusedFX (mode 0 = last touched parameter)
    if reaper.GetTouchedOrFocusedFX then
      local ok, trackidx, itemidx, takeidx, fxidx, parm = reaper.GetTouchedOrFocusedFX(0)
      if ok and itemidx == -1 then  -- Not a take FX
        local track
        if trackidx == -1 then
          track = reaper.GetMasterTrack(0)
        else
          track = reaper.GetTrack(0, trackidx)
        end
        if track then
          -- For monitoring FX, fxidx has 0x1000000 set (already in correct format)
          return true, track, fxidx, parm, false
        end
      elseif ok and itemidx >= 0 then
        return false, nil, nil, nil, true  -- Take FX (not supported)
      end
    end
    return false
  end

  -- Check if it's a take FX (high bit set on track_number)
  -- Take FX: track_number has bit 24 set (0x1000000)
  local is_take_fx = (track_number & 0x1000000) ~= 0

  if is_take_fx then
    return false, nil, nil, nil, true  -- Signal that it's take FX (not supported)
  end

  -- Get the track
  local track
  if track_number == 0 then
    track = reaper.GetMasterTrack(0)
  else
    track = reaper.GetTrack(0, track_number - 1)
  end

  if not track then
    return false
  end

  -- fx_number encodes both FX index and whether it's input/monitor FX
  -- Bits 24-25: 0=normal, 1=rec input FX, 2=monitor FX
  local fx_type = (fx_number >> 24) & 0x3
  local fx_idx = fx_number & 0xFFFFFF

  -- For monitor FX, add the offset
  if fx_type == 2 then
    fx_idx = MONITOR_FX_OFFSET + fx_idx
  end

  return true, track, fx_idx, param_number, false
end

-- Get full info about a parameter for display
local function get_param_display_info(track, fx_idx, param_idx)
  if not track or not fx_idx then
    return nil
  end

  local _, fx_name = reaper.TrackFX_GetFXName(track, fx_idx, "")
  local _, param_name = reaper.TrackFX_GetParamName(track, fx_idx, param_idx, "")
  local track_name = get_track_display_name(track)

  -- Create short name (truncated)
  local short_name = param_name or "Param"
  if #short_name > 15 then
    short_name = short_name:sub(1, 12) .. "..."
  end

  return {
    track_name = track_name,
    fx_name = fx_name or "Unknown FX",
    param_name = param_name or "Unknown Param",
    short_name = short_name
  }
end

-- Resolve a custom param entry - find current FX indices from GUIDs
-- Returns: resolved (bool), track, fx_idx
resolve_custom_param = function(param)
  if not param then return false end

  local track = find_track_by_guid(param.track_guid)
  if not track then
    return false
  end

  local fx_idx = find_fx_by_guid(track, param.fx_guid)
  if not fx_idx then
    return false
  end

  return true, track, fx_idx
end

-- Create default curve points for a custom parameter (normalized 0-1)
create_default_custom_curve = function()
  return {
    {x = 0, y = 1.0},
    {x = 50, y = 0.5},
    {x = 100, y = 0.0}
  }
end

-- Evaluate a custom curve at a given distance (returns 0-1 normalized)
local function custom_curve_evaluate(param, x)
  if not param or not param.curve then return 0.5 end

  local points = param.curve
  local n = #points

  if n == 0 then return 0.5 end
  if n == 1 then return clamp(points[1].y, 0, 1) end

  -- Clamp X to curve range
  if x <= points[1].x then return clamp(points[1].y, 0, 1) end
  if x >= points[n].x then return clamp(points[n].y, 0, 1) end

  -- Find segment
  local seg = 1
  for i = 1, n - 1 do
    if x >= points[i].x and x <= points[i+1].x then
      seg = i
      break
    end
  end

  local p1 = points[seg]
  local p2 = points[seg + 1]

  local t = inverse_lerp(p1.x, p2.x, x)

  local val
  if param.interpolation == "linear" then
    val = lerp(p1.y, p2.y, t)
  else
    -- Catmull-Rom spline
    local p0 = seg > 1 and points[seg - 1] or {x = p1.x - 1, y = p1.y}
    local p3 = seg + 2 <= n and points[seg + 2] or {x = p2.x + 1, y = p2.y}
    val = catmull_rom(t, p0.y, p1.y, p2.y, p3.y)
  end

  return clamp(val, 0, 1)
end

-- Add a new custom parameter from last touched FX
-- Returns: success, error_message
local function add_custom_param_from_last_touched()
  -- Get last touched parameter
  local success, track, fx_idx, param_idx, is_take_fx = get_last_touched_param()

  if is_take_fx then
    return false, "Take FX not supported. Please use track FX."
  end

  if not success or not track then
    return false, "No parameter touched. Please adjust a parameter on an FX first."
  end

  -- Check if this is our own JSFX (don't allow linking to self)
  local _, fx_name = reaper.TrackFX_GetFXName(track, fx_idx, "")
  if fx_name:lower():match("avs_attenuator") then
    return false, "Cannot link to AVS_Attenuator itself."
  end

  -- Allocate a slot
  local slot = allocate_custom_slot()
  if not slot then
    return false, "All 8 custom parameter slots are in use. Remove one first."
  end

  -- Find the JSFX on the same track
  local jsfx_idx = find_jsfx_on_track(track)
  if not jsfx_idx then
    -- Try to find JSFX on any track and warn user
    free_custom_slot(slot)
    return false, "AVS_Attenuator JSFX not found on the same track as the target FX. Please add it first."
  end

  -- Get GUIDs for stable storage
  local track_guid = reaper.GetTrackGUID(track)
  local fx_guid = reaper.TrackFX_GetFXGUID(track, fx_idx)
  local jsfx_guid = reaper.TrackFX_GetFXGUID(track, jsfx_idx)

  if not fx_guid then
    free_custom_slot(slot)
    return false, "Could not get FX GUID."
  end

  -- Get display info
  local info = get_param_display_info(track, fx_idx, param_idx)
  if not info then
    free_custom_slot(slot)
    return false, "Could not get parameter info."
  end

  -- Calculate JSFX custom slot parameter index (0-indexed)
  local jsfx_slot_param_idx = JSFX_CUSTOM_SLOT_BASE + slot - 1

  -- Create the parameter link
  local link_ok, link_err = create_param_link(track, fx_idx, param_idx, jsfx_idx, jsfx_slot_param_idx)
  if not link_ok then
    free_custom_slot(slot)
    return false, "Failed to create parameter link: " .. (link_err or "unknown error")
  end

  -- Create the custom param entry
  local param_entry = {
    id = generate_custom_id(),
    track_guid = track_guid,
    fx_guid = fx_guid,
    jsfx_guid = jsfx_guid,
    param_index = param_idx,
    jsfx_slot = slot,
    name_short = info.short_name,
    name_full = info.param_name,
    fx_name = info.fx_name,
    track_name = info.track_name,
    curve = create_default_custom_curve(),
    interpolation = "smooth",
    color = generate_random_curve_color(),
    enabled = true,
    resolved = true
  }

  table.insert(state.custom_params, param_entry)
  state.selected_custom_id = param_entry.id

  -- Set initial value (at current distance)
  local initial_value = custom_curve_evaluate(param_entry, state.current_distance)
  reaper.TrackFX_SetParamNormalized(track, jsfx_idx, jsfx_slot_param_idx, initial_value)

  return true
end

-- Remove a custom parameter by ID
local function remove_custom_param(param_id)
  if not param_id then return false end

  -- Find the param entry
  local param_entry = nil
  local param_index = nil
  for i, p in ipairs(state.custom_params) do
    if p.id == param_id then
      param_entry = p
      param_index = i
      break
    end
  end

  if not param_entry then
    return false, "Parameter not found"
  end

  -- Try to remove the link (even if target doesn't exist anymore)
  local resolved, track, fx_idx = resolve_custom_param(param_entry)
  if resolved and track and fx_idx then
    remove_param_link(track, fx_idx, param_entry.param_index)
  end

  -- Free the slot
  free_custom_slot(param_entry.jsfx_slot)

  -- Remove from list
  table.remove(state.custom_params, param_index)

  -- Clear selection if this was selected
  if state.selected_custom_id == param_id then
    state.selected_custom_id = nil
    -- Select another if available
    if #state.custom_params > 0 then
      state.selected_custom_id = state.custom_params[1].id
    end
  end

  return true
end

-- Resolve all custom params and recreate links
resolve_and_link_all_custom_params = function()
  for _, param in ipairs(state.custom_params) do
    local resolved, track, fx_idx = resolve_custom_param(param)
    param.resolved = resolved

    if resolved and track and fx_idx then
      -- Find JSFX on the track
      local jsfx_idx = find_jsfx_on_track(track)
      if jsfx_idx then
        local jsfx_slot_param_idx = JSFX_CUSTOM_SLOT_BASE + param.jsfx_slot - 1
        create_param_link(track, fx_idx, param.param_index, jsfx_idx, jsfx_slot_param_idx)
      else
        param.resolved = false
      end
    end
  end
end

-- Update all custom JSFX slots with current curve values
local function update_custom_params_to_jsfx()
  for _, param in ipairs(state.custom_params) do
    if param.resolved and param.enabled ~= false then
      local track = find_track_by_guid(param.track_guid)
      if track then
        local jsfx_idx = find_jsfx_on_track(track)
        if jsfx_idx then
          local value = custom_curve_evaluate(param, state.current_distance)
          local jsfx_slot_param_idx = JSFX_CUSTOM_SLOT_BASE + param.jsfx_slot - 1
          reaper.TrackFX_SetParamNormalized(track, jsfx_idx, jsfx_slot_param_idx, value)
        end
      end
    end
  end
end

-- Get custom param by ID
local function get_custom_param_by_id(param_id)
  for _, p in ipairs(state.custom_params) do
    if p.id == param_id then
      return p
    end
  end
  return nil
end

-- =============================================================================
-- COORDINATE TRANSFORMS
-- =============================================================================

-- Convert curve coordinates to screen coordinates
local function to_screen(x, y, curve)
  local rect = state.graph_rect

  -- X transform (linear: distance)
  local norm_x = inverse_lerp(DISTANCE_MIN, DISTANCE_MAX, x)
  local sx = rect.x + norm_x * rect.w

  -- Y transform (depends on scale)
  local norm_y
  if curve.y_scale == "log" then
    -- Logarithmic scale for frequency
    local log_min = math.log(curve.y_min)
    local log_max = math.log(curve.y_max)
    local log_y = math.log(clamp(y, curve.y_min, curve.y_max))
    norm_y = inverse_lerp(log_min, log_max, log_y)
  else
    -- Linear scale
    norm_y = inverse_lerp(curve.y_min, curve.y_max, y)
  end

  -- Flip Y (screen Y increases downward)
  local sy = rect.y + (1 - norm_y) * rect.h

  return sx, sy
end

-- Convert screen coordinates to curve coordinates
local function from_screen(sx, sy, curve)
  local rect = state.graph_rect

  -- X transform
  local norm_x = (sx - rect.x) / rect.w
  local x = lerp(DISTANCE_MIN, DISTANCE_MAX, norm_x)

  -- Y transform (flip Y first)
  local norm_y = 1 - (sy - rect.y) / rect.h

  local y
  if curve.y_scale == "log" then
    local log_min = math.log(curve.y_min)
    local log_max = math.log(curve.y_max)
    local log_y = lerp(log_min, log_max, norm_y)
    y = math.exp(log_y)
  else
    y = lerp(curve.y_min, curve.y_max, norm_y)
  end

  return x, y
end

-- =============================================================================
-- CUSTOM CURVE COORDINATE TRANSFORMS
-- =============================================================================
-- Custom curves use normalized Y values (0-1) on the same X axis (0-100 distance)

-- Virtual curve definition for custom params (used by coordinate transforms)
local CUSTOM_CURVE_DEF = {
  y_min = 0,
  y_max = 1,
  y_scale = "linear"
}

-- Convert custom curve coordinates to screen coordinates
local function custom_to_screen(x, y)
  local rect = state.graph_rect

  -- X transform (linear: distance)
  local norm_x = inverse_lerp(DISTANCE_MIN, DISTANCE_MAX, x)
  local sx = rect.x + norm_x * rect.w

  -- Y transform (linear: 0-1 normalized)
  local norm_y = inverse_lerp(CUSTOM_CURVE_DEF.y_min, CUSTOM_CURVE_DEF.y_max, y)

  -- Flip Y (screen Y increases downward)
  local sy = rect.y + (1 - norm_y) * rect.h

  return sx, sy
end

-- Convert screen coordinates to custom curve coordinates
local function custom_from_screen(sx, sy)
  local rect = state.graph_rect

  -- X transform
  local norm_x = (sx - rect.x) / rect.w
  local x = lerp(DISTANCE_MIN, DISTANCE_MAX, norm_x)

  -- Y transform (flip Y first)
  local norm_y = 1 - (sy - rect.y) / rect.h
  local y = lerp(CUSTOM_CURVE_DEF.y_min, CUSTOM_CURVE_DEF.y_max, norm_y)

  return x, y
end

-- Add a point to a custom curve
local function custom_curve_add_point(param, x, y)
  if not param or not param.curve then return false end

  -- Clamp to valid ranges
  x = clamp(x, DISTANCE_MIN, DISTANCE_MAX)
  y = clamp(y, 0, 1)

  -- Don't add if too close to existing point
  for _, p in ipairs(param.curve) do
    if math.abs(p.x - x) < 0.5 then
      return false
    end
  end

  table.insert(param.curve, {x = x, y = y})
  -- Sort by X
  table.sort(param.curve, function(a, b) return a.x < b.x end)
  state.dirty = true
  return true
end

-- Move a point on a custom curve
local function custom_curve_move_point(param, point_idx, new_x, new_y)
  if not param or not param.curve then return false end
  local point = param.curve[point_idx]
  if not point then return false end

  local n = #param.curve

  -- Constrain X to stay between neighbors
  local min_x = DISTANCE_MIN
  local max_x = DISTANCE_MAX

  if point_idx > 1 then
    min_x = param.curve[point_idx - 1].x + 0.5
  end
  if point_idx < n then
    max_x = param.curve[point_idx + 1].x - 0.5
  end

  point.x = clamp(new_x, min_x, max_x)
  point.y = clamp(new_y, 0, 1)
  state.dirty = true
  return true
end

-- Remove a point from a custom curve
local function custom_curve_remove_point(param, point_idx)
  if not param or not param.curve then return false end
  -- Must keep at least 2 points
  if #param.curve <= 2 then
    return false
  end

  table.remove(param.curve, point_idx)
  state.dirty = true
  return true
end

-- =============================================================================
-- SERIALIZATION
-- =============================================================================

-- Save current state to ExtState
save_state = function()
  for i, curve in ipairs(state.curves) do
    local key = "curve_" .. curve.id
    local value = json_encode_points(curve.points)
    reaper.SetExtState(EXTSTATE_SECTION, key, value, true)

    -- Save interpolation mode
    local interp_key = "interp_" .. curve.id
    reaper.SetExtState(EXTSTATE_SECTION, interp_key, curve.interpolation, true)
  end

  -- Save visibility
  local vis_str = ""
  for i = 1, 4 do
    vis_str = vis_str .. (state.curve_visible[i] and "1" or "0")
  end
  reaper.SetExtState(EXTSTATE_SECTION, "visibility", vis_str, true)

  -- Save enabled state
  local enabled_str = ""
  for i = 1, 4 do
    enabled_str = enabled_str .. (state.curve_enabled[i] and "1" or "0")
  end
  reaper.SetExtState(EXTSTATE_SECTION, "enabled", enabled_str, true)

  -- Save current distance
  reaper.SetExtState(EXTSTATE_SECTION, "distance", tostring(state.current_distance), true)

  -- Save display max distance
  reaper.SetExtState(EXTSTATE_SECTION, "display_max_distance", tostring(state.display_max_distance), true)

  -- Save active curve
  reaper.SetExtState(EXTSTATE_SECTION, "active_curve", tostring(state.active_curve), true)

  -- Save base attenuation values
  reaper.SetExtState(EXTSTATE_SECTION, "base_volume_db", tostring(state.base.volume_db), true)
  reaper.SetExtState(EXTSTATE_SECTION, "base_hp_hz", tostring(state.base.hp_hz), true)
  reaper.SetExtState(EXTSTATE_SECTION, "base_lp_hz", tostring(state.base.lp_hz), true)
  reaper.SetExtState(EXTSTATE_SECTION, "base_spread_pct", tostring(state.base.spread_pct), true)

  -- Save auto-bypass setting
  reaper.SetExtState(EXTSTATE_SECTION, "auto_bypass_on_exit", state.auto_bypass_on_exit and "1" or "0", true)

  -- Save custom parameters
  local custom_data = {}
  for _, param in ipairs(state.custom_params) do
    table.insert(custom_data, {
      id = param.id,
      track_guid = param.track_guid,
      fx_guid = param.fx_guid,
      jsfx_guid = param.jsfx_guid,
      param_index = param.param_index,
      jsfx_slot = param.jsfx_slot,
      name_short = param.name_short,
      name_full = param.name_full,
      fx_name = param.fx_name,
      track_name = param.track_name,
      curve = param.curve,
      interpolation = param.interpolation,
      color = param.color,
      enabled = param.enabled
    })
  end
  local custom_json = json.encode(custom_data, {})
  reaper.SetExtState(EXTSTATE_SECTION, "custom_params", custom_json, true)

  -- Save selected custom param
  reaper.SetExtState(EXTSTATE_SECTION, "selected_custom_id", state.selected_custom_id or "", true)
end

-- Load state from ExtState
local function load_state()
  for i, curve in ipairs(state.curves) do
    local key = "curve_" .. curve.id
    local value = reaper.GetExtState(EXTSTATE_SECTION, key)

    if value and value ~= "" then
      local points = json_decode_points(value)
      if #points >= 2 then
        curve.points = points
        sort_curve_points(curve)
      end
    end

    -- Load interpolation mode
    local interp_key = "interp_" .. curve.id
    local interp = reaper.GetExtState(EXTSTATE_SECTION, interp_key)
    if interp == "linear" or interp == "smooth" then
      curve.interpolation = interp
    end
  end

  -- Load visibility
  local vis_str = reaper.GetExtState(EXTSTATE_SECTION, "visibility")
  if vis_str and #vis_str == 4 then
    for i = 1, 4 do
      state.curve_visible[i] = vis_str:sub(i, i) == "1"
    end
  end

  -- Load enabled state
  local enabled_str = reaper.GetExtState(EXTSTATE_SECTION, "enabled")
  if enabled_str and #enabled_str == 4 then
    for i = 1, 4 do
      state.curve_enabled[i] = enabled_str:sub(i, i) == "1"
    end
  end

  -- Load current distance
  local dist_str = reaper.GetExtState(EXTSTATE_SECTION, "distance")
  if dist_str and dist_str ~= "" then
    state.current_distance = clamp(tonumber(dist_str) or 10, DISTANCE_MIN, DISTANCE_MAX)
  end

  -- Load display max distance
  local max_dist_str = reaper.GetExtState(EXTSTATE_SECTION, "display_max_distance")
  if max_dist_str and max_dist_str ~= "" then
    state.display_max_distance = clamp(tonumber(max_dist_str) or 100, 1, 100000)
  end

  -- Load active curve
  local active_str = reaper.GetExtState(EXTSTATE_SECTION, "active_curve")
  if active_str and active_str ~= "" then
    state.active_curve = clamp(tonumber(active_str) or 1, 1, 4)
  end

  -- Load base attenuation values (default to unattenuated reference values if not present)
  -- Reference values: Volume=0, HP=20, LP=20000, Spread=100
  local base_vol = reaper.GetExtState(EXTSTATE_SECTION, "base_volume_db")
  state.base.volume_db = (base_vol and base_vol ~= "") and (tonumber(base_vol) or 0.0) or 0.0

  local base_hp = reaper.GetExtState(EXTSTATE_SECTION, "base_hp_hz")
  state.base.hp_hz = (base_hp and base_hp ~= "") and (tonumber(base_hp) or 20.0) or 20.0

  local base_lp = reaper.GetExtState(EXTSTATE_SECTION, "base_lp_hz")
  state.base.lp_hz = (base_lp and base_lp ~= "") and (tonumber(base_lp) or 20000.0) or 20000.0

  local base_spread = reaper.GetExtState(EXTSTATE_SECTION, "base_spread_pct")
  state.base.spread_pct = (base_spread and base_spread ~= "") and (tonumber(base_spread) or 100.0) or 100.0

  -- Load auto-bypass setting
  local auto_bypass = reaper.GetExtState(EXTSTATE_SECTION, "auto_bypass_on_exit")
  state.auto_bypass_on_exit = (auto_bypass == "1")

  -- Load custom parameters
  local custom_json = reaper.GetExtState(EXTSTATE_SECTION, "custom_params")
  if custom_json and custom_json ~= "" then
    local custom_data = json.decode(custom_json)
    if custom_data and type(custom_data) == "table" then
      state.custom_params = {}
      init_custom_slots()  -- Reset slot tracking

      for _, data in ipairs(custom_data) do
        -- Reconstruct param entry
        local param = {
          id = data.id or generate_custom_id(),
          track_guid = data.track_guid,
          fx_guid = data.fx_guid,
          jsfx_guid = data.jsfx_guid,
          param_index = data.param_index,
          jsfx_slot = data.jsfx_slot,
          name_short = data.name_short,
          name_full = data.name_full,
          fx_name = data.fx_name,
          track_name = data.track_name,
          curve = data.curve or create_default_custom_curve(),
          interpolation = data.interpolation or "smooth",
          color = data.color or generate_random_curve_color(),
          enabled = data.enabled ~= false,  -- Default to true for backwards compatibility
          resolved = false  -- Will be resolved below
        }

        -- Mark slot as used
        if param.jsfx_slot and param.jsfx_slot >= 1 and param.jsfx_slot <= JSFX_CUSTOM_SLOT_COUNT then
          state.custom_slot_used[param.jsfx_slot] = true
        end

        table.insert(state.custom_params, param)
      end

      -- Resolve and recreate links
      resolve_and_link_all_custom_params()
    end
  else
    init_custom_slots()  -- Initialize empty slot tracking
  end

  -- Load selected custom param
  local sel_custom = reaper.GetExtState(EXTSTATE_SECTION, "selected_custom_id")
  if sel_custom and sel_custom ~= "" then
    -- Verify it exists
    local found = false
    for _, p in ipairs(state.custom_params) do
      if p.id == sel_custom then
        found = true
        break
      end
    end
    state.selected_custom_id = found and sel_custom or nil
  end
end

-- =============================================================================
-- JSFX COMMUNICATION
-- =============================================================================

-- Initialize gmem communication
local function init_gmem()
  reaper.gmem_attach(GMEM_NAMESPACE)
end

-- Helper: Sanitize values to ensure they are valid numbers
local function sanitize(val, default)
  if val ~= val or val == math.huge or val == -math.huge then
    return default or 0.0
  end
  return val
end

-- Helper: Normalize frequency (Hz) to 0-1 using log scale
-- Maps 20-20000 Hz to 0-1 (logarithmic)
local function normalize_freq(hz)
  local min_hz = 20
  local max_hz = 20000
  hz = clamp(sanitize(hz, min_hz), min_hz, max_hz)
  return math.log(hz / min_hz) / math.log(max_hz / min_hz)
end

-- Helper: Set parameters on a found JSFX instance
local function set_jsfx_params(track, fx_idx, vol, hpf, lpf, spread)
  -- Volume and Spread: raw values
  -- HPF/LPF: normalized 0-1 (JSFX will convert back to Hz)
  reaper.TrackFX_SetParam(track, fx_idx, 0, sanitize(vol, 0))
  reaper.TrackFX_SetParam(track, fx_idx, 1, normalize_freq(hpf))
  reaper.TrackFX_SetParam(track, fx_idx, 2, normalize_freq(lpf))
  reaper.TrackFX_SetParam(track, fx_idx, 3, sanitize(spread, 100))
end

-- Helper: Find the JSFX and update its sliders directly
-- Searches: 1) Selected track FX, 2) Master track FX, 3) Monitor FX chain
local function sync_jsfx_parameters(vol, hpf, lpf, spread)
  -- Monitor FX chain offset (REAPER convention: 0x1000000 = 16777216)
  local MONITOR_FX_OFFSET = 0x1000000

  -- 1. Check selected track's FX chain
  local track = reaper.GetSelectedTrack(0, 0)
  if track then
    local fx_count = reaper.TrackFX_GetCount(track)
    for i = 0, fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(track, i, "")
      if name:lower():match("avs_attenuator") then
        set_jsfx_params(track, i, vol, hpf, lpf, spread)
        return
      end
    end
  end

  -- 2. Check master track's regular FX chain
  local master = reaper.GetMasterTrack(0)
  if master then
    local fx_count = reaper.TrackFX_GetCount(master)
    for i = 0, fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(master, i, "")
      if name:lower():match("avs_attenuator") then
        set_jsfx_params(master, i, vol, hpf, lpf, spread)
        return
      end
    end

    -- 3. Check master track's monitor FX chain
    -- Use offset 0x1000000 for both getting name and setting params
    local mon_fx_count = reaper.TrackFX_GetRecCount(master)
    for i = 0, mon_fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(master, MONITOR_FX_OFFSET + i, "")
      if name:lower():match("avs_attenuator") then
        set_jsfx_params(master, MONITOR_FX_OFFSET + i, vol, hpf, lpf, spread)
        return
      end
    end
  end
end

-- Helper: Find the AVS_Attenuator JSFX instance
-- Returns: track, fx_idx (with monitor offset if applicable), or nil, nil if not found
local function find_jsfx_instance()
  local MONITOR_FX_OFFSET = 0x1000000

  -- 1. Check selected track's FX chain
  local track = reaper.GetSelectedTrack(0, 0)
  if track then
    local fx_count = reaper.TrackFX_GetCount(track)
    for i = 0, fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(track, i, "")
      if name:lower():match("avs_attenuator") then
        return track, i
      end
    end
  end

  -- 2. Check master track's regular FX chain
  local master = reaper.GetMasterTrack(0)
  if master then
    local fx_count = reaper.TrackFX_GetCount(master)
    for i = 0, fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(master, i, "")
      if name:lower():match("avs_attenuator") then
        return master, i
      end
    end

    -- 3. Check master track's monitor FX chain
    local mon_fx_count = reaper.TrackFX_GetRecCount(master)
    for i = 0, mon_fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(master, MONITOR_FX_OFFSET + i, "")
      if name:lower():match("avs_attenuator") then
        return master, MONITOR_FX_OFFSET + i
      end
    end
  end

  return nil, nil
end

-- Get bypass state of the JSFX instance
-- Returns: true if bypassed, false if enabled, nil if not found
get_jsfx_bypass_state = function()
  local track, fx_idx = find_jsfx_instance()
  if not track then return nil end
  return reaper.TrackFX_GetEnabled(track, fx_idx) == false
end

-- Toggle bypass state of the JSFX instance
-- Returns: new bypass state (true=bypassed), or nil if not found
toggle_jsfx_bypass = function()
  local track, fx_idx = find_jsfx_instance()
  if not track then return nil end
  local currently_enabled = reaper.TrackFX_GetEnabled(track, fx_idx)
  reaper.TrackFX_SetEnabled(track, fx_idx, not currently_enabled)
  return currently_enabled  -- If was enabled, now bypassed (true)
end

-- Bypass all AVS_Attenuator JSFX instances across all tracks
-- Used for auto-bypass on script exit
local function bypass_all_jsfx()
  local MONITOR_FX_OFFSET = 0x1000000

  -- Check all regular tracks
  local num_tracks = reaper.CountTracks(0)
  for t = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, t)
    if track then
      local fx_count = reaper.TrackFX_GetCount(track)
      for i = 0, fx_count - 1 do
        local _, name = reaper.TrackFX_GetFXName(track, i, "")
        if name:lower():match("avs_attenuator") then
          reaper.TrackFX_SetEnabled(track, i, false)
        end
      end
    end
  end

  -- Check master track's regular FX chain
  local master = reaper.GetMasterTrack(0)
  if master then
    local fx_count = reaper.TrackFX_GetCount(master)
    for i = 0, fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(master, i, "")
      if name:lower():match("avs_attenuator") then
        reaper.TrackFX_SetEnabled(master, i, false)
      end
    end

    -- Check master track's monitor FX chain
    local mon_fx_count = reaper.TrackFX_GetRecCount(master)
    for i = 0, mon_fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(master, MONITOR_FX_OFFSET + i, "")
      if name:lower():match("avs_attenuator") then
        reaper.TrackFX_SetEnabled(master, MONITOR_FX_OFFSET + i, false)
      end
    end
  end
end

-- Unbypass all AVS_Attenuator JSFX instances across all tracks
-- Used for auto-unbypass on script start
local function unbypass_all_jsfx()
  local MONITOR_FX_OFFSET = 0x1000000

  -- Check all regular tracks
  local num_tracks = reaper.CountTracks(0)
  for t = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, t)
    if track then
      local fx_count = reaper.TrackFX_GetCount(track)
      for i = 0, fx_count - 1 do
        local _, name = reaper.TrackFX_GetFXName(track, i, "")
        if name:lower():match("avs_attenuator") then
          reaper.TrackFX_SetEnabled(track, i, true)
        end
      end
    end
  end

  -- Check master track's regular FX chain
  local master = reaper.GetMasterTrack(0)
  if master then
    local fx_count = reaper.TrackFX_GetCount(master)
    for i = 0, fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(master, i, "")
      if name:lower():match("avs_attenuator") then
        reaper.TrackFX_SetEnabled(master, i, true)
      end
    end

    -- Check master track's monitor FX chain
    local mon_fx_count = reaper.TrackFX_GetRecCount(master)
    for i = 0, mon_fx_count - 1 do
      local _, name = reaper.TrackFX_GetFXName(master, MONITOR_FX_OFFSET + i, "")
      if name:lower():match("avs_attenuator") then
        reaper.TrackFX_SetEnabled(master, MONITOR_FX_OFFSET + i, true)
      end
    end
  end
end

-- Send current output values to JSFX
local function update_jsfx()
  -- Rate limiting
  local current_time = reaper.time_precise()
  if current_time - state.last_update_time < UPDATE_INTERVAL then
    return
  end
  state.last_update_time = current_time

  -- Only update if dirty
  if not state.dirty then return end

  -- Compute output values (curve + base offset, clamped)
  compute_output_values()

  -- 1. Write to gmem (High speed, for audio thread)
  for i, curve in ipairs(state.curves) do
    reaper.gmem_write(curve.gmem_index, state.output_values[i])
  end

  -- Write distance to gmem (so JSFX slider stays in sync)
  reaper.gmem_write(GMEM_DISTANCE, state.current_distance)

  -- Set dirty flag for JSFX
  reaper.gmem_write(GMEM_DIRTY, 1)

  -- 2. Sync visual parameters on Selected Track (Wakes up plugin when stopped)
  -- Note: state.output_values indices are 1:Vol, 2:HPF, 3:LPF, 4:Spread
  sync_jsfx_parameters(
    state.output_values[1],
    state.output_values[2],
    state.output_values[3],
    state.output_values[4]
  )

  -- 3. Update custom parameter JSFX slots
  update_custom_params_to_jsfx()

  state.dirty = false
end

-- Force immediate update (bypass rate limiting)
force_update_jsfx = function()
  -- Compute output values (curve + base offset, clamped)
  compute_output_values()

  for i, curve in ipairs(state.curves) do
    reaper.gmem_write(curve.gmem_index, state.output_values[i])
  end

  -- Write distance to gmem (so JSFX slider stays in sync)
  reaper.gmem_write(GMEM_DISTANCE, state.current_distance)

  reaper.gmem_write(GMEM_DIRTY, 1)

  -- Sync parameters immediately
  sync_jsfx_parameters(
    state.output_values[1],
    state.output_values[2],
    state.output_values[3],
    state.output_values[4]
  )

  -- Update custom parameter JSFX slots
  update_custom_params_to_jsfx()

  state.dirty = false
  state.last_update_time = reaper.time_precise()
end

-- Check for distance updates from JSFX (for automation)
local function check_jsfx_distance()
  local dirty = reaper.gmem_read(GMEM_DISTANCE_DIRTY)
  if dirty == 1 then
    -- Read distance from JSFX
    local new_distance = reaper.gmem_read(GMEM_DISTANCE)
    new_distance = clamp(new_distance, DISTANCE_MIN, DISTANCE_MAX)

    -- Only update if different (avoid feedback loop)
    if math.abs(new_distance - state.current_distance) > 0.01 then
      state.current_distance = new_distance
      state.dirty = true
    end

    -- Clear dirty flag
    reaper.gmem_write(GMEM_DISTANCE_DIRTY, 0)
  end
end

-- =============================================================================
-- GUI RENDERING
-- =============================================================================

-- Get ImGui context and packages
local ImGui = {}

local function init_imgui()
  state.ctx = reaper.ImGui_CreateContext("AVS_Attenuator Editor")

  -- Populate ImGui table with functions
  for name, func in pairs(reaper) do
    if name:match("^ImGui_") then
      local short_name = name:sub(7)  -- Remove "ImGui_" prefix
      ImGui[short_name] = func
    end
  end
end

-- Draw the grid
local function draw_grid(draw_list)
  local rect = state.graph_rect
  local curve = state.curves[state.active_curve]
  local use_custom_grid = state.selected_custom_id ~= nil

  -- Vertical grid lines (distance)
  local x_step = 10  -- Every 10 distance units
  for x = DISTANCE_MIN, DISTANCE_MAX, x_step do
    local sx, _ = to_screen(x, curve.y_min, curve)
    local major = (x % 50 == 0)
    local color = major and COLORS.grid_major or COLORS.grid
    ImGui.DrawList_AddLine(draw_list, sx, rect.y, sx, rect.y + rect.h, color, 1)
  end

  -- Horizontal grid lines (value)
  local y_steps
  if use_custom_grid then
    -- Custom curves use 0-100% linear scale
    y_steps = {0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100}
  elseif curve.y_scale == "log" then
    -- Log scale: use powers of 10
    y_steps = {}
    local v = curve.y_min
    while v <= curve.y_max do
      table.insert(y_steps, v)
      if v < 100 then v = v * 2
      elseif v < 1000 then v = v + 100
      else v = v * 2 end
    end
  else
    -- Linear scale
    local range = curve.y_max - curve.y_min
    local step
    if range <= 10 then step = 1
    elseif range <= 50 then step = 5
    elseif range <= 100 then step = 10
    else step = 20 end

    -- Align grid lines to multiples of step (ensures 0 is included when in range)
    local start_y = math.ceil(curve.y_min / step) * step
    y_steps = {}
    for y = start_y, curve.y_max, step do
      table.insert(y_steps, y)
    end
  end

  for _, y in ipairs(y_steps) do
    local sy
    if use_custom_grid then
      -- Custom grid: y is 0-100, convert to 0-1 for custom_to_screen
      _, sy = custom_to_screen(DISTANCE_MIN, y / 100)
    else
      _, sy = to_screen(DISTANCE_MIN, y, curve)
    end
    if sy >= rect.y and sy <= rect.y + rect.h then
      local major
      if use_custom_grid then
        major = (y % 50 == 0)  -- 0%, 50%, 100% are major
      else
        major = (curve.y_scale ~= "log" and y % 20 == 0) or
                (curve.y_scale == "log" and (y == 100 or y == 1000 or y == 10000))
      end
      local color = major and COLORS.grid_major or COLORS.grid
      ImGui.DrawList_AddLine(draw_list, rect.x, sy, rect.x + rect.w, sy, color, 1)
    end
  end
end

-- Draw axis labels
local function draw_axes(draw_list)
  local rect = state.graph_rect
  local curve = state.curves[state.active_curve]
  local use_custom_grid = state.selected_custom_id ~= nil

  -- X-axis labels (distance) - show display-scaled values
  for x = DISTANCE_MIN, DISTANCE_MAX, 20 do
    local sx, _ = to_screen(x, curve.y_min, curve)
    local display_x = to_display_distance(x)
    local label = string.format("%.0f", display_x)
    ImGui.DrawList_AddText(draw_list, sx - 10, rect.y + rect.h + 5, COLORS.text, label)
  end

  -- X-axis title
  ImGui.DrawList_AddText(draw_list, rect.x + rect.w/2 - 23, rect.y + rect.h + 20, COLORS.text, "Distance")

  -- Y-axis labels (must match grid line positions from draw_grid)
  local y_labels
  if use_custom_grid then
    -- Custom curves use 0-100% linear scale
    y_labels = {0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100}
  elseif curve.y_scale == "log" then
    y_labels = {20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000}
  else
    -- Use same logic as draw_grid to align labels with grid lines
    local range = curve.y_max - curve.y_min
    local step
    if range <= 10 then step = 1
    elseif range <= 50 then step = 5
    elseif range <= 100 then step = 10
    else step = 20 end

    local start_y = math.ceil(curve.y_min / step) * step
    y_labels = {}
    for y = start_y, curve.y_max, step do
      table.insert(y_labels, y)
    end
  end

  for _, y in ipairs(y_labels) do
    local sy, label
    if use_custom_grid then
      -- Custom grid: y is 0-100, convert to 0-1 for custom_to_screen
      _, sy = custom_to_screen(DISTANCE_MIN, y / 100)
      label = string.format("%d%%", y)
    else
      if y < curve.y_min or y > curve.y_max then
        goto continue
      end
      _, sy = to_screen(DISTANCE_MIN, y, curve)
      label = format_value(y, curve.unit)
    end
    if sy >= rect.y - 5 and sy <= rect.y + rect.h + 5 then
      ImGui.DrawList_AddText(draw_list, rect.x - 55, sy - 7, COLORS.text, label)
    end
    ::continue::
  end
end

-- Draw a single curve
local function draw_curve(draw_list, curve_idx)
  local curve = state.curves[curve_idx]
  if #curve.points < 2 then return end

  local rect = state.graph_rect

  -- Sample curve at regular intervals
  local x_range = DISTANCE_MAX - DISTANCE_MIN
  local step = x_range / CURVE_SAMPLE_COUNT

  -- Build points array for polyline (reaper.new_array required by ReaImGui)
  local num_points = CURVE_SAMPLE_COUNT + 1
  local points = reaper.new_array(num_points * 2)

  for i = 0, CURVE_SAMPLE_COUNT do
    local x = DISTANCE_MIN + i * step
    local y = curve_evaluate(curve, x)
    local sx, sy = to_screen(x, y, curve)
    points[i * 2 + 1] = sx
    points[i * 2 + 2] = sy
  end

  -- Draw polyline (dimmer if disabled)
  local thickness = (curve_idx == state.active_curve) and 2.5 or 1.5
  local color = curve.color
  if not state.curve_enabled[curve_idx] then
    -- Make disabled curves semi-transparent (reduce alpha from FF to 40)
    color = (curve.color & 0xFFFFFF00) | 0x40
  end
  ImGui.DrawList_AddPolyline(draw_list, points, color, 0, thickness)
end

-- Draw control points for active curve
local function draw_control_points(draw_list)
  local curve_idx = state.active_curve
  local curve = state.curves[curve_idx]

  for i, point in ipairs(curve.points) do
    local sx, sy = to_screen(point.x, point.y, curve)

    local is_selected = state.selected_point and
                        state.selected_point[1] == curve_idx and
                        state.selected_point[2] == i
    local is_hovered = state.hovered_point and
                       state.hovered_point[1] == curve_idx and
                       state.hovered_point[2] == i

    -- Selected points are largest, then hovered, then normal
    local radius
    if is_selected then
      radius = POINT_HOVER_RADIUS + 2  -- Larger than hover
    elseif is_hovered then
      radius = POINT_HOVER_RADIUS
    else
      radius = POINT_RADIUS
    end

    -- Determine fill color
    local fill_color
    if is_selected then
      fill_color = curve.color --0xFFFFFFFF  -- White for selected (highly visible)
    elseif is_hovered then
      fill_color = COLORS.point_hovered
    else
      fill_color = curve.color
    end

    -- Draw filled circle with outline
    ImGui.DrawList_AddCircleFilled(draw_list, sx, sy, radius, fill_color, 10)
    ImGui.DrawList_AddCircle(draw_list, sx, sy, radius, COLORS.point_outline, 10, 1)

    -- Draw coordinates tooltip when hovered or selected (show display distance)
    if is_hovered or is_selected then
      local display_x = to_display_distance(point.x)
      local coord_text = string.format("%.1f, %s", display_x, format_value(point.y, curve.unit))
      ImGui.DrawList_AddText(draw_list, sx + 15, sy - 10, COLORS.text, coord_text)
    end
  end
end

-- Draw current distance indicator
local function draw_distance_indicator(draw_list)
  local rect = state.graph_rect
  local curve = state.curves[state.active_curve]

  local sx, _ = to_screen(state.current_distance, curve.y_min, curve)

  -- Draw vertical line
  ImGui.DrawList_AddLine(draw_list, sx, rect.y, sx, rect.y + rect.h, COLORS.distance_line, 2)

  -- Draw evaluation points on each visible curve
  for i, c in ipairs(state.curves) do
    if state.curve_visible[i] then
      local y = state.evaluated_values[i] or curve_evaluate(c, state.current_distance)
      local px, py = to_screen(state.current_distance, y, c)
      local color = c.color
      if not state.curve_enabled[i] then
        color = (c.color & 0xFFFFFF00) | 0x40
      end
      ImGui.DrawList_AddCircleFilled(draw_list, px, py, 5, color, 12)
      ImGui.DrawList_AddCircle(draw_list, px, py, 5, COLORS.point_outline, 12, 1.5)
    end
  end

  -- Draw evaluation points on custom curves
  for _, param in ipairs(state.custom_params) do
    local y = custom_curve_evaluate(param, state.current_distance)
    local px, py = custom_to_screen(state.current_distance, y)
    local color = param.color
    if param.enabled == false then
      color = (param.color & 0xFFFFFF00) | 0x40
    end
    ImGui.DrawList_AddCircleFilled(draw_list, px, py, 5, color, 12)
    ImGui.DrawList_AddCircle(draw_list, px, py, 5, COLORS.point_outline, 12, 1.5)
  end
end

-- Draw a single custom parameter curve
local function draw_custom_curve(draw_list, param)
  if not param or not param.curve or #param.curve < 2 then return end

  local rect = state.graph_rect

  -- Sample curve at regular intervals
  local x_range = DISTANCE_MAX - DISTANCE_MIN
  local step = x_range / CURVE_SAMPLE_COUNT

  -- Build points array for polyline
  local num_points = CURVE_SAMPLE_COUNT + 1
  local points = reaper.new_array(num_points * 2)

  for i = 0, CURVE_SAMPLE_COUNT do
    local x = DISTANCE_MIN + i * step
    local y = custom_curve_evaluate(param, x)
    local sx, sy = custom_to_screen(x, y)
    points[i * 2 + 1] = sx
    points[i * 2 + 2] = sy
  end

  -- Draw polyline (thicker if selected, dimmer if disabled)
  local is_selected = state.selected_custom_id == param.id
  local thickness = is_selected and 2.5 or 1.5
  local color = param.color
  if param.enabled == false then
    -- Make disabled curves semi-transparent (reduce alpha from FF to 40)
    color = (param.color & 0xFFFFFF00) | 0x40
  end
  ImGui.DrawList_AddPolyline(draw_list, points, color, 0, thickness)
end

-- Draw all custom curves
local function draw_custom_curves(draw_list)
  -- Draw non-selected curves first
  for _, param in ipairs(state.custom_params) do
    if param.id ~= state.selected_custom_id then
      draw_custom_curve(draw_list, param)
    end
  end

  -- Draw selected curve on top
  if state.selected_custom_id then
    local selected_param = get_custom_param_by_id(state.selected_custom_id)
    if selected_param then
      draw_custom_curve(draw_list, selected_param)
    end
  end
end

-- Draw control points for selected custom curve
local function draw_custom_control_points(draw_list)
  if not state.selected_custom_id then return end

  local param = get_custom_param_by_id(state.selected_custom_id)
  if not param or not param.curve then return end

  for i, point in ipairs(param.curve) do
    local sx, sy = custom_to_screen(point.x, point.y)

    -- Check if this point is selected or hovered
    -- Custom points are identified as {"custom", param_id, point_idx}
    local is_selected = state.selected_point and
                        state.selected_point[1] == "custom" and
                        state.selected_point[2] == param.id and
                        state.selected_point[3] == i
    local is_hovered = state.hovered_point and
                       state.hovered_point[1] == "custom" and
                       state.hovered_point[2] == param.id and
                       state.hovered_point[3] == i

    -- Selected points are largest, then hovered, then normal
    local radius
    if is_selected then
      radius = POINT_HOVER_RADIUS + 2
    elseif is_hovered then
      radius = POINT_HOVER_RADIUS
    else
      radius = POINT_RADIUS
    end

    -- Determine fill color
    local fill_color
    if is_selected then
      fill_color = param.color
    elseif is_hovered then
      fill_color = COLORS.point_hovered
    else
      fill_color = param.color
    end

    -- Draw filled circle with outline
    ImGui.DrawList_AddCircleFilled(draw_list, sx, sy, radius, fill_color, 10)
    ImGui.DrawList_AddCircle(draw_list, sx, sy, radius, COLORS.point_outline, 10, 1)

    -- Draw coordinates tooltip when hovered or selected
    if is_hovered or is_selected then
      local display_x = to_display_distance(point.x)
      local coord_text = string.format("%.1f, %.2f", display_x, point.y)
      ImGui.DrawList_AddText(draw_list, sx + 15, sy - 10, COLORS.text, coord_text)
    end
  end
end

-- Handle mouse interaction with graph
local function handle_graph_interaction()
  local rect = state.graph_rect
  local curve_idx = state.active_curve
  local curve = state.curves[curve_idx]

  local mouse_x, mouse_y = ImGui.GetMousePos(state.ctx)

  -- Use IsItemHovered to check if mouse is over the invisible button (graph area)
  local in_graph = ImGui.IsItemHovered(state.ctx)

  -- Find hovered point (check both main curves and custom curves)
  state.hovered_point = nil
  if in_graph or state.dragging then
    local min_dist = POINT_HIT_RADIUS

    -- Check main curve points (only when no custom curve is selected)
    if not state.selected_custom_id then
      for i, point in ipairs(curve.points) do
        local sx, sy = to_screen(point.x, point.y, curve)
        local dist = math.sqrt((mouse_x - sx)^2 + (mouse_y - sy)^2)
        if dist < min_dist then
          min_dist = dist
          state.hovered_point = {curve_idx, i}  -- {curve_idx, point_idx}
        end
      end
    end

    -- Check custom curve points (if a custom param is selected)
    if state.selected_custom_id then
      local param = get_custom_param_by_id(state.selected_custom_id)
      if param and param.curve then
        for i, point in ipairs(param.curve) do
          local sx, sy = custom_to_screen(point.x, point.y)
          local dist = math.sqrt((mouse_x - sx)^2 + (mouse_y - sy)^2)
          if dist < min_dist then
            min_dist = dist
            state.hovered_point = {"custom", param.id, i}  -- {"custom", param_id, point_idx}
          end
        end
      end
    end
  end

  -- Handle left-click (use IsItemClicked for the invisible button)
  if ImGui.IsItemClicked(state.ctx, 0) then
    if state.hovered_point then
      -- Select and prepare for potential drag
      state.selected_point = state.hovered_point
      state.dragging = true
      state.drag_active = false  -- Don't move until threshold exceeded
      state.drag_start_mouse = {x = mouse_x, y = mouse_y}

      -- Get the initial point position based on type
      if state.hovered_point[1] == "custom" then
        local param = get_custom_param_by_id(state.hovered_point[2])
        if param and param.curve then
          local point = param.curve[state.hovered_point[3]]
          state.drag_start_point = {x = point.x, y = point.y}
        end
      else
        local point = curve.points[state.hovered_point[2]]
        state.drag_start_point = {x = point.x, y = point.y}
      end
    else
      -- Add new point at click position
      -- Check if a custom curve is selected - if so, add to custom curve
      if state.selected_custom_id then
        local param = get_custom_param_by_id(state.selected_custom_id)
        if param then
          local x, y = custom_from_screen(mouse_x, mouse_y)
          if custom_curve_add_point(param, x, y) then
            -- Find and select the new point
            for i, p in ipairs(param.curve) do
              if math.abs(p.x - x) < 1.0 then
                state.selected_point = {"custom", param.id, i}
                state.dragging = true
                state.drag_active = true
                state.drag_start_mouse = {x = mouse_x, y = mouse_y}
                state.drag_start_point = {x = p.x, y = p.y}
                break
              end
            end
            save_state()
            force_update_jsfx()
          end
        end
      else
        -- Add to main curve
        local x, y = from_screen(mouse_x, mouse_y, curve)
        if curve_add_point(curve, x, y) then
          -- Find and select the new point
          for i, p in ipairs(curve.points) do
            if math.abs(p.x - x) < 1.0 then
              state.selected_point = {curve_idx, i}
              state.dragging = true
              state.drag_active = true
              state.drag_start_mouse = {x = mouse_x, y = mouse_y}
              state.drag_start_point = {x = p.x, y = p.y}
              break
            end
          end
          save_state()
          force_update_jsfx()
        end
      end
    end
  end

  -- Handle right-click (delete point)
  if ImGui.IsItemClicked(state.ctx, 1) and state.hovered_point then
    if state.hovered_point[1] == "custom" then
      -- Delete custom curve point
      local param = get_custom_param_by_id(state.hovered_point[2])
      if param and custom_curve_remove_point(param, state.hovered_point[3]) then
        state.selected_point = nil
        state.hovered_point = nil
        save_state()
        force_update_jsfx()
      end
    else
      -- Delete main curve point
      local ci, pi = state.hovered_point[1], state.hovered_point[2]
      if curve_remove_point(state.curves[ci], pi) then
        state.selected_point = nil
        state.hovered_point = nil
        save_state()
        force_update_jsfx()
      end
    end
  end

  -- Handle dragging (continues even outside graph area)
  if state.dragging then
    if ImGui.IsMouseDown(state.ctx, 0) then
      -- Check if we've exceeded the drag threshold
      if not state.drag_active and state.drag_start_mouse then
        local dx = mouse_x - state.drag_start_mouse.x
        local dy = mouse_y - state.drag_start_mouse.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist >= DRAG_THRESHOLD then
          state.drag_active = true
        end
      end

      -- Only move the point if drag is active (threshold exceeded)
      if state.drag_active and state.selected_point then
        if state.selected_point[1] == "custom" then
          -- Drag custom curve point
          local param = get_custom_param_by_id(state.selected_point[2])
          if param then
            local x, y = custom_from_screen(mouse_x, mouse_y)
            custom_curve_move_point(param, state.selected_point[3], x, y)
            force_update_jsfx()
          end
        else
          -- Drag main curve point
          local x, y = from_screen(mouse_x, mouse_y, curve)
          local ci, pi = state.selected_point[1], state.selected_point[2]
          curve_move_point(state.curves[ci], pi, x, y)
          force_update_jsfx()
        end
      end
    else
      -- Mouse released
      state.dragging = false
      state.drag_active = false
      state.drag_start_mouse = nil
      save_state()
    end
  end
end

-- Draw the graph area
local function draw_graph()
  local avail_w, avail_h = ImGui.GetContentRegionAvail(state.ctx)
  local graph_h = avail_h - CONTROL_PANEL_H

  -- Calculate graph rectangle
  local cx, cy = ImGui.GetCursorScreenPos(state.ctx)
  state.graph_rect = {
    x = cx + GRAPH_MARGIN_L,
    y = cy + GRAPH_MARGIN_T,
    w = avail_w - GRAPH_MARGIN_L - GRAPH_MARGIN_R,
    h = graph_h - GRAPH_MARGIN_T - GRAPH_MARGIN_B
  }

  local rect = state.graph_rect
  local draw_list = ImGui.GetWindowDrawList(state.ctx)

  -- Draw graph background
  ImGui.DrawList_AddRectFilled(draw_list, rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, COLORS.graph_bg, 4)

  -- Draw grid
  draw_grid(draw_list)

  -- Draw axes and labels
  draw_axes(draw_list)

  -- Draw curves (back to front, active on top)
  for i = 1, 4 do
    if i ~= state.active_curve and state.curve_visible[i] then
      draw_curve(draw_list, i)
    end
  end
  if state.curve_visible[state.active_curve] then
    draw_curve(draw_list, state.active_curve)
  end

  -- Draw custom curves
  draw_custom_curves(draw_list)

  -- Draw control points (only for active curve when no custom curve selected)
  if not state.selected_custom_id then
    draw_control_points(draw_list)
  end

  -- Draw control points for selected custom curve
  draw_custom_control_points(draw_list)

  -- Draw distance indicator
  draw_distance_indicator(draw_list)

  -- Add invisible button over graph area to capture mouse input and prevent window dragging
  -- Extend slightly beyond graph edges to catch interactions near control points on the boundary
  local btn_pad = 15
  ImGui.SetCursorScreenPos(state.ctx, rect.x - btn_pad, rect.y - btn_pad)
  ImGui.InvisibleButton(state.ctx, "##graph_interaction", rect.w + btn_pad * 2, rect.h + btn_pad * 2,
    ImGui.ButtonFlags_MouseButtonLeft() | ImGui.ButtonFlags_MouseButtonRight())

  -- Handle interaction (must be called after InvisibleButton to get correct hover state)
  handle_graph_interaction()

  -- Reset cursor and advance past graph area
  ImGui.SetCursorScreenPos(state.ctx, cx, cy + graph_h)
end

-- State for custom curves dropdown error message
local custom_curves_error_msg = nil
local custom_curves_error_time = 0

-- Draw toolbar (curve selection, visibility, interpolation)
local function draw_toolbar()
  ImGui.PushStyleColor(state.ctx, ImGui.Col_Button(), 0x40404060)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_ButtonHovered(), 0x60606080)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_ButtonActive(), 0x808080A0)

  -- Curve selection buttons
  for i, curve in ipairs(state.curves) do
    if i > 1 then ImGui.SameLine(state.ctx) end

    -- Only highlight if this is the active curve AND no custom curve is selected
    local is_active = (i == state.active_curve) and not state.selected_custom_id
    local needs_dark_text = is_active and (i == 2 or i == 4)  -- HPF (green) and Spread (yellow) need dark text
    if is_active then
      -- Push all 3 button states to keep consistent color on hover/click
      ImGui.PushStyleColor(state.ctx, ImGui.Col_Button(), curve.color)
      ImGui.PushStyleColor(state.ctx, ImGui.Col_ButtonHovered(), curve.color)
      ImGui.PushStyleColor(state.ctx, ImGui.Col_ButtonActive(), curve.color)
    end
    if needs_dark_text then
      ImGui.PushStyleColor(state.ctx, ImGui.Col_Text(), 0x000000FF)  -- Black text
    end

    local enabled_label = state.curve_enabled[i] and "" or " [D]"
    if ImGui.Button(state.ctx, curve.label .. enabled_label .. "##curve" .. i, 90, 24) then
      state.active_curve = i
      state.selected_custom_id = nil  -- Deselect any custom curve when selecting a main curve
      save_state()
    end

    -- Right-click to toggle enabled (disabled curves don't affect output)
    if ImGui.IsItemClicked(state.ctx, 1) then
      state.curve_enabled[i] = not state.curve_enabled[i]
      state.dirty = true
      save_state()
      force_update_jsfx()
    end

    if needs_dark_text then
      ImGui.PopStyleColor(state.ctx)
    end
    if is_active then
      ImGui.PopStyleColor(state.ctx, 3)  -- Pop all 3 button state colors
    end
  end

  -- Custom Curves dropdown (to the right of Spread)
  ImGui.SameLine(state.ctx, 0, 10)

  local custom_count = #state.custom_params
  local slots_label = custom_count > 0 and string.format(" Custom (%d)", custom_count) or " Custom"

  -- Draw colored dot next to Custom dropdown if a custom curve is selected
  local selected_custom_param = nil
  if state.selected_custom_id then
    for _, param in ipairs(state.custom_params) do
      if param.id == state.selected_custom_id then
        selected_custom_param = param
        break
      end
    end
  end

  -- Capture combo position before drawing
  local combo_x, combo_y = ImGui.GetCursorScreenPos(state.ctx)

  -- Add padding to label if we have a selected custom param (to make room for dot)
  local display_label = selected_custom_param and ("    " .. slots_label) or slots_label

  ImGui.SetNextItemWidth(state.ctx, 100)
  if ImGui.BeginCombo(state.ctx, "##custom_curves", display_label) then
    -- "Add last touched parameter" button
    if ImGui.Selectable(state.ctx, "+ Add last touched param", false) then
      local ok, err = add_custom_param_from_last_touched()
      if not ok then
        custom_curves_error_msg = err
        custom_curves_error_time = reaper.time_precise()
      else
        save_state()
        force_update_jsfx()
      end
    end
    if ImGui.IsItemHovered(state.ctx) then
      ImGui.BeginTooltip(state.ctx)
      ImGui.Text(state.ctx, "Capture the last touched FX parameter")
      ImGui.Text(state.ctx, "and create a custom curve to drive it over distance.")
      ImGui.TextColored(state.ctx, COLORS.text_dim, string.format("Slots available: %d of 8", JSFX_CUSTOM_SLOT_COUNT - custom_count))
      ImGui.EndTooltip(state.ctx)
    end

    -- "Remove selected parameter" button
    local has_selection = state.selected_custom_id ~= nil
    if not has_selection then
      ImGui.BeginDisabled(state.ctx)
    end
    if ImGui.Selectable(state.ctx, "- Remove selected param", false) then
      if state.selected_custom_id then
        remove_custom_param(state.selected_custom_id)
        save_state()
        force_update_jsfx()
      end
    end
    if not has_selection then
      ImGui.EndDisabled(state.ctx)
    end

    -- Separator before parameter list
    if custom_count > 0 then
      ImGui.Separator(state.ctx)
    end

    -- List of custom parameters (ordered by add-time, oldest first)
    for _, param in ipairs(state.custom_params) do
      local is_selected = state.selected_custom_id == param.id
      local label = param.name_short or "Custom"
      if not param.resolved then
        label = label .. " (missing)"
      end
      -- Add [D] suffix if disabled
      if param.enabled == false then
        label = label .. " [D]"
      end

      -- Get cursor position for drawing colored dot
      local cursor_x, cursor_y = ImGui.GetCursorScreenPos(state.ctx)
      local dot_radius = 4
      local dot_offset_x = 6  -- Padding from left edge
      local dot_offset_y = 9  -- Center vertically in row

      -- Use selection indicator and spacing for label
      local select_label = is_selected and ("* " .. label) or ("  " .. label)
      if ImGui.Selectable(state.ctx, "     " .. select_label .. "##" .. param.id, is_selected) then
        state.selected_custom_id = param.id
        save_state()
      end

      -- Right-click to toggle enabled (disabled curves don't affect output)
      if ImGui.IsItemClicked(state.ctx, 1) then
        param.enabled = not (param.enabled ~= false)
        state.dirty = true
        save_state()
        force_update_jsfx()
      end

      -- Draw colored dot in front of the parameter name
      local draw_list = ImGui.GetWindowDrawList(state.ctx)
      ImGui.DrawList_AddCircleFilled(draw_list, cursor_x + dot_offset_x, cursor_y + dot_offset_y, dot_radius, param.color)

      -- Tooltip with full info
      if ImGui.IsItemHovered(state.ctx) then
        ImGui.BeginTooltip(state.ctx)
        ImGui.Text(state.ctx, "Parameter: " .. (param.name_full or param.name_short or "Unknown"))
        ImGui.Text(state.ctx, "FX: " .. (param.fx_name or "Unknown"))
        ImGui.Text(state.ctx, "Track: " .. (param.track_name or "Unknown"))
        ImGui.TextColored(state.ctx, COLORS.text_dim, "Slot: Custom " .. param.jsfx_slot)
        if not param.resolved then
          ImGui.TextColored(state.ctx, 0xFF6666FF, "Status: Target FX not found")
        elseif param.enabled == false then
          ImGui.TextColored(state.ctx, 0xFFAA66FF, "Status: Disabled (right-click to enable)")
        else
          ImGui.TextColored(state.ctx, 0x66FF66FF, "Status: Linked (right-click to disable)")
        end
        ImGui.EndTooltip(state.ctx)
      end
    end

    ImGui.EndCombo(state.ctx)
  end

  -- Draw colored dot inside Custom dropdown (left side) if a custom curve is selected
  if selected_custom_param then
    local dot_radius = 5
    local draw_list = ImGui.GetWindowDrawList(state.ctx)
    -- Position dot inside the combo box, left side with some padding
    ImGui.DrawList_AddCircleFilled(draw_list, combo_x + 10, combo_y + 12, dot_radius, selected_custom_param.color)
  end

  -- Show error message briefly
  if custom_curves_error_msg and (reaper.time_precise() - custom_curves_error_time) < 3.0 then
    ImGui.SameLine(state.ctx)
    ImGui.TextColored(state.ctx, 0xFF6666FF, custom_curves_error_msg)
  end

  ImGui.SameLine(state.ctx, 0, 20)

  -- Interpolation mode selector
  ImGui.Text(state.ctx, "Interp:")
  ImGui.SameLine(state.ctx)

  local curve = state.curves[state.active_curve]
  ImGui.SetNextItemWidth(state.ctx, 80)
  if ImGui.BeginCombo(state.ctx, "##interp", curve.interpolation) then
    if ImGui.Selectable(state.ctx, "linear", curve.interpolation == "linear") then
      curve.interpolation = "linear"
      state.dirty = true
      save_state()
    end
    if ImGui.Selectable(state.ctx, "smooth", curve.interpolation == "smooth") then
      curve.interpolation = "smooth"
      state.dirty = true
      save_state()
    end
    ImGui.EndCombo(state.ctx)
  end

  -- Help text
  ImGui.SameLine(state.ctx, 0, 20)
  ImGui.TextColored(state.ctx, COLORS.text_dim, "(Click: add point | Drag: move | Right-click: delete)")

  ImGui.PopStyleColor(state.ctx, 3)

  ImGui.Separator(state.ctx)
end

-- Draw control panel (distance slider, value readouts)
local function draw_control_panel()
  ImGui.Separator(state.ctx)

  local avail_w, _ = ImGui.GetContentRegionAvail(state.ctx)

  -- Distance control section
  ImGui.Text(state.ctx, "DISTANCE CONTROL")
  ImGui.Spacing(state.ctx)

  -- Large distance slider (shows display values, converts to/from internal 0-100)
  local display_dist = to_display_distance(state.current_distance)
  local display_min = to_display_distance(DISTANCE_MIN)
  local display_max = state.display_max_distance

  ImGui.SetNextItemWidth(state.ctx, avail_w - 120)
  local changed, new_display_dist = ImGui.SliderDouble(state.ctx, "##distance",
    display_dist, display_min, display_max, "%.1f")

  if changed then
    state.current_distance = from_display_distance(new_display_dist)
    force_update_jsfx()  -- Update JSFX immediately while dragging
  end

  -- Save state only when slider is released (not during drag)
  if ImGui.IsItemDeactivatedAfterEdit(state.ctx) then
    save_state()
  end

  ImGui.SameLine(state.ctx)

  -- Numeric input (shows display values)
  ImGui.SetNextItemWidth(state.ctx, 105)
  local input_changed, input_val = ImGui.InputDouble(state.ctx, "##dist_input",
    display_dist, 1.0, 10.0, "%.1f")

  if input_changed then
    local internal_val = from_display_distance(input_val)
    state.current_distance = clamp(internal_val, DISTANCE_MIN, DISTANCE_MAX)
    state.dirty = true
    save_state()
    force_update_jsfx()
  end

  ImGui.Spacing(state.ctx)
  ImGui.Separator(state.ctx)
  ImGui.Spacing(state.ctx)

  -- Current values display with base offset inputs
  ImGui.Text(state.ctx, "CURRENT VALUES AT DISTANCE")
  ImGui.Spacing(state.ctx)

  -- Layout: 2x2 grid with current value + base input for each parameter
  -- Row 1: Volume | High-Pass
  -- Row 2: Low-Pass | Spread
  local col_width = avail_w / 2 - 10
  local value_width = 110
  local base_input_width = 100

  -- Helper to get base value by curve index
  local function get_base_value(idx)
    if idx == 1 then return state.base.volume_db
    elseif idx == 2 then return state.base.hp_hz
    elseif idx == 3 then return state.base.lp_hz
    elseif idx == 4 then return state.base.spread_pct
    end
    return 0
  end

  -- Helper to set base value by curve index
  local function set_base_value(idx, val)
    if idx == 1 then state.base.volume_db = val
    elseif idx == 2 then state.base.hp_hz = val
    elseif idx == 3 then state.base.lp_hz = val
    elseif idx == 4 then state.base.spread_pct = val
    end
  end

  -- Helper to get step size for base input
  local function get_base_step(idx)
    if idx == 1 then return 0.1, 1.0  -- Volume: 0.1 dB step
    elseif idx == 2 then return 10, 100  -- HP: 10 Hz step (values typically 20-500)
    elseif idx == 3 then return 100, 1000  -- LP: 100 Hz step (values typically 2000-20000)
    elseif idx == 4 then return 1, 10  -- Spread: 1% step
    end
    return 1, 10
  end

  -- Helper to get format string for base input
  local function get_base_format(idx)
    if idx == 1 then return "%.1f"  -- Volume: 1 decimal
    elseif idx == 2 or idx == 3 then return "%.0f"  -- HP/LP: integers
    elseif idx == 4 then return "%.1f"  -- Spread: 1 decimal
    end
    return "%.1f"
  end

  -- Draw order: 1=Volume, 2=HPF, 3=LPF, 4=Spread
  -- Layout: Row1: Volume(1), HPF(2) | Row2: LPF(3), Spread(4)
  local layout = {
    {1, 2},  -- Row 1: Volume, High-Pass
    {3, 4}   -- Row 2: Low-Pass, Spread
  }

  -- Fixed offset for base input within each column (leaves room for longest value text)
  local base_input_offset = 150

  for row_idx, row in ipairs(layout) do
    for col_idx, curve_idx in ipairs(row) do
      local curve = state.curves[curve_idx]

      -- Calculate column start position
      local col_start = (col_idx == 1) and 0 or (col_width + 20)

      -- Move to column start
      if col_idx == 2 then
        ImGui.SameLine(state.ctx, col_start)
      end

      -- Get output value (curve + base, clamped)
      local output_value = state.output_values[curve_idx] or curve_evaluate(curve, state.current_distance)
      local color = state.curve_visible[curve_idx] and curve.color or COLORS.text_dim

      -- Current value display
      ImGui.TextColored(state.ctx, color,
        string.format("%s: %s", curve.label, format_value(output_value, curve.unit)))

      -- Base input at fixed position within column
      ImGui.SameLine(state.ctx, col_start + base_input_offset)

      local base_val = get_base_value(curve_idx)
      local step, step_fast = get_base_step(curve_idx)
      local fmt = get_base_format(curve_idx)

      ImGui.SetNextItemWidth(state.ctx, base_input_width)
      local base_changed, new_base = ImGui.InputDouble(state.ctx, "##base_" .. curve.id, base_val, step, step_fast, fmt)

      if base_changed then
        -- Ensure numeric value (no NaN)
        new_base = tonumber(new_base) or 0
        set_base_value(curve_idx, new_base)
        state.dirty = true
        force_update_jsfx()
      end

      -- Save state when input is deactivated
      if ImGui.IsItemDeactivatedAfterEdit(state.ctx) then
        save_state()
      end
    end

    -- Add spacing between rows
    if row_idx < #layout then
      ImGui.Spacing(state.ctx)
    end
  end

  -- Bottom row: Selected Point X/Y (left) and Max Distance (right)
  ImGui.Spacing(state.ctx)
  ImGui.Separator(state.ctx)
  ImGui.Spacing(state.ctx)

  -- Selected Point X/Y inputs (left side)
  local point_input_width = 100
  ImGui.SameLine(state.ctx)

  if state.selected_point then
    local ci, pi = state.selected_point[1], state.selected_point[2]
    local curve = state.curves[ci]
    local point = curve and curve.points[pi]

    if point then
      -- X input (display distance)
      local display_x = to_display_distance(point.x)
      ImGui.Text(state.ctx, "X:")
      ImGui.SameLine(state.ctx)
      ImGui.SetNextItemWidth(state.ctx, point_input_width)
      local x_changed, new_display_x = ImGui.InputDouble(state.ctx, "##point_x",
        display_x, 1.0, 10.0, "%.1f")

      if x_changed then
        local new_internal_x = from_display_distance(new_display_x)
        curve_move_point(curve, pi, new_internal_x, point.y)
        force_update_jsfx()
      end

      if ImGui.IsItemDeactivatedAfterEdit(state.ctx) then
        save_state()
      end

      -- Y input (curve value 0-100)
      ImGui.SameLine(state.ctx)
      ImGui.Text(state.ctx, "Y:")
      ImGui.SameLine(state.ctx)
      ImGui.SetNextItemWidth(state.ctx, point_input_width)
      local y_changed, new_y = ImGui.InputDouble(state.ctx, "##point_y",
        point.y, 1.0, 10.0, "%.1f")

      if y_changed then
        curve_move_point(curve, pi, point.x, new_y)
        force_update_jsfx()
      end

      if ImGui.IsItemDeactivatedAfterEdit(state.ctx) then
        save_state()
      end
    else
      ImGui.TextDisabled(state.ctx, "X: -  Y: -")
    end
  else
    ImGui.TextDisabled(state.ctx, "X: -  Y: -")
  end

  -- Max Distance input box (right side, same row)
  local max_dist_label_width = 80
  local max_dist_input_width = 100
  ImGui.SameLine(state.ctx, avail_w - max_dist_label_width - max_dist_input_width - 10)

  ImGui.Text(state.ctx, "Max Distance:")
  ImGui.SameLine(state.ctx)
  ImGui.SetNextItemWidth(state.ctx, max_dist_input_width)
  local max_changed, new_max = ImGui.InputDouble(state.ctx, "##max_distance",
    state.display_max_distance, 10.0, 100.0, "%.0f")

  if max_changed then
    -- Clamp to reasonable range (1 to 100000)
    state.display_max_distance = clamp(new_max, 1, 100000)
  end

  if ImGui.IsItemDeactivatedAfterEdit(state.ctx) then
    save_state()
  end
end

-- Main GUI loop
local function main_loop()
  -- Set minimum window size
  ImGui.SetNextWindowSizeConstraints(state.ctx, WINDOW_MIN_W, WINDOW_MIN_H, 4096, 4096)

  -- Window styling - fully opaque (Alpha is the last two hex digits: FF)
  ImGui.PushStyleVar(state.ctx, ImGui.StyleVar_WindowBorderSize(), 1)
  ImGui.PushStyleVar(state.ctx, ImGui.StyleVar_Alpha(), 1.0)

  -- All background colors fully opaque (Converted to 0xRRGGBBAA)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_WindowBg(), 0x1E1E24FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_ChildBg(), 0x1E1E24FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_PopupBg(), 0x1E1E24FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_FrameBg(), 0x2A2A36FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_FrameBgHovered(), 0x3A3A46FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_FrameBgActive(), 0x4A4A56FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_TitleBg(), 0x1A1A24FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_TitleBgActive(), 0x2A2A36FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_TitleBgCollapsed(), 0x1A1A24FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_MenuBarBg(), 0x1E1E24FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_ScrollbarBg(), 0x1E1E24FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_Border(), 0x404050FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_Header(), 0x2A2A36FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_HeaderHovered(), 0x3A3A46FF)
  ImGui.PushStyleColor(state.ctx, ImGui.Col_HeaderActive(), 0x4A4A56FF)

  local visible, open = ImGui.Begin(state.ctx, "AVS_Attenuator Editor", true,
    ImGui.WindowFlags_NoCollapse())

  if visible then
    avs_presets_ui(state.ctx, state)
    draw_toolbar()
    draw_graph()
    draw_control_panel()
    ImGui.End(state.ctx)
  end

  ImGui.PopStyleColor(state.ctx, 15)
  ImGui.PopStyleVar(state.ctx, 2)

  state.window_open = open

  -- Check for distance updates from JSFX (automation)
  check_jsfx_distance()

  -- Update JSFX with rate limiting
  update_jsfx()

  -- Continue loop if window is open
  if state.window_open then
    reaper.defer(main_loop)
  else
    -- Cleanup
    if state.auto_bypass_on_exit then
      bypass_all_jsfx()
    end
    save_state()
    -- End undo block without creating an undo point (-1 flag)
    reaper.Undo_EndBlock2(0, "AVS_Attenuator Editor", -1)
  end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

local function main()
  -- Begin undo block to prevent individual FX parameter changes from creating undo points
  -- The block will be closed with -1 flag on exit to discard without creating an undo point
  reaper.Undo_BeginBlock2(0)

  -- Initialize ImGui
  init_imgui()

  -- Initialize curves
  init_curves()

  -- Load saved state
  load_state()

  -- Auto-unbypass JSFX on script start if auto_bypass_on_exit is enabled
  if state.auto_bypass_on_exit then
    unbypass_all_jsfx()
  end

  -- Initialize gmem
  init_gmem()

  -- Compute output values and send to JSFX
  force_update_jsfx()

  -- Start main loop
  main_loop()
end

-- Entry point
main()
