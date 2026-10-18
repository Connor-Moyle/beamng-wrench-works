-- Wrench Works: look. An optional light colour grade and vignette on the finished picture, in the game's own Options > Graphics page (a second group, next to
-- the anti-aliasing). Everything is off until picked; "off" is the effect not running, so nothing of the game's is changed. See docs/AA_DESIGN.md section 7.
local M = {}

local DIR = '/shaders/common/postFx/slrrGfx/'
local EFFECT, SHADER, BLOCK = 'SLRR_Look_PostEffect', 'SLRR_Look_ShaderData', 'SLRR_Look_StateBlock'

M.PRESETS = {
  { id = 'off', label = 'Off', note = 'No grade: the picture as the game draws it.', values = {} },
  { id = 'natural', label = 'Natural', note = 'A touch of contrast and warmth, a faint vignette. Hardly noticeable, takes the flatness off.',
    values = { contrast = 0.15, saturation = 0.05, warmth = 0.10, split = 0, vignette = 0.15 } },
  { id = 'cinematic', label = 'Cinematic', note = 'More contrast, slightly muted colours, cool shadows and warm highlights, a clear vignette.',
    values = { contrast = 0.35, saturation = -0.05, warmth = 0.10, split = 0.5, vignette = 0.35 } },
  { id = 'vivid', label = 'Vivid', note = 'Stronger colours and contrast, a light vignette. For bright, sunny drives.',
    values = { contrast = 0.25, saturation = 0.25, warmth = 0, split = 0, vignette = 0.10 } },
  { id = 'custom', label = 'Custom', note = 'Your own mix of the controls below (picked by changing any of them).' },
}

M.KEYS = { preset = 'slrrLookPreset', contrast = 'slrrLookContrast', saturation = 'slrrLookSaturation', warmth = 'slrrLookWarmth', split = 'slrrLookSplit', vignette = 'slrrLookVignette' }
M.DEFAULTS = { preset = 'off', contrast = 0, saturation = 0, warmth = 0, split = 0, vignette = 0 }
local NAMES = { 'preset', 'contrast', 'saturation', 'warmth', 'split', 'vignette' }
local RANGE = { contrast = { 0, 1 }, saturation = { -0.5, 0.5 }, warmth = { -1, 1 }, split = { 0, 1 }, vignette = { 0, 1 } }

local function clamp(v, lo, hi) v = tonumber(v) or 0 if v < lo then return lo elseif v > hi then return hi end return v end

function M.presetValues(id)
  for _, p in ipairs(M.PRESETS) do
    if p.id == id and p.values then
      local out = {}
      for name, v in pairs(M.DEFAULTS) do if name ~= 'preset' then out[name] = p.values[name] or v end end
      return out
    end
  end
end

function M.readOptions(get)
  local o = {}
  for _, name in ipairs(NAMES) do
    local v = get(M.KEYS[name], nil)
    if v == nil then v = M.DEFAULTS[name] end
    o[name] = v
  end
  return o
end

-- the preset the options equal (anything else is custom)
function M.matchPreset(o)
  for _, p in ipairs(M.PRESETS) do
    local values = M.presetValues(p.id)
    if values then
      local same = true
      for name, want in pairs(values) do
        if math.abs((tonumber(o[name]) or 0) - want) > 1e-3 then same = false end
      end
      if same then return p.id end
    end
  end
  return 'custom'
end

-- what the pass is told: neutral values do nothing, and when every one is neutral the effect is not run at all
function M.plan(o)
  o = o or {}
  local p = {}
  for name, r in pairs(RANGE) do p[name] = clamp(o[name], r[1], r[2]) end
  p.active = p.contrast > 0 or p.saturation ~= 0 or p.warmth ~= 0 or p.split > 0 or p.vignette > 0
  return p
end

----------------------------------------------------------------------------------------------
-- the effect

local state = { opts = nil, plan = nil, error = nil }
local timer = 0

local function find(name) return scenetree and scenetree.findObject(name) or nil end

local function isEnabled()
  local e = find(EFFECT)
  local on = false
  if e then pcall(function() on = e:isEnabled() == true end) end
  return on
end

