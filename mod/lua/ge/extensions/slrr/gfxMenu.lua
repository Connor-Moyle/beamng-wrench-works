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
      -- anti-aliasing
      field({ id = aa.preset, tab = 'aa', group = 'Preset', type = 'enum', label = 'Preset', key = gk.preset, default = gd.preset, options = options(G.PRESETS, gd, { mode = aa.mode, predication = aa.predication, temporal = aa.temporal, edgeAA = aa.edgeAA, spec = aa.spec, sharpener = aa.sharpener, strength = aa.strength }),
              tooltip = 'Picks the settings below in one go. Changing any of them afterwards makes it Custom. ' .. notes(G.PRESETS) }),
      field({ id = aa.mode, tab = 'aa', group = 'Anti-aliasing', type = 'enum', label = 'Anti-aliasing mode', key = gk.mode, default = gd.mode, options = options(G.MODES, gd, {}),
              presets = { performance = 'fxaa', balanced = 'smaa', quality = 'smaaUltra', max = 'smaaUltraTemporal' },          -- Quick setup (the Mods menu's whole-pack presets)
              tooltip = 'Anything but Game\'s own takes over the game\'s Anti-aliasing and Anti-aliasing type settings while it is picked. ' .. notes(G.MODES) }),
      field({ id = aa.predication, tab = 'aa', group = 'Anti-aliasing', type = 'bool', label = 'Depth predication (SMAA Ultra)', key = gk.predication, default = gd.predication,
              tooltip = 'Lets SMAA Ultra use the depth: edges of objects are caught at full sensitivity and fine texture detail is not mistaken for edges.' }),
      field({ id = aa.temporal, tab = 'aa', group = 'Anti-aliasing', type = 'slider', label = 'Temporal smoothing amount', key = gk.temporal, default = gd.temporal, min = 0, max = 1, step = 0.05, presets = { max = 0.7 },
              tooltip = 'For the Temporal smoothing mode: how much of the previous frame is kept. More calms shimmer more but can soften the picture while moving.' }),
      field({ id = aa.edgeAA, tab = 'aa', group = 'Anti-aliasing', type = 'bool', label = 'Edge smoothing pass (game\'s own)', key = gk.edgeAA, default = gd.edgeAA, advanced = true,
              tooltip = 'The game\'s own depth and normal edge blur. Its vertex shader fails to compile in BeamNG 0.39, so it does nothing there (kept for other versions).' }),
      field({ id = aa.spec, tab = 'aa', group = 'Shimmer', type = 'slider', label = 'Specular shimmer reduction', key = gk.spec, default = gd.spec, min = 0, max = 1, step = 0.05,
              tooltip = 'Calms bright sparkle on glossy, bumpy surfaces (car paint, rain-wet roads). 0 is off; too much dulls real highlights. Works best with Temporal smoothing.' }),
      field({ id = aa.sharpener, tab = 'aa', group = 'Sharpening', type = 'enum', label = 'Sharpening', key = gk.sharpener, default = gd.sharpener, options = options(G.SHARPENERS, gd, {}), presets = { performance = 'off', balanced = 'off', quality = 'cas', max = 'cas' },
              tooltip = 'Brings back the detail anti-aliasing softens. Runs after the anti-aliasing. ' .. notes(G.SHARPENERS) }),
      field({ id = aa.strength, tab = 'aa', group = 'Sharpening', type = 'slider', label = 'Sharpening strength', key = gk.strength, default = gd.strength, min = 0, max = 1, step = 0.05, presets = { quality = 0.4, max = 0.4 },
              tooltip = 'How much sharpening. 0.4 is gentle; above 0.7 thin lines start to look etched. 0 is the same as off.' }),
      { id = 'aa_unavailable', tab = 'aa', type = 'note', label = G.unavailableText() },
      -- look
      field({ id = 'look_preset', tab = 'look', group = 'Look', type = 'enum', label = 'Look', key = lk.preset, default = ld.preset, options = options(Lk.PRESETS, ld, look),
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
      field({ id = 'cam_preset', tab = 'camera', group = 'Cinematic camera', type = 'enum', label = 'Cinematic camera', key = ck.preset, default = cd.preset, options = options(C.PRESETS, cd, cam),
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
