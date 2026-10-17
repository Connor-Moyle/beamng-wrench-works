-- Wrench Works: graphics. Two optional picture improvements, both off by default and switched live from the Graphics group of the settings:
--   * SMAA Ultra: the game's SMAA runs at its "high" preset. With this on, the edge detection and blending-weight steps of SMAA_PostEffect use our own shaders
--     (shaders/common/postFx/slrrGfx/: the Ultra preset, colour edge detection). The game's shader files and objects are never changed; our ShaderData objects are
--     new and the two effects' `shader` field is pointed at them, and back at what it was when the option goes off. Only while the player's anti-aliasing is SMAA.
--   * Sharpening: AMD FidelityFX Contrast Adaptive Sharpening (MIT licence, header kept in the shader) as a post effect that runs after the anti-aliasing.
-- The pure part (plan) is tested by tools/graphics_test.js; the rest talks to the renderer.

local M = {}

local DIR = '/shaders/common/postFx/slrrGfx/'
local STOCK = { edge = 'SMAA_EdgeDetectionShaderData', weight = 'SMAA_BlendingWeightShaderData' }
local OURS = { edge = 'SLRR_SMAAUltra_EdgeShaderData', weight = 'SLRR_SMAAUltra_WeightShaderData' }
local EFFECT = { edge = 'SMAA_PostEffect', weight = 'SMAA_PostEffect1' }
local CAS = 'SLRR_CAS_PostEffect'

M.DEFAULT_STRENGTH = 0.4

-- What should be on, from the settings and the player's anti-aliasing. opts = { ultra = bool, sharpen = bool, strength = 0..1 }, env = { aa = bool, aaType = 'smaa'|'fxaa'|... }
function M.plan(opts, env)
  opts, env = opts or {}, env or {}
  local smaa = env.aa ~= false and env.aaType == 'smaa'
  local strength = tonumber(opts.strength)
  if not strength then strength = M.DEFAULT_STRENGTH end
  strength = math.max(0, math.min(1, strength))
  local note
  if opts.ultra and not smaa then note = 'SMAA Ultra waits: the anti-aliasing is not SMAA (Options > Graphics)' end
  return { ultra = opts.ultra == true and smaa, sharpen = opts.sharpen == true and strength > 0, strength = strength, note = note }
end

----------------------------------------------------------------------------------------------
-- the renderer

local saved = {}          -- stage -> the shader the effect had before ours
local state = { ultra = false, sharpen = false, strength = M.DEFAULT_STRENGTH, note = nil, error = nil }
local casEffect

local function find(name) return scenetree and scenetree.findObject(name) or nil end

local function makeShaderData(name, vertex, pixel, samplers)
  local sd = find(name)
  if sd then return sd end
  sd = createObject('ShaderData')
  sd.DXVertexShaderFile = DIR .. vertex
  sd.DXPixelShaderFile = DIR .. pixel
  sd.pixVersion = 5.0
  for i, s in ipairs(samplers) do sd:setField('samplerNames', i - 1, s) end
  sd:registerObject(name)
  return sd
end

local function ensureUltra()
  makeShaderData(OURS.edge, 'slrr_smaaUltra_edgeV.hlsl', 'slrr_smaaUltra_edgeP.hlsl', { '$colorTexGamma' })
  makeShaderData(OURS.weight, 'slrr_smaaUltra_weightV.hlsl', 'slrr_smaaUltra_weightP.hlsl', { '$edgesTex', '$areaTex', '$searchTex' })
end

-- the effect has to build its pipeline again with the other shader; off and on again if it was running
local function rebuild(effect)
  if not effect then return end
  local ok = pcall(function() effect:reload() end)
  if not ok then
    pcall(function() effect:disable() effect:enable() end)
  end
end

local function setUltra(on)
  if on == state.ultra then return true end
  local smaa = find('SMAA_PostEffect')
  if not smaa then state.error = 'the SMAA effect is not there (yet)' return false end
  if on then ensureUltra() end
  local running = false
  pcall(function() running = smaa:isEnabled() end)
  for stage, name in pairs(EFFECT) do
    local effect = find(name)
    if effect then
      if on then
        saved[stage] = saved[stage] or effect:getField('shader', 0)
        if saved[stage] == '' or saved[stage] == nil then saved[stage] = STOCK[stage] end
        effect:setField('shader', 0, OURS[stage])
      else
        effect:setField('shader', 0, saved[stage] or STOCK[stage])
        saved[stage] = nil
      end
    end
  end
  for _, name in pairs(EFFECT) do rebuild(find(name)) end
  if running then pcall(function() smaa:enable() end) end
  state.ultra = on
  log('I', 'slrr_graphics', 'SMAA ' .. (on and 'Ultra on' or 'back to the game\'s own preset'))
  return true
