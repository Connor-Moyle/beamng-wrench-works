-- Wrench Works: cinematic camera. Motion blur, depth of field (the game's own effects, set from simple options and put back exactly) and letterbox bars (one
-- more pass of ours), in the game's Options > Graphics page. Off until picked. Never touches the game's effects while a photo-mode session is open (it saves and
-- restores them itself). See docs/AA_DESIGN.md section 8.
local M = {}

local DIR = '/shaders/common/postFx/slrrGfx/'
local EFFECT, SHADER, BLOCK = 'SLRR_Cam_PostEffect', 'SLRR_Cam_ShaderData', 'SLRR_Cam_StateBlock'

M.LETTERBOX = {
  { id = 'off', label = 'Off', note = 'No bars.' },
  { id = '2.39', label = '2.39:1', note = 'Wide cinema bars.' },
  { id = '2.0', label = '2:1', note = 'Lighter bars.' },
  { id = '1.85', label = '1.85:1', note = 'Slim bars.' },
}

M.PRESETS = {
  { id = 'off', label = 'Off', note = 'The game\'s own camera effects, as set elsewhere.', values = {} },
  { id = 'subtle', label = 'Subtle', note = 'A little motion blur and a soft background. No bars.', values = { blur = 0.5, dof = 0.2 } },
  { id = 'film', label = 'Film', note = 'Motion blur, a clear soft background and 2.39:1 bars.', values = { blur = 1.0, dof = 0.5, letterbox = '2.39' } },
  { id = 'dramatic', label = 'Dramatic', note = 'Strong motion blur, a very soft background, 2:1 bars.', values = { blur = 1.6, dof = 0.9, letterbox = '2.0' } },
  { id = 'custom', label = 'Custom', note = 'Your own mix of the controls below (picked by changing any of them).' },
}

M.KEYS = { preset = 'slrrCamPreset', blur = 'slrrCamBlur', dof = 'slrrCamDof', letterbox = 'slrrCamLetterbox' }
M.DEFAULTS = { preset = 'off', blur = 0, dof = 0, letterbox = 'off' }
local NAMES = { 'preset', 'blur', 'dof', 'letterbox' }
local RANGE = { blur = { 0, 2 }, dof = { 0, 1 } }
-- the game's depth-of-field values we set (put back as they were)
local DOF_KEYS = { '$DOFPostFx::Enable', '$DOFPostFx::EnableAutoFocus', '$DOFPostFx::BlurMax' }

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

function M.matchPreset(o)
  for _, p in ipairs(M.PRESETS) do
    local values = M.presetValues(p.id)
    if values then
      local same = true
      for name, want in pairs(values) do
        if type(want) == 'number' then
          if math.abs((tonumber(o[name]) or 0) - want) > 1e-3 then same = false end
        elseif o[name] ~= want then same = false end
      end
      if same then return p.id end
    end
  end
  return 'custom'
end

-- the height of each bar (top and bottom) as a fraction of the screen height, to show a picture of `ratio` on a screen of `aspect` (width / height). Letterbox
-- only: a ratio no wider than the screen gets no bars (pillarbox would just shrink the picture).
function M.barHeight(ratio, aspect)
  ratio, aspect = tonumber(ratio), tonumber(aspect)
  if not (ratio and aspect and aspect > 0 and ratio > aspect) then return 0 end
  return (1 - aspect / ratio) / 2
end

function M.plan(o)
  o = o or {}
  local p = { ratio = tonumber(o.letterbox) or 0 }
  for name, r in pairs(RANGE) do p[name] = clamp(o[name], r[1], r[2]) end
  p.active = p.blur > 0 or p.dof > 0 or p.ratio > 0
  return p
end

----------------------------------------------------------------------------------------------
-- the effects

local state = { opts = nil, plan = nil, error = nil, saved = nil }
local timer = 0

local function find(name) return scenetree and scenetree.findObject(name) or nil end

local function isEnabled(name)
  local e = find(name)
  local on = false
  if e then pcall(function() on = e:isEnabled() == true end) end
  return on
end

-- a photo-mode session is open: it saves and restores the game's effects itself, so we keep out of its way
local function photoModeOpen()
  local ok, open = pcall(function() return ui_photomode_shared and ui_photomode_shared.S and ui_photomode_shared.S.sessionActive == true end)
  return ok and open
end

local function updateDof()
  local ok, dof = pcall(require, 'client/postFx/dof')
  if ok and dof and dof.updateDOFSettings then dof.updateDOFSettings() end
end

-- the game's values as they are now, kept once so that off puts them back exactly
local function save()
  if state.saved then return end
  local s = { dof = {} }
  local mb = find('PostFxMotionBlur')
  if mb then s.blur = { strength = mb.strength, on = isEnabled('PostFxMotionBlur') } end
  for _, key in ipairs(DOF_KEYS) do s.dof[key] = { VariableRegistry.get(key) } end
  s.dofOn = isEnabled('DOFPostEffect')
  state.saved = s
