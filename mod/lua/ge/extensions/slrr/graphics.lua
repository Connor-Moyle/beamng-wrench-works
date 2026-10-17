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
  { id = 'balanced', label = 'Balanced', values = { gfxAaMode = 'smaaUltra', gfxPredication = true, gfxSharpener = 'cas', gfxSharpenStrength = 0.4 },
    note = 'SMAA Ultra with depth predication and gentle AMD CAS sharpening. Clean edges, cheap.' },
  { id = 'smooth', label = 'Smooth', values = { gfxAaMode = 'smaaUltraTemporal', gfxPredication = true, gfxTemporal = 0.7, gfxSharpener = 'cas', gfxSharpenStrength = 0.6 },
    note = 'SMAA Ultra plus Temporal smoothing and firmer CAS: the calmest picture while driving.' },
  { id = 'max', label = 'Maximum', values = { gfxAaMode = 'smaaUltraTemporal', gfxPredication = true, gfxTemporal = 0.85, gfxSharpener = 'nis', gfxSharpenStrength = 0.5 },
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
    block:registerObject('SLRR_TSM_StateBlock')
  end
  makeShaderData('SLRR_TSM_ShaderData', 'slrr_tsmV.hlsl', 'slrr_tsmP.hlsl', { '$curTex', '$histTex', '$velTex' })
  makeShaderData('SLRR_TSMCopy_ShaderData', 'slrr_tsmV.hlsl', 'slrr_tsmCopyP.hlsl', { '$curTex' })
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
  e:setShaderConst('$tsmParams', string.format('%f 0 0 0', state.tsmWeight))
  e:setShaderConst('$tsmSize', string.format('%f %f 0 0', size.x, size.y))
end
rawset(_G, TSM .. 'Callbacks', { preProcess = tsmConsts, onEnabled = function() tsmConsts() return true end })

local function applyTemporal(plan)
  state.tsmWeight = plan.temporalWeight
  if not plan.temporal then
    state.tsmWait = nil
    if isEnabled(TSM) then find(TSM):disable() log('I', 'slrr_graphics', 'temporal smoothing off') end
    if isEnabled(TSM_COPY) then find(TSM_COPY):disable() end
    return
  end
  ensureTsm()
  if not isEnabled(TSM_COPY) then find(TSM_COPY):enable() end
  if not isEnabled(TSM) and not state.tsmWait then
    state.tsmWait = 3          -- a few frames for the history to fill before the smoothing reads it
  end
  tsmConsts()
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
    tsmOn = isEnabled(TSM), tsmCopyOn = isEnabled(TSM_COPY),
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
      if state.plan and state.plan.temporal and find(TSM) then find(TSM):enable() log('I', 'slrr_graphics', 'temporal smoothing on') end
    end
  end
  timer = timer + (dt or 0)
  if timer < 2 or not state.opts then return end
  timer = 0
  M.apply()
end

-- a level ends: our objects may go with it (made again when needed); the game's SMAA/FXAA effects stay, with whatever shader they have
function M.onLevelEnd()
  state.tsmWait = nil
end

return M