end

-- the sharpening effect, made once; its shader constant is set every frame by the callbacks below
local function ensureCas()
  casEffect = find(CAS)
  if casEffect then return casEffect end
  local block = find('SLRR_CAS_StateBlock')
  if not block then
    block = createObject('GFXStateBlockData')
    block:inheritParentFields(find('PFX_DefaultStateBlock'))
    block.samplersDefined = true
    block:setField('samplerStates', 0, 'SamplerClampLinear')
    block:registerObject('SLRR_CAS_StateBlock')
  end
  makeShaderData('SLRR_CAS_ShaderData', 'slrr_casV.hlsl', 'slrr_casP.hlsl', { '$colorTex' })
  casEffect = createObject('PostEffect')
  casEffect.isEnabled = false
  casEffect.allowReflectPass = false
  casEffect:setField('renderTime', 0, 'PFXAfterDiffuse')
  casEffect.renderPriority = 0.5                                  -- the anti-aliasing runs at the default 1: ours after it
  casEffect:setField('shader', 0, 'SLRR_CAS_ShaderData')
  casEffect:setField('stateBlock', 0, 'SLRR_CAS_StateBlock')
  casEffect:setField('texture', 0, '$backBuffer')
  casEffect:setField('target', 0, '$backBuffer')
  casEffect:registerObject(CAS)
  return casEffect
end

-- PostEffects find their callbacks by the object's name + "Callbacks"
local function setCasConsts()
  local e = find(CAS)
  if not e then return end
  local size = e:getRenderTargetSize()
  if size and size.x > 0 and size.y > 0 then
    e:setShaderConst('$casParams', string.format('%f %f %f 0', 1.0 / size.x, 1.0 / size.y, state.strength))
  end
end
rawset(_G, 'SLRR_CAS_PostEffectCallbacks', { preProcess = setCasConsts, onEnabled = function() setCasConsts() return true end })

local function setSharpen(on, strength)
  if on then
    local e = ensureCas()
    state.strength = strength
    local running = false
    pcall(function() running = e:isEnabled() end)
    if not (state.sharpen and running) then e:enable() end       -- (not running although it was on: the object was made again after a level change)
    setCasConsts()
  elseif state.sharpen then
    local e = find(CAS)
    if e then e:disable() end
  end
  if on ~= state.sharpen then log('I', 'slrr_graphics', 'sharpening ' .. (on and string.format('on (%.2f)', strength) or 'off')) end
  state.sharpen = on
  state.strength = strength
end

local function aaEnvironment()
  local get = settings and settings.getValue
  if not get then return {} end
  return { aa = get('GraphicAntialias') ~= false, aaType = tostring(get('GraphicAntialiasType') or 'fxaa'):lower() }
end

-- put the picture as the settings want it; safe to call at any time (a level that is not loaded yet changes nothing)
function M.apply(opts)
  state.opts = opts or state.opts or {}
  state.error = nil
  local ok, err = pcall(function()
    if not (scenetree and createObject) then return end
    local plan = M.plan(state.opts, aaEnvironment())
    state.note = plan.note
    setUltra(plan.ultra)
    setSharpen(plan.sharpen, plan.strength)
  end)
  if not ok then
    state.error = tostring(err)
    log('E', 'slrr_graphics', 'could not apply: ' .. tostring(err))
  end
  return M.status()
end

function M.status()
  return { ultra = state.ultra, sharpen = state.sharpen, strength = state.strength, note = state.note, error = state.error,
           casObject = find(CAS) ~= nil, edgeShader = find(EFFECT.edge) and find(EFFECT.edge):getField('shader', 0) or nil }
end

-- the player may change the anti-aliasing type elsewhere: looked at every two seconds
local timer = 0
function M.tick(dt)
  timer = timer + (dt or 0)
  if timer < 2 or not state.opts then return end
  timer = 0
  local plan = M.plan(state.opts, aaEnvironment())
  if plan.ultra ~= state.ultra or plan.sharpen ~= state.sharpen then M.apply() end
end

-- a level ends: the sharpening object may go with it (made again when needed); the game's SMAA effects stay, with whatever shader they have
function M.onLevelEnd()
  casEffect = nil
end

return M
