-- Wrench Works: the graphics package's page in the pause-menu Mods menu (slrr_settings): three tabs, Anti-aliasing & sharpening, Look, Cinematic camera.
-- The values stay in the game settings under the keys the modules read (slrrGfx*, slrrLook*, slrrCam*), so slrr/graphics, slrr/look and slrr/camera do not change; a
-- changed value is handed to graphics.onSettingsChanged, which fills a preset's other settings, makes a changed one Custom and applies the picture.
-- Registered from the garage extension: at load and when the registry says it is ready (slrr_settings is Wrench Works' own; absent, nothing is shown and the package
-- runs on its defaults).
local M = {}

M.MOD = 'wrench_works_gfx'

-- the notes of a list of choices in one text, for a tooltip
local function notes(list)
  local out = {}
  for _, o in ipairs(list) do if o.note then out[#out + 1] = o.label .. ': ' .. o.note end end
  return table.concat(out, ' ')
end

-- a list of { id, label, note, values } as enum options; a preset's values become `sets` (the registry writes them through the other fields' stores), `ids` maps
-- a value name to the id of its field
local function options(list, defaults, ids)
  local out = {}
  for _, o in ipairs(list) do
    local opt = { id = o.id, label = o.label }
    if o.values then
      opt.sets = {}
      for name, fieldId in pairs(ids) do
        local v = o.values[name]
        if v == nil then v = defaults[name] end
        opt.sets[fieldId] = v
      end
    end
    out[#out + 1] = opt
  end
  return out
end

local function changed() require('slrr/graphics').onSettingsChanged() end

local function field(f)
  f.store = { kind = 'setting', key = f.key }
  f.onChange = changed
  f.key = nil
  return f
end

-- the game's own upscalers/anti-aliasing types this GPU and the lighting quality allow (GraphicAntialiasType, BeamNG 0.40; core/settings/graphic.lua): the keys, as the game's own list
-- of them names (an engine without the call lists them all, as the game does)
M.UPSCALER_MODES = { { 'fxaa', 'FXAA', 8 }, { 'smaa', 'SMAA', 8 }, { 'smaaT2x', 'SMAA T2x', 7 }, { 'dlss', 'NVIDIA DLSS', 1 }, { 'fsr3', 'AMD FSR 3', 2 }, { 'fsr4', 'AMD FSR 4', 3 },
                     { 'xess', 'Intel XeSS', 4 }, { 'fsrCustom', 'FSR (custom)', 5 }, { 'pssr', 'PSSR', 9 } }
-- the lowest lighting quality has no depth and motion vectors for the temporal upscalers: the game refuses them there, so the row does not offer them
local function lowestLighting()
  return rawget(_G, 'settings') and settings.getValue and settings.getValue('GraphicLightingQuality') == 'Lowest'
end
function M.upscalerOptions(available)
  local out = { { id = 'off', label = 'Off' } }
  for _, m in ipairs(M.UPSCALER_MODES) do
    if not available or available(m[3]) then
      out[#out + 1] = { id = m[1], label = m[2], hideIf = require('slrr/graphics').TEMPORAL_UPSCALERS[m[1]] and lowestLighting or nil }
    end
  end
  return out
end
local function gpuAvailable()
  if not (RenderView and RenderView.isUpscaleModeAvailable) then return nil end
  return function(mode) local ok, r = pcall(RenderView.isUpscaleModeAvailable, mode) return ok and r end
end
-- the upscaler values that do the anti-aliasing themselves (ours are greyed out while one of them is picked)
local TEMPORAL = { 'dlss', 'fsr3', 'fsr4', 'xess', 'fsrCustom', 'pssr', 'smaaT2x' }
local NO_SHARPEN = { 'off', 'fxaa', 'smaa', 'smaaT2x' }

function M.schema()
  local G, Lk, C = require('slrr/graphics'), require('slrr/look'), require('slrr/camera')
  local gk, lk, ck = G.KEYS, Lk.KEYS, C.KEYS
  local aa = { preset = 'aa_preset', mode = 'aa_mode', predication = 'aa_predication', temporal = 'aa_temporal', edgeAA = 'aa_edge', spec = 'aa_spec', sharpener = 'aa_sharpener', strength = 'aa_strength' }
  local look = { contrast = 'look_contrast', saturation = 'look_saturation', warmth = 'look_warmth', split = 'look_split', vignette = 'look_vignette' }
  local cam = { blur = 'cam_blur', dof = 'cam_dof', letterbox = 'cam_letterbox' }
  local gd, ld, cd = G.DEFAULTS, Lk.DEFAULTS, C.DEFAULTS
  local AA, LOOK, CAM = 'Anti-aliasing & sharpening', 'Look', 'Cinematic camera'
  return {
    mod = M.MOD, title = 'Wrench Works: graphics & camera', icon = 'wrench', order = 30,
    tabs = {
      { id = 'aa', title = AA, description = 'Smoother edges and sharper detail. "Game\'s own" leaves the game\'s anti-aliasing exactly as it is; anything else takes over its anti-aliasing type while it is picked.' },
      { id = 'look', title = LOOK, description = 'A light colour grade and a vignette on the finished picture. Off changes nothing; the menus and the HUD are not touched.' },
      { id = 'camera', title = CAM, description = 'Motion blur, depth of field and letterbox bars for replays and photos. Off leaves the game\'s own settings alone; photo mode keeps its own while it is open.' },
    },
    fields = {
      -- the game's own upscalers (0.40): set through the game's settings, so Options > Graphics shows the same
      { id = 'up_type', tab = 'aa', group = 'Upscaling (BeamNG 0.40)', type = 'enum', label = 'Upscaler', default = 'off', options = M.upscalerOptions(gpuAvailable()), onChange = changed,
        store = { kind = 'setting', key = 'GraphicAntialiasType' },
        tooltip = 'The game\'s own anti-aliasing type, the same setting as Options > Graphics: only the ones this graphics card supports are listed (the temporal ones also need the lighting quality above Lowest). DLSS, FSR, XeSS and PSSR render the picture smaller and rebuild it; they do the anti-aliasing themselves, so the anti-aliasing and shimmer settings below are switched off while one is picked.' },
      { id = 'up_preset', tab = 'aa', group = 'Upscaling (BeamNG 0.40)', type = 'enum', label = 'Quality', default = 'quality', onChange = changed,
        store = { kind = 'setting', key = G.UP_KEY },
        options = (function() local o = {} for _, p in ipairs(G.UPSCALE_PRESETS) do o[#o + 1] = { id = p.id, label = p.label, sets = { up_scale = p.scale } } end o[#o + 1] = { id = 'custom', label = 'Custom' } return o end)(),
        tooltip = 'How small the picture is rendered before the upscaler rebuilds it: DLAA / native renders at full size (best picture, the AA only), Quality about 2/3, Balanced 0.59, Performance half, Ultra Performance a third (fastest). Also applies to FXAA and SMAA, which then stretch the smaller picture.' },
      { id = 'up_scale', tab = 'aa', group = 'Upscaling (BeamNG 0.40)', type = 'slider', label = 'Render scale', default = 1 / 1.5, min = 0.33, max = 1, step = 0.01, onChange = changed,
        store = { kind = 'setting', key = 'GraphicUpscalingQuality' }, advanced = true,
        tooltip = 'The exact render scale (the same setting as Options > Graphics): 1 is native, 0.5 renders half the width and height.' },
      { id = 'up_sharp', tab = 'aa', group = 'Upscaling (BeamNG 0.40)', type = 'slider', label = 'Sharpness', default = 0, min = 0, max = 1, step = 0.05, onChange = changed,
        store = { kind = 'setting', key = 'GraphicUpscalingSharpness' },
        disabledIf = { field = 'up_type', oneOf = NO_SHARPEN, why = 'Upscaler sharpening only applies to DLSS, FSR, XeSS and PSSR.' },
        tooltip = 'The upscaler\'s own sharpening after the rebuild. 0 is off; our sharpening below only runs when this is 0.' },
      -- anti-aliasing
      field({ id = aa.preset, tab = 'aa', disabledIf = { field = 'up_type', oneOf = TEMPORAL, why = 'The upscaler already handles this.' }, group = 'Preset', type = 'enum', label = 'Preset', key = gk.preset, default = gd.preset, options = options(G.PRESETS, gd, { mode = aa.mode, predication = aa.predication, temporal = aa.temporal, edgeAA = aa.edgeAA, spec = aa.spec, sharpener = aa.sharpener, strength = aa.strength }),
              tooltip = 'Picks the settings below in one go. Changing any of them afterwards makes it Custom. ' .. notes(G.PRESETS) }),
      field({ id = aa.mode, feature = true, offValue = 'game', tab = 'aa', disabledIf = { field = 'up_type', oneOf = TEMPORAL, why = 'The upscaler already handles this.' }, group = 'Anti-aliasing', type = 'enum', label = 'Anti-aliasing mode', key = gk.mode, default = gd.mode, options = options(G.MODES, gd, {}),
              presets = { performance = 'fxaa', balanced = 'smaa', quality = 'smaaUltra', max = 'smaaUltraTemporal' },          -- Quick setup (the Mods menu's whole-pack presets)
              tooltip = 'Anything but Game\'s own takes over the game\'s Anti-aliasing and Anti-aliasing type settings while it is picked. ' .. notes(G.MODES) }),
      field({ id = aa.predication, tab = 'aa', disabledIf = { field = 'up_type', oneOf = TEMPORAL, why = 'The upscaler already handles this.' }, group = 'Anti-aliasing', type = 'bool', label = 'Depth predication (SMAA Ultra)', key = gk.predication, default = gd.predication,
              tooltip = 'Lets SMAA Ultra use the depth: edges of objects are caught at full sensitivity and fine texture detail is not mistaken for edges.' }),
      field({ id = aa.temporal, tab = 'aa', disabledIf = { field = 'up_type', oneOf = TEMPORAL, why = 'The upscaler already handles this.' }, group = 'Anti-aliasing', type = 'slider', label = 'Temporal smoothing amount', key = gk.temporal, default = gd.temporal, min = 0, max = 1, step = 0.05, presets = { max = 0.7 },
              tooltip = 'For the Temporal smoothing mode: how much of the previous frame is kept. More calms shimmer more but can soften the picture while moving.' }),
      field({ id = aa.edgeAA, tab = 'aa', disabledIf = { field = 'up_type', oneOf = TEMPORAL, why = 'The upscaler already handles this.' }, group = 'Anti-aliasing', type = 'bool', label = 'Edge smoothing pass (game\'s own)', key = gk.edgeAA, default = gd.edgeAA, advanced = true,
              tooltip = 'The game\'s own depth and normal edge blur. Its vertex shader fails to compile in BeamNG 0.39, so it does nothing there (kept for other versions).' }),
      field({ id = aa.spec, tab = 'aa', disabledIf = { field = 'up_type', oneOf = TEMPORAL, why = 'The upscaler already handles this.' }, group = 'Shimmer', type = 'slider', label = 'Specular shimmer reduction', key = gk.spec, default = gd.spec, min = 0, max = 1, step = 0.05,
              tooltip = 'Calms bright sparkle on glossy, bumpy surfaces (car paint, rain-wet roads). 0 is off; too much dulls real highlights. Works best with Temporal smoothing.' }),
      field({ id = aa.sharpener, tab = 'aa', group = 'Sharpening', type = 'enum', label = 'Sharpening', key = gk.sharpener, default = gd.sharpener, options = options(G.SHARPENERS, gd, {}), presets = { performance = 'off', balanced = 'off', quality = 'cas', max = 'cas' },
              tooltip = 'Brings back the detail anti-aliasing softens. Runs after the anti-aliasing. ' .. notes(G.SHARPENERS) }),
      field({ id = aa.strength, tab = 'aa', group = 'Sharpening', type = 'slider', label = 'Sharpening strength', key = gk.strength, default = gd.strength, min = 0, max = 1, step = 0.05, presets = { quality = 0.4, max = 0.4 },
              tooltip = 'How much sharpening. 0.4 is gentle; above 0.7 thin lines start to look etched. 0 is the same as off.' }),
      { id = 'aa_unavailable', tab = 'aa', type = 'note', label = G.unavailableText() },
      -- look
      field({ id = 'look_preset', feature = true, tab = 'look', group = 'Look', type = 'enum', label = 'Look', key = lk.preset, default = ld.preset, options = options(Lk.PRESETS, ld, look),
              tooltip = 'A light colour grade on the finished picture. Off changes nothing. Changing any control below afterwards makes it Custom. ' .. notes(Lk.PRESETS) }),
      field({ id = look.contrast, tab = 'look', group = 'Grade', type = 'slider', label = 'Contrast', key = lk.contrast, default = ld.contrast, min = 0, max = 1, step = 0.05,
              tooltip = 'A gentle S-curve: deeper shadows, brighter highlights.' }),
      field({ id = look.saturation, tab = 'look', group = 'Grade', type = 'slider', label = 'Saturation', key = lk.saturation, default = ld.saturation, min = -0.5, max = 0.5, step = 0.05,
              tooltip = 'Colour strength. 0 is as the game draws it, below it is more muted, above it is stronger.' }),
      field({ id = look.warmth, tab = 'look', group = 'Grade', type = 'slider', label = 'Warmth', key = lk.warmth, default = ld.warmth, min = -1, max = 1, step = 0.1,
              tooltip = 'Cool (blue) to warm (orange) tint. 0 is neutral.' }),
      field({ id = look.split, tab = 'look', group = 'Grade', type = 'slider', label = 'Colour split', key = lk.split, default = ld.split, min = 0, max = 1, step = 0.05,
              tooltip = 'Cool shadows and warm highlights, a film look.' }),
      field({ id = look.vignette, tab = 'look', group = 'Grade', type = 'slider', label = 'Vignette', key = lk.vignette, default = ld.vignette, min = 0, max = 1, step = 0.05,
              tooltip = 'Darkens the corners of the picture. The menus and the HUD are not touched.' }),
      -- cinematic camera
      field({ id = 'cam_preset', feature = true, tab = 'camera', group = 'Cinematic camera', type = 'enum', label = 'Cinematic camera', key = ck.preset, default = cd.preset, options = options(C.PRESETS, cd, cam),
              tooltip = 'Motion blur, depth of field and letterbox bars for replays and photos. Off leaves the game\'s own settings alone. Changing any control below afterwards makes it Custom. ' .. notes(C.PRESETS) }),
      field({ id = cam.blur, tab = 'camera', group = 'Effects', type = 'slider', label = 'Motion blur', key = ck.blur, default = cd.blur, min = 0, max = 2, step = 0.1, presets = { performance = 0 },
              tooltip = 'Strength of the game\'s motion blur. 0 leaves the game\'s own setting.' }),
      field({ id = cam.dof, tab = 'camera', group = 'Effects', type = 'slider', label = 'Depth of field', key = ck.dof, default = cd.dof, min = 0, max = 1, step = 0.05, presets = { performance = 0 },
              tooltip = 'Blurs the background, focus follows the car (the camera\'s target). 0 leaves the game\'s own setting.' }),
      field({ id = cam.letterbox, tab = 'camera', group = 'Effects', type = 'enum', label = 'Letterbox', key = ck.letterbox, default = cd.letterbox, options = options(C.LETTERBOX, cd, {}),
              tooltip = 'Black bars top and bottom for a wide cinema picture (a 16:9 screen at 2.39:1). A screen already that wide or wider gets none. The menus and the HUD are not cut. ' .. notes(C.LETTERBOX) }),
    },
  }
end

-- the groups earlier versions wrote into the game's Options page (the user-folder copy of its layout): taken out, once per start, so the page does not show them twice
-- (their markers; the first version of the graphics group had none)
function M.removeOldGroups()
  local ok, L = pcall(require, 'slrr/optionsLayout')
  if not ok then return end
  pcall(L.uninstall, 'group-v2', { ',{"basic_interaction":false,"component":"OptionsGroup"' })
  pcall(L.uninstall, 'look-v1')
  pcall(L.uninstall, 'camera-v1')
end

-- put the page into the Mods menu (Wrench Works' registry; nothing happens without it)
function M.register()
  local S = rawget(_G, 'slrr_settings')
  if not S or not S.register then return false end
  local ok, err = pcall(function() S.register(M.schema()) end)
  if not ok and log then log('E', 'slrr_gfxMenu', 'register failed: ' .. tostring(err)) end
  return ok
end

return M