end

local function restore()
  local s = state.saved
  if not s then return end
  state.saved = nil
  local mb = find('PostFxMotionBlur')
  if mb and s.blur then
    mb.strength = s.blur.strength
    if s.blur.on then mb:enable() else mb:disable() end
  end
  for _, key in ipairs(DOF_KEYS) do VariableRegistry.set(key, s.dof[key][1]) end
  updateDof()
  local d = find('DOFPostEffect')
  if d then if s.dofOn then d:enable() else d:disable() end end
  log('I', 'slrr_camera', 'the game\'s blur and depth of field put back')
end

local function consts()
  local e = find(EFFECT)
  local p = state.plan
  if not (e and p) then return end
  local size = e:getRenderTargetSize()
  if not (size and size.x > 0 and size.y > 0) then return end
  e:setShaderConst('$camA', string.format('%f %f 0 0', M.barHeight(p.ratio, size.x / size.y), 1 / size.y))
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
    sd.DXVertexShaderFile = DIR .. 'slrr_camV.hlsl'
    sd.DXPixelShaderFile = DIR .. 'slrr_camP.hlsl'
    sd.pixVersion = 5.0
    sd:setField('samplerNames', 0, '$colorTex')
    sd:registerObject(SHADER)
  end
  local e = createObject('PostEffect')
  e.isEnabled = false
  e.allowReflectPass = false
  e:setField('renderTime', 0, 'PFXAfterDiffuse')
  e.renderPriority = 0.25                     -- after the grade (0.3)
  e:setField('shader', 0, SHADER)
  e:setField('stateBlock', 0, BLOCK)
  e:setField('texture', 0, '$backBuffer')
  e:setField('target', 0, '$backBuffer')
  e:registerObject(EFFECT)
end

local function applyLetterbox(plan)
  if plan.ratio <= 0 then
    if isEnabled(EFFECT) then find(EFFECT):disable() log('I', 'slrr_camera', 'letterbox off') end
    return
  end
  ensure()
  local e = find(EFFECT)
  if not isEnabled(EFFECT) then e:enable() log('I', 'slrr_camera', 'letterbox on') end
  consts()
end

local function applyGame(plan)
  if photoModeOpen() then restore() return end            -- (photo mode has its own copy to put back: leave it the game's true state)
  if not (plan.blur > 0 or plan.dof > 0) then restore() return end
  save()
  local mb = find('PostFxMotionBlur')
  if plan.blur > 0 and mb then
    mb.strength = plan.blur
    if not isEnabled('PostFxMotionBlur') then mb:enable() end
  elseif mb and state.saved.blur then
    mb.strength = state.saved.blur.strength
    if state.saved.blur.on then mb:enable() else mb:disable() end
  end
  if plan.dof > 0 then
    VariableRegistry.set('$DOFPostFx::Enable', true)
    VariableRegistry.set('$DOFPostFx::EnableAutoFocus', true)       -- (follows the camera's target: the car)
    VariableRegistry.set('$DOFPostFx::BlurMax', plan.dof)
    updateDof()
  else
    for _, key in ipairs(DOF_KEYS) do VariableRegistry.set(key, state.saved.dof[key][1]) end
    updateDof()
  end
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
    applyGame(plan)
    applyLetterbox(plan)
  end)
  if not ok then
    state.error = tostring(err)
    if state.error ~= before then log('E', 'slrr_camera', 'could not apply: ' .. state.error) end      -- (once, not at every tick)
  end
  return M.status()
end

function M.status()
  return { on = isEnabled(EFFECT), plan = state.plan, error = state.error, holding = state.saved ~= nil }
end

-- every two seconds: the effects may be gone after a level change, and photo mode may have opened or closed
function M.tick(dt)
  timer = timer + (dt or 0)
  if timer < 2 or not state.opts then return end
  timer = 0
  M.apply()
end

-- the mod is unloaded: everything back
function M.unload()
  state.opts = {}
  pcall(restore)
  return M.apply({})
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
function M.onSettingsChanged()
  if not (settings and settings.getValue) then return end
  local o = M.readOptions(settings.getValue)
  if o.preset ~= lastPreset then
    lastPreset = o.preset
    local values = M.presetValues(o.preset)
    if values then
      for name, want in pairs(values) do
        local have = o[name]
        local differs = type(want) == 'number' and math.abs((tonumber(have) or 0) - want) > 1e-6 or type(want) ~= 'number' and have ~= want
        if differs then settings.setValue(M.KEYS[name], want) o[name] = want end
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