local function consts()
  local e = find(EFFECT)
  local p = state.plan
  if not (e and p) then return end
  local size = e:getRenderTargetSize()
  if not (size and size.x > 0 and size.y > 0) then return end
  e:setShaderConst('$lookA', string.format('%f %f %f %f', p.contrast, 1 + p.saturation, p.warmth, p.split))
  e:setShaderConst('$lookB', string.format('%f %f 0 0', p.vignette, size.x / size.y))
end
rawset(_G, EFFECT .. 'Callbacks', { preProcess = consts, onEnabled = function() consts() return true end })

local function ensure()
  if find(EFFECT) then return end
  local block = find(BLOCK)
  if not block then
    block = createObject('GFXStateBlockData')
    block:inheritParentFields(find('PFX_DefaultStateBlock'))
    block.samplersDefined = true
    block:setField('samplerStates', 0, 'SamplerClampLinear')
    block:registerObject(BLOCK)
  end
  if not find(SHADER) then
    local sd = createObject('ShaderData')
    sd.DXVertexShaderFile = DIR .. 'slrr_lookV.hlsl'
    sd.DXPixelShaderFile = DIR .. 'slrr_lookP.hlsl'
    sd.pixVersion = 5.0
    sd:setField('samplerNames', 0, '$colorTex')
    sd:registerObject(SHADER)
  end
  local e = createObject('PostEffect')
  e.isEnabled = false
  e.allowReflectPass = false
  e:setField('renderTime', 0, 'PFXAfterDiffuse')
  e.renderPriority = 0.3                      -- after the anti-aliasing (1), the smoothing (0.8) and the sharpeners (0.5)
  e:setField('shader', 0, SHADER)
  e:setField('stateBlock', 0, BLOCK)
  e:setField('texture', 0, '$backBuffer')
  e:setField('target', 0, '$backBuffer')
  e:registerObject(EFFECT)
end

-- put the picture as the options want it; safe to call at any time
function M.apply(opts)
  state.opts = opts or state.opts or {}
  local before = state.error
  state.error = nil
  local ok, err = pcall(function()
    if not (scenetree and createObject) then return end
    local plan = M.plan(state.opts)
    state.plan = plan
    if not plan.active then
      if isEnabled() then find(EFFECT):disable() log('I', 'slrr_look', 'look off') end
      return
    end
    ensure()
    local e = find(EFFECT)
    if not isEnabled() then e:enable() log('I', 'slrr_look', 'look on') end
    consts()
  end)
  if not ok then
    state.error = tostring(err)
    if state.error ~= before then log('E', 'slrr_look', 'could not apply: ' .. state.error) end      -- (once, not at every tick)
  end
  return M.status()
end

function M.status()
  return { on = isEnabled(), plan = state.plan, error = state.error }
end

-- the effect may be gone after a level change: look again every two seconds
function M.tick(dt)
  timer = timer + (dt or 0)
  if timer < 2 or not state.opts then return end
  timer = 0
  M.apply()
end

----------------------------------------------------------------------------------------------
-- the settings (the Mods menu page is slrr/gfxMenu)

function M.ensureDefaults()
  if not (settings and settings.getValue and settings.setValue) then return end
  for _, name in ipairs(NAMES) do
    if settings.getValue(M.KEYS[name]) == nil then settings.setValue(M.KEYS[name], M.DEFAULTS[name]) end
  end
end

local lastPreset
-- the game says some setting changed: a new preset picks its values; any other change of ours makes the preset Custom (or the one it now equals)
function M.onSettingsChanged()
  if not (settings and settings.getValue) then return end
  local o = M.readOptions(settings.getValue)
  if o.preset ~= lastPreset then
    lastPreset = o.preset
    local values = M.presetValues(o.preset)
    if values then
      for name, want in pairs(values) do
        if math.abs((tonumber(o[name]) or 0) - want) > 1e-6 then settings.setValue(M.KEYS[name], want) o[name] = want end
      end
    end
  else
    local match = M.matchPreset(o)
    if match ~= o.preset then lastPreset = match settings.setValue(M.KEYS.preset, match) o.preset = match end
  end
  return M.apply(o)
end

function M.onLevelEnd() end

return M
