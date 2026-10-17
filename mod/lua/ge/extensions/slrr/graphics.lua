-- Wrench Works: graphics. The anti-aliasing package, all live from the Graphics group of the settings, all off ("Game's own") by default:
--   * AA mode: Off / FXAA / FXAA HQ / SMAA High / SMAA Ultra / SMAA Ultra + Temporal smoothing. FXAA HQ, SMAA Ultra and the depth predication use our own shader
--     copies (shaders/common/postFx/slrrGfx/); the game's shader files and objects are never changed: our ShaderData objects are new and the game's effects get
--     their `shader` field pointed at them, and back at the game's own when the option goes away. "Game's own" puts the game's FXAA/SMAA on or off the way
--     Options > Graphics says (the game's own code is never bypassed, only its effects are switched).
--   * Temporal smoothing: two post effects of ours. One blends the picture with last frame's, found through the game's #VelocityBuffer and clamped to the colours
--     around the pixel; the other keeps the result for the next frame in a render target of ours. The engine has no camera jitter, so this calms shimmer; it adds no detail.
--   * Sharpener (runs after the anti-aliasing): AMD CAS, AMD FSR 1 RCAS, NVIDIA NIS sharpen (MIT licences, headers kept in the shaders).
-- The pure part (plan, the sharpener constants, the notes) is tested by tools/graphics_test.js; the rest talks to the renderer.

local M = {}

local DIR = '/shaders/common/postFx/slrrGfx/'

local function clamp01(x) return math.max(0, math.min(1, x)) end

----------------------------------------------------------------------------------------------
-- what the player can pick, with the notes shown under the choice (id, label, note)

M.MODES = {
  { id = 'game', label = 'Game\'s own', plan = {},
    note = 'Leaves the anti-aliasing exactly as Options > Graphics has it. Nothing here changes it.' },
  { id = 'off', label = 'Off', plan = { base = 'off' },
    note = 'No anti-aliasing: sharpest and fastest, but every edge is a staircase and thin lines shimmer. For screenshots of the raw image or a slow PC.' },
  { id = 'fxaa', label = 'FXAA', plan = { base = 'fxaa' },
    note = 'NVIDIA FXAA as the game ships it (top quality preset). Very cheap; blurs the whole picture a little. Good on shimmer and thin wires, weaker than SMAA on stair-steps.' },
  { id = 'fxaaHQ', label = 'FXAA HQ', plan = { base = 'fxaa', hq = true },
    note = 'NVIDIA FXAA 3.11 with sub-pixel removal at its maximum (1.00; the game uses 0.90). The smoothest and softest of the cheap options: for foliage, fences and wires. Pair it with a sharpener.' },
  { id = 'smaa', label = 'SMAA High', plan = { base = 'smaa' },
    note = 'The game\'s SMAA at its High preset: clean edges with little blur, cheap. The best of the game\'s own choices.' },
  { id = 'smaaUltra', label = 'SMAA Ultra', plan = { base = 'smaa', ultra = true },
    note = 'SMAA with the Ultra preset: a longer edge search and colour edge detection, with depth predication (below) to keep texture detail out of it. Catches the faint edges High misses; a little more frame time.' },
  { id = 'smaaUltraTemporal', label = 'SMAA Ultra + Temporal smoothing', plan = { base = 'smaa', ultra = true, temporal = true },
    note = 'SMAA Ultra, then a blend with the previous frame (found with the game\'s motion vectors, clamped so nothing ghosts). Calms shimmer, crawling edges and flicker while you drive. It cannot add detail (the engine has no camera jitter, so this is not TAA) and can soften the picture: pair it with a sharpener. Needs the game\'s velocity buffer.' },
}

M.SHARPENERS = {
  { id = 'off', label = 'Off', note = 'No sharpening.' },
  { id = 'cas', label = 'AMD CAS', note = 'AMD FidelityFX Contrast Adaptive Sharpening: sharpens soft areas more than edges that are already crisp, so few halos. One cheap pass. The safe choice.' },
  { id = 'rcas', label = 'AMD FSR RCAS', note = 'The sharpening pass of AMD FSR 1: crisper than CAS, with a noise guard. Cheap. Good after FXAA HQ or Temporal smoothing.' },
  { id = 'nis', label = 'NVIDIA NIS', note = 'The sharpener of NVIDIA Image Scaling: edge-directed (sharpens along edges, not across them) with the least ringing; a little more work (25 reads per pixel). A good match for SMAA Ultra.' },
}

M.PRESETS = {
  { id = 'custom', label = 'Custom', note = 'Your own mix of the settings below.' },
  { id = 'balanced', label = 'Balanced', values = { mode = 'smaaUltra', predication = true, edgeAA = false, sharpener = 'cas', strength = 0.4 },
    note = 'SMAA Ultra with depth predication and gentle AMD CAS sharpening. Clean edges, cheap.' },
  { id = 'smooth', label = 'Smooth', values = { mode = 'smaaUltraTemporal', predication = true, temporal = 0.7, edgeAA = false, spec = 0.5, sharpener = 'cas', strength = 0.6 },
    note = 'SMAA Ultra plus Temporal smoothing and firmer CAS: the calmest picture while driving.' },
  { id = 'max', label = 'Maximum', values = { mode = 'smaaUltraTemporal', predication = true, temporal = 0.85, edgeAA = false, spec = 0.7, sharpener = 'nis', strength = 0.5 },
    note = 'The strongest smoothing and NVIDIA NIS sharpening. For real supersampling add NVIDIA DSR / AMD VSR in the driver and pick the bigger resolution in the game.' },
}

-- things people ask for that a mod cannot do (shown as a list in the settings; the reasons are what the game's files show, see docs/AA_DESIGN.md)
M.UNAVAILABLE = {
  { name = 'NVIDIA DLSS, DLAA and Frame Generation', why = 'need NVIDIA\'s SDK inside the engine, a jittered camera and motion vectors; BeamNG has no hook for them.' },
  { name = 'AMD FSR 2, 3, 4 and Frame Generation', why = 'temporal upscalers: they need a jittered camera that a mod cannot add. FSR 1\'s sharpener is offered as RCAS.' },
  { name = 'FSR 1 and NIS upscaling', why = 'the game has no render-scale setting to upscale from. Their sharpeners are offered.' },
  { name = 'TAA / TSR', why = 'same: no camera jitter. Temporal smoothing is the closest a mod can get.' },
  { name = 'MSAA', why = 'not in the game\'s deferred renderer.' },
  { name = 'Real supersampling', why = 'no render scale in the game. Use NVIDIA DSR / AMD VSR in the driver and choose the bigger resolution in the game.' },
}

local function byId(list, id)
  for _, v in ipairs(list) do if v.id == id then return v end end
end

-- the settings a preset picks (nil for Custom or an unknown one)
function M.presetValues(id)
  local p = byId(M.PRESETS, id)
  return p and p.values or nil
end

-- the notes in one text, for the line under the setting
function M.unavailableText()
  local out = {}
  for _, u in ipairs(M.UNAVAILABLE) do out[#out + 1] = u.name .. ': ' .. u.why end
  return 'Not available in BeamNG mods: ' .. table.concat(out, ' ')
end

----------------------------------------------------------------------------------------------
-- the pure part

M.DEFAULT_STRENGTH = 0.4
M.DEFAULT_TEMPORAL = 0.7

-- What should be on, from the settings. opts = { mode, predication = bool, temporal = 0..1, sharpener, strength = 0..1 }
function M.plan(opts)
  opts = opts or {}
  local mode = byId(M.MODES, opts.mode) or M.MODES[1]
  local strength = tonumber(opts.strength)
  if not strength then strength = M.DEFAULT_STRENGTH end
  strength = clamp01(strength)
  local sharpener = opts.sharpener
  if not byId(M.SHARPENERS, sharpener) then sharpener = 'off' end
  if strength <= 0 then sharpener = 'off' end
  local amount = tonumber(opts.temporal)
  if not amount then amount = M.DEFAULT_TEMPORAL end
  amount = clamp01(amount)
  local p = mode.plan
  return {
    mode = mode.id, base = p.base, hq = p.hq == true, ultra = p.ultra == true,
    predication = p.ultra == true and opts.predication ~= false,
    edgeAA = opts.edgeAA == true, spec = clamp01(tonumber(opts.spec) or 0),
    temporal = p.temporal == true, temporalWeight = 0.6 + 0.35 * amount,      -- weight of last frame's picture: 0.60 .. 0.95
    sharpener = sharpener, strength = strength,
  }
end

-- FSR RCAS: the lobe scale from the strength (AMD's "sharpness" is in stops, 0 = sharpest, 2 = none)
function M.rcasLobe(strength)
  return 2 ^ (-2 * (1 - clamp01(strength)))
end

-- NVIDIA's NVSharpenUpdateConfig (NIS_Config.h), SDR path, for a sharpness 0..1
function M.nisConfig(strength)
  local slider = clamp01(strength) - 0.5
  local maxScale = slider >= 0 and 1.25 or 1.75
  local minScale = slider >= 0 and 1.25 or 1.0
  local limitScale = slider >= 0 and 1.25 or 1.0
  local startY, endY = 0.45, 0.9
  local strMin = math.max(0, 0.4 + slider * minScale * 1.2)
  local strMax = 1.6 + slider * maxScale * 1.8
  local limMin = math.max(0.1, 0.14 + slider * limitScale * 0.32)
  local limMax = 0.5 + slider * limitScale * 0.6
  return { startY = startY, scaleY = 1 / (endY - startY), strMin = strMin, strScale = strMax - strMin,
           limMin = limMin, limScale = limMax - limMin, ratioNorm = 1 / (10 - 2) }
end

----------------------------------------------------------------------------------------------
-- the renderer

local STOCK = { SMAA_PostEffect = 'SMAA_EdgeDetectionShaderData', SMAA_PostEffect1 = 'SMAA_BlendingWeightShaderData', FXAA_PostEffect = 'FXAA_ShaderData' }
local OURS = {
  edge = 'SLRR_SMAAUltra_EdgeShaderData', edgePred = 'SLRR_SMAAUltra_EdgePredShaderData', weight = 'SLRR_SMAAUltra_WeightShaderData',
  hq = 'SLRR_FXAAHQ_ShaderData',
}
local SHARP = {
  cas = { effect = 'SLRR_CAS_PostEffect', shader = 'SLRR_CAS_ShaderData', v = 'slrr_casV.hlsl', p = 'slrr_casP.hlsl' },
  rcas = { effect = 'SLRR_RCAS_PostEffect', shader = 'SLRR_RCAS_ShaderData', v = 'slrr_sharpenV.hlsl', p = 'slrr_rcasP.hlsl' },
  nis = { effect = 'SLRR_NIS_PostEffect', shader = 'SLRR_NIS_ShaderData', v = 'slrr_sharpenV.hlsl', p = 'slrr_nisP.hlsl' },
}
local TSM, TSM_COPY, TSM_HIST = 'SLRR_TSM_PostEffect', 'SLRR_TSMCopy_PostEffect', '#slrrTsmHist'

-- temporal smoothing: how hard thin geometry (foliage, wires) cuts the history, and the width of the colour clamp (try in game: require('slrr/graphics').tune{guard=0.8, gamma=1}; tune{debug=1} shows the specular mask)
local tune = { guard = 0.8, gamma = 1.0, debug = 0 }       -- debug: 0 off; 1 the specular risk mask, 2 normal spread, 3 glossiness, 4 sparkle (grey pictures)
local state = { opts = nil, plan = nil, owned = false, strength = M.DEFAULT_STRENGTH, tsmWeight = 0.85, tsmWait = nil, error = nil }

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

local function ensureOurs(key)
  if key == 'edge' then makeShaderData(OURS.edge, 'slrr_smaaUltra_edgeV.hlsl', 'slrr_smaaUltra_edgeP.hlsl', { '$colorTexGamma' })
  elseif key == 'edgePred' then makeShaderData(OURS.edgePred, 'slrr_smaaUltra_edgeV.hlsl', 'slrr_smaaUltra_edgePredP.hlsl', { '$colorTexGamma', '$prepassDepthTex' })
  elseif key == 'weight' then makeShaderData(OURS.weight, 'slrr_smaaUltra_weightV.hlsl', 'slrr_smaaUltra_weightP.hlsl', { '$edgesTex', '$areaTex', '$searchTex' })
  elseif key == 'hq' then makeShaderData(OURS.hq, 'slrr_fxaaHQV.hlsl', 'slrr_fxaaHQP.hlsl', { '$colorTex' }) end
end

-- the effect has to build its pipeline again with the other shader; off and on again if it was running
local function rebuild(effect)
  if not effect then return end
  local ok = pcall(function() effect:reload() end)
  if not ok then
    pcall(function() effect:disable() effect:enable() end)
  end
end

local function isEnabled(name)
  local e = find(name)
  if not e then return false end
  local on = false
  pcall(function() on = e:isEnabled() == true end)
  return on
end

local function shaderOf(name)
  local e = find(name)
  return e and e:getField('shader', 0) or nil
end

-- point an effect's shader at `want` (nil: the game's own); true when that changed something
local function setShader(effectName, want)
  local effect = find(effectName)
  if not effect then return false end
  local current = effect:getField('shader', 0)
  if current == '' or current == nil then current = STOCK[effectName] end
  local target = want or STOCK[effectName]
  if current == target then return false end
  effect:setField('shader', 0, target)
  return true
end

local function aaEnvironment()
  local get = settings and settings.getValue
  if not get then return { aa = true, aaType = 'fxaa' } end
  local v = get('GraphicAntialias')
  return { aa = v ~= false and tonumber(v) ~= 0, aaType = tostring(get('GraphicAntialiasType') or 'fxaa'):lower() }
end

local function applyShaders(plan)
  local smaa, fxaa = find('SMAA_PostEffect'), find('FXAA_PostEffect')
  local smaaOn, fxaaOn = isEnabled('SMAA_PostEffect'), isEnabled('FXAA_PostEffect')
  local want = { edge = nil, weight = nil, hq = nil }
  if plan.ultra then
    want.edge = plan.predication and 'edgePred' or 'edge'
    want.weight = 'weight'
  end
  if plan.hq then want.hq = 'hq' end
  for _, key in pairs(want) do ensureOurs(key) end
  local smaaChanged = setShader('SMAA_PostEffect', want.edge and OURS[want.edge] or nil)
  smaaChanged = setShader('SMAA_PostEffect1', want.weight and OURS[want.weight] or nil) or smaaChanged
  if smaa then      -- the depth the predicated edge shader reads
    local tex = (want.edge == 'edgePred') and '#prepass[Depth]' or ''
    local now = tostring(smaa:getField('texture', 1) or '')
    if now ~= tex then smaa:setField('texture', 1, tex) smaaChanged = true end
  end
  local fxaaChanged = setShader('FXAA_PostEffect', want.hq and OURS.hq or nil)
  if smaaChanged then
    rebuild(find('SMAA_PostEffect')) rebuild(find('SMAA_PostEffect1')) rebuild(find('SMAA_PostEffect2'))
    if smaaOn and smaa then pcall(function() smaa:enable() end) end
    log('I', 'slrr_graphics', plan.ultra and ('SMAA Ultra on' .. (plan.predication and ' with depth predication' or '')) or 'SMAA back to the game\'s own preset')
  end
  if fxaaChanged then
    rebuild(fxaa)
    if fxaaOn and fxaa then pcall(function() fxaa:enable() end) end
    log('I', 'slrr_graphics', plan.hq and 'FXAA HQ on' or 'FXAA back to the game\'s own settings')
  end
end

-- which of the game's own effects runs; nil base = the game's say-so (Options > Graphics), put back once if we had taken over
local function applyBase(plan)
  local wantSmaa, wantFxaa
  if plan.base then
    state.owned = true
    wantSmaa, wantFxaa = plan.base == 'smaa', plan.base == 'fxaa'
  elseif state.owned then
    local env = aaEnvironment()
    wantSmaa, wantFxaa = env.aa and env.aaType == 'smaa', env.aa and env.aaType ~= 'smaa'
    state.owned = false
  else
    return
  end
  local smaa, fxaa = find('SMAA_PostEffect'), find('FXAA_PostEffect')
  if not (smaa and fxaa) then return end
  -- off before on: switching one on switches the other off by the game's own callbacks anyway
  if not wantSmaa and isEnabled('SMAA_PostEffect') then smaa:disable() end
  if not wantFxaa and isEnabled('FXAA_PostEffect') then fxaa:disable() end
  if wantSmaa and not isEnabled('SMAA_PostEffect') then smaa:enable() end
  if wantFxaa and not isEnabled('FXAA_PostEffect') then fxaa:enable() end
end

local function ensureStateBlock()
  local block = find('SLRR_CAS_StateBlock')
  if not block then
    block = createObject('GFXStateBlockData')
    block:inheritParentFields(find('PFX_DefaultStateBlock'))
    block.samplersDefined = true
    block:setField('samplerStates', 0, 'SamplerClampLinear')
    block:registerObject('SLRR_CAS_StateBlock')
  end
end

-- a sharpening effect, made once; its shader constants are set every frame by the callbacks below
local function ensureSharpener(id)
  local def = SHARP[id]
  local effect = find(def.effect)
  if effect then return effect end
  ensureStateBlock()
  makeShaderData(def.shader, def.v, def.p, { '$colorTex' })
  effect = createObject('PostEffect')
  effect.isEnabled = false
  effect.allowReflectPass = false
  effect:setField('renderTime', 0, 'PFXAfterDiffuse')
  effect.renderPriority = 0.5                                  -- the anti-aliasing runs at the default 1 and the smoothing at 0.8: the sharpener after them
  effect:setField('shader', 0, def.shader)
  effect:setField('stateBlock', 0, 'SLRR_CAS_StateBlock')
  effect:setField('texture', 0, '$backBuffer')
  effect:setField('target', 0, '$backBuffer')
  effect:registerObject(def.effect)
  return effect
end

-- PostEffects find their callbacks by the object's name + "Callbacks"
local function sharpConsts(id)
  local e = find(SHARP[id].effect)
  if not e then return end
  local size = e:getRenderTargetSize()
  if not (size and size.x > 0 and size.y > 0) then return end
  local tx, ty, s = 1.0 / size.x, 1.0 / size.y, state.strength
  if id == 'cas' then
    e:setShaderConst('$casParams', string.format('%f %f %f 0', tx, ty, s))
  elseif id == 'rcas' then
    e:setShaderConst('$sharpParams', string.format('%f %f %f 0', tx, ty, M.rcasLobe(s)))
  else
    local c = M.nisConfig(s)
    e:setShaderConst('$sharpParams', string.format('%f %f 0 0', tx, ty))
    e:setShaderConst('$nisA', string.format('%f %f %f %f', c.startY, c.scaleY, c.strMin, c.strScale))
    e:setShaderConst('$nisB', string.format('%f %f %f 0', c.limMin, c.limScale, c.ratioNorm))
  end
end
for id, def in pairs(SHARP) do
  rawset(_G, def.effect .. 'Callbacks', { preProcess = function() sharpConsts(id) end, onEnabled = function() sharpConsts(id) return true end })
end

local function applySharpener(plan)
  state.strength = plan.strength
  for id, def in pairs(SHARP) do
    if id ~= plan.sharpener and isEnabled(def.effect) then
      find(def.effect):disable()
      log('I', 'slrr_graphics', 'sharpening ' .. id .. ' off')
    end
  end
  if plan.sharpener == 'off' then return end
  local e = ensureSharpener(plan.sharpener)
  if not isEnabled(SHARP[plan.sharpener].effect) then
    e:enable()
    log('I', 'slrr_graphics', string.format('sharpening %s on (%.2f)', plan.sharpener, plan.strength))
  end
  sharpConsts(plan.sharpener)
end

-- temporal smoothing: the smoothing effect and the one that keeps its result for next frame
local function ensureTsm()
  if find(TSM) and find(TSM_COPY) then return end
  local block = find('SLRR_TSM_StateBlock')
  if not block then
    block = createObject('GFXStateBlockData')
    block:inheritParentFields(find('PFX_DefaultStateBlock'))
    block.samplersDefined = true
    block:setField('samplerStates', 0, 'SamplerClampPoint')
    block:setField('samplerStates', 1, 'SamplerClampLinear')
    block:setField('samplerStates', 2, 'SamplerClampPoint')
    block:setField('samplerStates', 3, 'SamplerClampPoint')
    block:setField('samplerStates', 4, 'SamplerClampPoint')
    block:registerObject('SLRR_TSM_StateBlock')
  end
  makeShaderData('SLRR_TSM_ShaderData', 'slrr_tsmV.hlsl', 'slrr_tsmP.hlsl', { '$curTex', '$histTex', '$velTex', '$depthTex', '$rt0Tex' })
  makeShaderData('SLRR_TSMCopy_ShaderData', 'slrr_tsmV.hlsl', 'slrr_tsmCopyP.hlsl', { '$curTex', '$depthTex' })
  if not find(TSM) then
    local e = createObject('PostEffect')
    e.isEnabled = false
    e.allowReflectPass = false
    e:setField('renderTime', 0, 'PFXAfterDiffuse')
    e.renderPriority = 0.8
    e:setField('shader', 0, 'SLRR_TSM_ShaderData')
    e:setField('stateBlock', 0, 'SLRR_TSM_StateBlock')
    e:setField('texture', 0, '$backBuffer')
    e:setField('texture', 1, TSM_HIST)
    e:setField('texture', 2, '#VelocityBuffer')
    e:setField('texture', 3, '#prepass[Depth]')
    e:setField('texture', 4, '#prepass[RT0]')
    e:setField('target', 0, '$backBuffer')
    e:registerObject(TSM)
  end
  if not find(TSM_COPY) then
    local e = createObject('PostEffect')
    e.isEnabled = false
    e.allowReflectPass = false
    e:setField('renderTime', 0, 'PFXAfterDiffuse')
    e.renderPriority = 0.7
    e:setField('shader', 0, 'SLRR_TSMCopy_ShaderData')
    e:setField('stateBlock', 0, 'SLRR_TSM_StateBlock')
    e:setField('texture', 0, '$backBuffer')
    e:setField('texture', 1, '#prepass[Depth]')
    e:setField('target', 0, TSM_HIST)
    e:setField('targetFormat', 0, 'GFXFormatR16G16B16A16F')
    e:registerObject(TSM_COPY)
  end
end

local function tsmConsts()
  local e = find(TSM)
  if not e then return end
  local size = e:getRenderTargetSize()
  if not (size and size.x > 0 and size.y > 0) then return end
  e:setShaderConst('$tsmParams', string.format('%f %f %f %f', state.tsmWeight, tune.guard, tune.gamma, state.spec or 0))
  e:setShaderConst('$tsmSize', string.format('%f %f %f 0', size.x, size.y, tune.debug))
end
rawset(_G, TSM .. 'Callbacks', { preProcess = tsmConsts, onEnabled = function() tsmConsts() return true end })

local function applyTemporal(plan)
  state.spec = plan.spec
  -- the smoothing effect also carries the specular shimmer reduction: with the temporal mode off it runs with no history (weight 0)
  local wantTsm = plan.temporal or plan.spec > 0 or tune.debug > 0
  state.tsmWeight = plan.temporal and plan.temporalWeight or 0
  if not wantTsm then
    state.tsmWait = nil
    if isEnabled(TSM) then find(TSM):disable() log('I', 'slrr_graphics', 'temporal smoothing off') end
    if isEnabled(TSM_COPY) then find(TSM_COPY):disable() end
    return
  end
  ensureTsm()
  if plan.temporal then
    if not isEnabled(TSM_COPY) then find(TSM_COPY):enable() end
    if not isEnabled(TSM) and not state.tsmWait then
      state.tsmWait = 3          -- a few frames for the history to fill before the smoothing reads it
    end
  else
    state.tsmWait = nil
    if isEnabled(TSM_COPY) then find(TSM_COPY):disable() end
    if not isEnabled(TSM) then find(TSM):enable() log('I', 'slrr_graphics', 'specular shimmer reduction on (no history)') end
  end
  tsmConsts()
end

-- the game's own edge smoothing (depth and normal edges, GPU Gems 3): two effects the game makes but leaves off; put back as found
local EDGE = { 'EdgeDetectPostEffect', 'EdgeAAPostEffect' }
local function applyEdgeAA(plan)
  if plan.edgeAA then
    if not state.edgeSaved then
      state.edgeSaved = {}
      for _, name in ipairs(EDGE) do state.edgeSaved[name] = isEnabled(name) end
    end
    for _, name in ipairs(EDGE) do
      local e = find(name)
      if e and not isEnabled(name) then e:enable() end
    end
  elseif state.edgeSaved then
    for _, name in ipairs(EDGE) do
      local e = find(name)
      if e and isEnabled(name) ~= state.edgeSaved[name] then
        if state.edgeSaved[name] then e:enable() else e:disable() end
      end
    end
    state.edgeSaved = nil
  end
end

-- for trying values in game: M.tune({ guard = 0..1, gamma = 0.5..2 }) returns what is set
function M.tune(t)
  for k, v in pairs(t or {}) do if tune[k] ~= nil and tonumber(v) then tune[k] = tonumber(v) end end
  if state.opts then M.apply() end
  tsmConsts()
  return tune
end

-- for finding out which input stops the smoothing pass from drawing: M.probe(slot, '#prepass[Depth]') rebinds one of its textures (0 picture, 1 history, 2 velocity, 3 depth, 4 normals); M.probe() lists what is bound
function M.probe(slot, name)
  local e = find(TSM)
  if not e then return 'no pass' end
  if slot then e:setField('texture', slot, name) end
  local out = {}
  for i = 0, 4 do out[#out + 1] = i .. '=' .. tostring(e:getField('texture', i)) end
  return table.concat(out, ' ')
end

-- the same for any field of any of our effects, then off and on again so it builds afresh: M.probeSet('SLRR_TSM_PostEffect', 'stateBlock', 0, 'SLRR_CAS_StateBlock')
function M.probeSet(effect, field, idx, value)
  local e = find(effect)
  if not e then return 'no ' .. tostring(effect) end
  e:setField(field, idx, value)
  pcall(function() e:disable() e:enable() end)
  return tostring(e:getField(field, idx))
end

-- put the picture as the settings want it; safe to call at any time (a level that is not loaded yet changes nothing)
function M.apply(opts)
  state.opts = opts or state.opts or {}
  state.error = nil
  local ok, err = pcall(function()
    if not (scenetree and createObject) then return end
    local plan = M.plan(state.opts)
    state.plan = plan
    applyShaders(plan)
    applyBase(plan)
    applyTemporal(plan)
    applyEdgeAA(plan)
    applySharpener(plan)
  end)
  if not ok then
    state.error = tostring(err)
    log('E', 'slrr_graphics', 'could not apply: ' .. tostring(err))
  end
  return M.status()
end

function M.status()
  local plan = state.plan or M.plan(state.opts)
  return {
    mode = plan.mode, sharpener = plan.sharpener, strength = state.strength, temporal = plan.temporal, error = state.error,
    owned = state.owned, edgeShader = shaderOf('SMAA_PostEffect'), weightShader = shaderOf('SMAA_PostEffect1'), fxaaShader = shaderOf('FXAA_PostEffect'),
    smaaOn = isEnabled('SMAA_PostEffect'), fxaaOn = isEnabled('FXAA_PostEffect'),
    casOn = isEnabled(SHARP.cas.effect), rcasOn = isEnabled(SHARP.rcas.effect), nisOn = isEnabled(SHARP.nis.effect),
    tsmOn = isEnabled(TSM), tsmCopyOn = isEnabled(TSM_COPY), edgeAAOn = isEnabled('EdgeAAPostEffect'), tune = tune,
  }
end

-- every frame: the smoothing waits a few frames after the history starts filling; every two seconds the settings are looked at again
-- (the player may change the anti-aliasing in Options > Graphics: with a mode of ours picked, ours wins within two seconds)
local timer = 0
function M.tick(dt)
  if state.tsmWait then
    state.tsmWait = state.tsmWait - 1
    if state.tsmWait <= 0 then
      state.tsmWait = nil
      if state.plan and (state.plan.temporal or state.plan.spec > 0) and find(TSM) then find(TSM):enable() log('I', 'slrr_graphics', 'temporal smoothing on') end
    end
  end
  timer = timer + (dt or 0)
  if timer < 2 or not state.opts then return end
  timer = 0
  M.apply()
end

----------------------------------------------------------------------------------------------
-- the controls in the game's own Options > Graphics page
-- Their values live in the game's settings under the keys below (the options page reads and writes those); the game tells us when one changed
-- (onSettingsChanged, forwarded by the garage extension). The page itself is the game's options layout (ui/ui-vue/src/modules/options/runtime/layout.json)
-- with one more group in the Graphics category, written into the user folder by installOptions; the game's own copy is never changed.

M.KEYS = { preset = 'slrrGfxPreset', mode = 'slrrGfxMode', predication = 'slrrGfxPredication', temporal = 'slrrGfxTemporal',
           edgeAA = 'slrrGfxEdgeAA', spec = 'slrrGfxSpec', sharpener = 'slrrGfxSharpener', strength = 'slrrGfxStrength' }
M.DEFAULTS = { preset = 'custom', mode = 'game', predication = true, temporal = M.DEFAULT_TEMPORAL, edgeAA = false, spec = 0, sharpener = 'off', strength = M.DEFAULT_STRENGTH }
local OPTION_NAMES = { 'preset', 'mode', 'predication', 'temporal', 'edgeAA', 'spec', 'sharpener', 'strength' }

-- the options from a getter (key, default) -> value, e.g. settings.getValue
function M.readOptions(get)
  local o = {}
  for _, name in ipairs(OPTION_NAMES) do
    local v = get(M.KEYS[name], nil)
    if v == nil then v = M.DEFAULTS[name] end
    o[name] = v
  end
  return o
end

-- which preset the options are (a preset's own values; anything else is custom)
function M.matchPreset(o)
  for _, p in ipairs(M.PRESETS) do
    if p.values then
      local same = true
      for _, name in ipairs(OPTION_NAMES) do
        if name ~= 'preset' then
          local want = p.values[name]
          if want == nil then want = M.DEFAULTS[name] end
          local have = o[name]
          if type(want) == 'number' then
            if type(have) ~= 'number' or math.abs(have - want) > 1e-3 then same = false end
          elseif have ~= want then same = false end
        end
      end
      if same then return p.id end
    end
  end
  return 'custom'
end

-- the settings screen's controls: a group for the Graphics category. Plain texts (not translation keys); the notes of every choice sit in its tooltip.
local function common(extra)
  local item = {
    version = '0.39', tooltip = '', interactive = true, condition_always_off = false, condition_not_shipping = false,
    condition_simplemenu = '', condition_visible = '', condition_enabled = '', separateLabel = true, manualApply = false, manualLua = '',
    lua = '', basic_interaction = false, slrr = true,
  }
  for k, v in pairs(extra) do item[k] = v end
  return item
end

local function choiceItem(label, setting, list, tooltip)
  local options = {}
  for _, o in ipairs(list) do options[#options + 1] = { value = o.id, label = o.label } end
  local notes = {}
  for _, o in ipairs(list) do notes[#notes + 1] = o.label .. ': ' .. o.note end
  return common({ label = label, setting = setting, tooltip = (tooltip and (tooltip .. '\n\n') or '') .. table.concat(notes, '\n\n'),
                  itemType = 'options', component = 'BngSmartSelect', optionsSource = '', options = options, search = { 'label', 'caption', 'tooltip', 'setting', 'options' } })
end

local function checkItem(label, setting, tooltip)
  return common({ label = label, setting = setting, tooltip = tooltip, itemType = 'checkbox', component = 'OptionsCheckbox', luaOff = '',
                  valueOn = true, valueOff = false, search = { 'label', 'caption', 'tooltip', 'setting' } })
end

local function sliderItem(label, setting, tooltip)
  return common({ label = label, setting = setting, tooltip = tooltip, itemType = 'slider', component = 'BngSlider', min = 0, max = 1, step = 0.05,
                  compact = false, valueMultiplier = 1, unit = '', inputMin = nil, inputMax = nil, inputStep = nil, search = { 'label', 'caption', 'tooltip', 'setting' } })
end

function M.optionsGroup()
  local k = M.KEYS
  return common({
    interactive = false, itemType = 'group', component = 'OptionsGroup', layout = 'column', firstAsTitle = true, separateLabel = nil, _slrr = 'group-v2',
    items = {
      common({ label = 'Wrench Works: anti-aliasing and sharpening', interactive = false, itemType = 'heading', component = 'OptionsHeading', icon = '_empty', variant = 'h4', search = { 'label' }, separateLabel = nil }),
      choiceItem('Preset', k.preset, M.PRESETS, 'Picks the settings below in one go. Changing any of them afterwards makes it Custom.'),
      choiceItem('Anti-aliasing mode', k.mode, M.MODES, 'Anything but Game\'s own takes over the Anti-aliasing and Anti-aliasing type settings above while it is picked.'),
      checkItem('Depth predication (SMAA Ultra)', k.predication, 'Lets SMAA Ultra use the depth: edges of objects are caught at full sensitivity and fine texture detail is not mistaken for edges.'),
      sliderItem('Temporal smoothing amount', k.temporal, 'For the Temporal smoothing mode: how much of the previous frame is kept. More calms shimmer more but can soften the picture while moving.'),
      checkItem('Edge smoothing pass (game\'s own)', k.edgeAA, 'The game\'s own depth and normal edge blur (a cheap extra pass that smooths creases and silhouettes SMAA sees little of). Its vertex shader fails to compile in BeamNG 0.39, so it does nothing there (kept for other versions).'),
      sliderItem('Specular shimmer reduction', k.spec, 'Calms bright sparkle on glossy, bumpy surfaces (car paint, rain-wet roads): the sparkle pixel is held to what it was last frame and blended towards its neighbours on the same surface. 0 is off; too much dulls real highlights. Works with Temporal smoothing best, and alone as a light blur.'),
      choiceItem('Sharpening', k.sharpener, M.SHARPENERS, 'Brings back the detail anti-aliasing softens. Runs after the anti-aliasing.'),
      sliderItem('Sharpening strength', k.strength, 'How much sharpening. 0.4 is gentle; above 0.7 thin lines start to look etched. 0 is the same as off.'),
      common({ label = '', caption = M.unavailableText(), interactive = false, itemType = 'text', component = 'OptionsText', variant = '', innerCaption = true,
               optionsSource = '', options = {}, search = { 'caption' }, separateLabel = true }),
    },
  })
end

-- puts the group into a copy of the game's layout (right after the anti-aliasing type); any earlier copy of ours is taken out first. nil + reason when the page is not found.
function M.patchLayout(layout)
  if type(layout) ~= 'table' or type(layout.items) ~= 'table' then return nil, 'no layout' end
  local function strip(items)
    for i = #items, 1, -1 do
      local it = items[i]
      if it.slrr == true then table.remove(items, i)
      elseif type(it.items) == 'table' then strip(it.items) end
    end
  end
  strip(layout.items)
  for _, category in ipairs(layout.items) do
    if category.categoryId == 'graphics' and type(category.items) == 'table' then
      for i, it in ipairs(category.items) do
        if it.setting == 'GraphicAntialiasType' then
          table.insert(category.items, i + 1, M.optionsGroup())
          return layout
        end
      end
    end
  end
  return nil, 'the Graphics page has no anti-aliasing type to put the group after'
end

-- our group as JSON text (written by hand: the game's encoder cannot tell an empty list from an empty object, and the layout is full of empty lists)
local function encodeJson(v)
  local t = type(v)
  if t == 'string' then
    local escaped = v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' elseif c == '\n' then return '\\n' end
      return string.format('\\u%04x', c:byte())
    end)
    return '"' .. escaped .. '"'
  elseif t == 'number' or t == 'boolean' then return tostring(v)
  elseif t == 'table' then
    if next(v) == nil or v[1] ~= nil then
      local out = {}
      for i = 1, #v do out[i] = encodeJson(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = encodeJson(k) .. ':' .. encodeJson(v[k]) end
    return '{' .. table.concat(out, ',') .. '}'
  end
  return 'null'
end
M.encodeJson = encodeJson

-- The group put into the game's layout text right after the anti-aliasing type item, the rest of the text untouched (byte for byte). nil + reason if it cannot.
-- where the object that opens at text[open] ends (strings skipped); nil if the text runs out
local function objectEnd(text, open)
  local depth, pos = 0, open
  while true do
    local i = text:find('["{}]', pos)
    if not i then return nil end
    local c = text:sub(i, i)
    if c == '"' then
      local j = i + 1
      while true do
        j = text:find('["\\]', j)
        if not j then return nil end
        if text:sub(j, j) == '\\' then j = j + 2 else break end
      end
      pos = j + 1
    elseif c == '{' then
      depth = depth + 1
      pos = i + 1
    else
      depth = depth - 1
      if depth == 0 then return i end
      pos = i + 1
    end
  end
end

-- the text without any earlier copy of our group (this version's marker, or the first version's start)
local function stripGroup(text)
  for _, start in ipairs({ ',{"_slrr":"group-v2"', ',{"basic_interaction":false,"component":"OptionsGroup"' }) do
    local at = text:find(start, 1, true)
    if at then
      local close = objectEnd(text, at + 1)
      if not close then return nil end
      return text:sub(1, at - 1) .. text:sub(close + 1)
    end
  end
  return text
end

function M.patchLayoutText(text)
  if type(text) ~= 'string' then return nil, 'no layout' end
  text = stripGroup(text)
  if not text then return nil, 'unbalanced layout' end
  local anchor = text:find('"setting"%s*:%s*"GraphicAntialiasType"')
  if not anchor then return nil, 'the Graphics page has no anti-aliasing type to put the group after' end
  -- walk the text (strings skipped) to find the object that holds the anchor and where it ends
  local pos, stack, itemStart, depthAtItem = 1, {}, nil, nil
  while true do
    local i = text:find('["{}]', pos)
    if not i then return nil, 'unbalanced layout' end
    local c = text:sub(i, i)
    if c == '"' then
      local j = i + 1
      while true do
        j = text:find('["\\]', j)
        if not j then return nil, 'unbalanced layout' end
        if text:sub(j, j) == '\\' then j = j + 2 else break end
      end
      pos = j + 1
    elseif c == '{' then
      stack[#stack + 1] = i
      pos = i + 1
    else
      local opened = table.remove(stack)
      if itemStart and #stack < depthAtItem then
        return text:sub(1, i) .. ',' .. encodeJson(M.optionsGroup()) .. text:sub(i + 1)
      end
      pos = i + 1
    end
    if not itemStart and pos > anchor then
      itemStart = stack[#stack]
      depthAtItem = #stack
    end
  end
end

local LAYOUT_DIR = '/ui/ui-vue/src/modules/options/runtime/'

local function readText(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local text = f:read('*a')
  f:close()
  return text
end

-- Writes the patched layout into the user folder when it is not there yet or the game's own layout changed (a game update); the game's copy is read from
-- the game folder because the user folder's copy hides it. Takes effect when the game's UI loads the options page (restart the game the first time).
local function slash(p) return (string.gsub(p or '', '\\', '/')) end
local function inUserFolder(real)
  local user = slash(FS:getUserPath())
  return user ~= '' and string.sub(slash(real), 1, #user) == user
end

-- the game's own layout text, from wherever it is: its real file (when that is not our copy in the user folder), the game folder, or the game's virtual file
-- system (which shows our copy once installed; that one is refused, see patchLayoutText)
local function gameLayoutText()
  local vpath = LAYOUT_DIR .. 'layout.json'
  local real = slash(FS:getFileRealPath(vpath))
  local tried = { 'real=' .. real, 'game=' .. slash(FS:getGamePath()) }
  local candidates = {}
  if real ~= '' and not inUserFolder(real) then candidates[#candidates + 1] = real end
  candidates[#candidates + 1] = slash(FS:getGamePath()) .. vpath
  for _, path in ipairs(candidates) do
    local text = readText(path)
    if text and #text > 1000 then return text, path end
  end
  local ok, text = pcall(readFile, vpath)
  if ok and type(text) == 'string' and #text > 1000 then return text, 'virtual ' .. vpath end
  return nil, table.concat(tried, ' ')
end

-- Writes the patched layout into the user folder when it is not there yet or differs (a game update, a newer mod). Takes effect when the game's UI loads the
-- options page (restart the game the first time).
function M.installOptions()
  local ok, err = pcall(function()
    local text, source = gameLayoutText()
    if not text then log('W', 'slrr_graphics', 'options page: the game layout file was not found (' .. tostring(source) .. '), nothing added') return end
    local patched, why = M.patchLayoutText(text)
    if not patched then
      log('W', 'slrr_graphics', 'options page: ' .. tostring(why) .. ' (read from ' .. tostring(source) .. '), nothing changed')
      return
    end
    local mine = slash(FS:getFileRealPath(LAYOUT_DIR .. 'layout.json'))
    local current = inUserFolder(mine) and readText(mine) or nil
    if current == patched then return end
    extensions.load('ui_options')
    if ui_options.saveLayout('', patched) then
      log('I', 'slrr_graphics', 'options page: anti-aliasing group added to Options > Graphics, layout read from ' .. tostring(source) .. ' (restart the game to see it if the page was already open)')
    end
  end)
  if not ok then log('E', 'slrr_graphics', 'options page install failed: ' .. tostring(err)) end
end

-- takes our copy of the layout away again (the game's own shows)
function M.uninstallOptions()
  local real = string.gsub(FS:getFileRealPath(LAYOUT_DIR .. 'layout.json') or '', '\\', '/')
  local userPath = string.gsub(FS:getUserPath() or '', '\\', '/')
  if userPath ~= '' and string.sub(real, 1, #userPath) == userPath then FS:removeFile(real) end
end

-- the settings the options page keeps: start values for those not there yet
function M.ensureDefaults()
  if not (settings and settings.getValue and settings.setValue) then return end
  for _, name in ipairs(OPTION_NAMES) do
    if settings.getValue(M.KEYS[name]) == nil then settings.setValue(M.KEYS[name], M.DEFAULTS[name]) end
  end
end

local lastPreset
-- picks a preset by id (balanced, smooth, max, custom), as the options page does
function M.applyPreset(id)
  if not (settings and settings.setValue) then return end
  settings.setValue(M.KEYS.preset, id)
  return M.onSettingsChanged()
end

-- the game says some setting changed: a new preset picks its values; any other change of ours makes the preset Custom (or the one it now equals); then the picture follows
function M.onSettingsChanged()
  if not (settings and settings.getValue) then return end
  local o = M.readOptions(settings.getValue)
  if o.preset ~= lastPreset then
    lastPreset = o.preset
    local values = M.presetValues(o.preset)
    if values then
      for name, v in pairs(M.DEFAULTS) do
        if name ~= 'preset' then
          local want = values[name]
          if want == nil then want = v end
          if o[name] ~= want then settings.setValue(M.KEYS[name], want) o[name] = want end
        end
      end
    end
  else
    local match = M.matchPreset(o)
    if match ~= o.preset then lastPreset = match settings.setValue(M.KEYS.preset, match) o.preset = match end
  end
  return M.apply(o)
end

-- a level ends: our objects may go with it (made again when needed); the game's SMAA/FXAA effects stay, with whatever shader they have
function M.onLevelEnd()
  state.tsmWait = nil
end

return M
