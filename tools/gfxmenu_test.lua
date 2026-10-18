-- The graphics package's Mods menu page (slrr/gfxMenu) on the real registry (slrr/settings) with stand-ins for the game. Run: node tools/gfxmenu_test.js
local S = require('slrr/settings')
local function check(name, ok, detail) if not ok then error('FAILED: ' .. name .. (detail and (' ' .. tostring(detail)) or ''), 0) end end
local store, logs = {}, {}
S.env.getSetting = function(k) return store[k] end
S.env.setSetting = function(k, v) store[k] = v end
S.env.log = function(l, t) logs[#logs + 1] = l .. ' ' .. t end
log = function(l, t) logs[#logs + 1] = l .. ' ' .. t end
-- the game's settings, as slrr/graphics, look and camera read them (and call onSettingsChanged by hand, as the registry's onChange does)
settings = { getValue = function(k, d) local v = store[k] if v == nil then return d end return v end, setValue = function(k, v) store[k] = v end }
scenetree = nil
_G.slrr_settings = S

local M = require('slrr/gfxMenu')
check('register', M.register() == true and #logs == 0, table.concat(logs, '; '))
local mods = S.mods()
local mine
for _, m in ipairs(mods) do if m.mod == M.MOD then mine = m end end
check('the mod is listed with its three tabs', mine and #mine.tabs == 3 and mine.tabs[1].id == 'aa' and mine.tabs[2].id == 'look' and mine.tabs[3].id == 'camera')

-- every settings key the modules read has a field, and the page shows the defaults
local G, Lk, C = require('slrr/graphics'), require('slrr/look'), require('slrr/camera')
local keys = {}
for _, f in ipairs(M.schema().fields) do if f.store and f.store.key then keys[f.store.key] = f end end
for _, K in ipairs({ G.KEYS, Lk.KEYS, C.KEYS }) do for name, key in pairs(K) do check('a field for ' .. key, keys[key] ~= nil) end end
local shown = {}
for _, tab in ipairs({ 'aa', 'look', 'camera' }) do for _, f in ipairs(S.page(M.MOD, tab).fields) do shown[f.id] = f end end
check('the page shows the defaults', shown.aa_mode.value == G.DEFAULTS.mode and shown.aa_preset.value == G.DEFAULTS.preset and shown.cam_letterbox.value == 'off')

-- a preset fills the other settings through their stores, and the module's own handling follows
local r = S.set(M.MOD, 'aa_preset', 'smooth')
check('preset accepted', r.ok, r.error)
check('smooth filled mode and temporal', store[G.KEYS.mode] == 'smaaUltraTemporal' and store[G.KEYS.preset] == 'smooth' and store[G.KEYS.predication] == true)
r = S.set(M.MOD, 'aa_strength', 0.9)
check('a slider is stored', r.ok and store[G.KEYS.strength] == 0.9)
check('changing one makes it custom (graphics.onSettingsChanged ran)', store[G.KEYS.preset] == 'custom' or store[G.KEYS.preset] == 'max', store[G.KEYS.preset])
check('clamped', S.set(M.MOD, 'aa_strength', 5).value == 1)
check('an unknown option is refused', S.set(M.MOD, 'aa_mode', 'nonsense').ok == false)

r = S.set(M.MOD, 'look_preset', 'cinematic')
check('look preset filled', r.ok and math.abs(store[Lk.KEYS.contrast] - 0.35) < 1e-6 and math.abs(store[Lk.KEYS.vignette] - 0.35) < 1e-6 and store[Lk.KEYS.split] == 0.5)
r = S.set(M.MOD, 'cam_preset', 'film')
check('camera preset filled', r.ok and store[C.KEYS.letterbox] == '2.39' and store[C.KEYS.blur] == 1)
r = S.set(M.MOD, 'cam_letterbox', 'off')
check('letterbox off makes it custom', r.ok and store[C.KEYS.preset] == 'custom')

-- Quick setup: the whole-pack presets write the fields' declared values through their stores
S.applyPreset('performance')
check('performance: FXAA, no sharpening, no blur or depth of field', store[G.KEYS.mode] == 'fxaa' and store[G.KEYS.sharpener] == 'off' and store[C.KEYS.blur] == 0 and store[C.KEYS.dof] == 0)
check('performance is the current preset', S.currentPreset() == 'performance', S.currentPreset())
S.applyPreset('quality')
check('quality: SMAA Ultra with CAS', store[G.KEYS.mode] == 'smaaUltra' and store[G.KEYS.sharpener] == 'cas' and store[G.KEYS.strength] == 0.4)
S.applyPreset('max')
check('max: SMAA Ultra + Temporal with CAS', store[G.KEYS.mode] == 'smaaUltraTemporal' and store[G.KEYS.sharpener] == 'cas' and math.abs(store[G.KEYS.temporal] - 0.7) < 1e-6)
check('our own preset field follows (onChange ran)', store[G.KEYS.preset] ~= nil)
S.applyPreset('balanced')
check('balanced: SMAA High, no sharpening', store[G.KEYS.mode] == 'smaa' and store[G.KEYS.sharpener] == 'off')

-- reset puts the defaults back on a tab
S.reset(M.MOD, 'look')
check('reset', store[Lk.KEYS.preset] == 'off' and store[Lk.KEYS.contrast] == 0 and store[Lk.KEYS.vignette] == 0)

-- without the registry nothing happens; the old groups can be cleaned out with no game
_G.slrr_settings = nil
check('no registry: nothing, no error', M.register() == false)
FS = { getUserPath = function() return '/u/' end, getFileRealPath = function() return '/elsewhere/layout.json' end }
M.removeOldGroups()
print('gfxmenu test passed')
