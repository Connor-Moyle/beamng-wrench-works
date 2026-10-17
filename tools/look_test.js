// Tests slrr/look.lua (the colour grade's plan, presets, option handling and options-page group) outside the game. Needs fengari:  node tools/look_test.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const ext = path.join(__dirname, '..', 'mod', 'lua', 'ge', 'extensions').split(path.sep).join('/');
const test = `
package.path = ${JSON.stringify(ext + '/?.lua;')} .. package.path
local K = dofile(${JSON.stringify(ext + '/slrr/look.lua')})
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
local function near(a, b) return math.abs(a - b) < 1e-4 end

-- plan: neutral values are inactive; any one control makes it active; values are clamped
check('defaults are inactive', not K.plan({}).active and not K.plan(nil).active)
check('contrast activates', K.plan({ contrast = 0.1 }).active)
check('saturation activates (either way)', K.plan({ saturation = 0.1 }).active and K.plan({ saturation = -0.1 }).active)
check('warmth activates (either way)', K.plan({ warmth = 0.5 }).active and K.plan({ warmth = -0.5 }).active)
check('vignette activates', K.plan({ vignette = 0.2 }).active)
check('split activates', K.plan({ split = 0.2 }).active)
local p = K.plan({ contrast = 9, saturation = -9, warmth = 9, split = -1, vignette = 'x' })
check('values are clamped', p.contrast == 1 and p.saturation == -0.5 and p.warmth == 1 and p.split == 0 and p.vignette == 0)

-- presets: every one has a note; the real ones are active, Off is not; each matches itself and nothing else
local ids = {}
for _, pr in ipairs(K.PRESETS) do
  ids[pr.id] = true
  check('note for ' .. pr.id, type(pr.note) == 'string' and #pr.note > 10 and type(pr.label) == 'string')
end
check('the presets', ids.off and ids.natural and ids.cinematic and ids.vivid and ids.custom)
check('off is inactive', not K.plan(K.presetValues('off')).active)
for _, id in ipairs({ 'natural', 'cinematic', 'vivid' }) do
  check(id .. ' is active', K.plan(K.presetValues(id)).active)
  check(id .. ' matches itself', K.matchPreset(K.presetValues(id)) == id)
end
check('off matches the defaults', K.matchPreset(K.presetValues('off')) == 'off')
check('custom has no values', K.presetValues('custom') == nil)
local v = K.presetValues('natural'); v.vignette = 0.9
check('a changed preset is custom', K.matchPreset(v) == 'custom')
check('presets differ', K.presetValues('natural').contrast ~= K.presetValues('cinematic').contrast)

-- reading the options, with defaults for what is not set yet
local o = K.readOptions(function(key, default) if key == 'slrrLookContrast' then return 0.3 end return default end)
check('read', near(o.contrast, 0.3) and o.preset == 'off' and o.vignette == 0)

-- the settings flow: a preset fills the others; changing one makes it custom or the preset it equals
local store = {}
settings = { getValue = function(key, default) local v = store[key] if v == nil then return default end return v end, setValue = function(key, v) store[key] = v end }
scenetree = nil   -- (no engine here: apply does nothing)
log = function() end
K.ensureDefaults()
check('defaults written', store.slrrLookPreset == 'off' and store.slrrLookContrast == 0)
store.slrrLookPreset = 'cinematic'
K.onSettingsChanged()
check('preset fills the settings', near(store.slrrLookContrast, 0.35) and near(store.slrrLookVignette, 0.35) and near(store.slrrLookSplit, 0.5))
store.slrrLookVignette = 0.8
K.onSettingsChanged()
check('a change makes it custom', store.slrrLookPreset == 'custom')
store.slrrLookVignette = 0.35
K.onSettingsChanged()
check('back to the values: the preset again', store.slrrLookPreset == 'cinematic')
store.slrrLookPreset = 'off'
K.onSettingsChanged()
check('off clears the settings', store.slrrLookContrast == 0 and store.slrrLookVignette == 0 and store.slrrLookSplit == 0)

-- the options group: data in the game's item format, keyed by our marker, the settings keys in it
local G = dofile(${JSON.stringify(ext + '/slrr/graphics.lua')})
local text = require('slrr/optionsLayout').encodeJson(K.optionsGroup({ common = function(x) return x end, choiceItem = function(label, setting) return { label = label, setting = setting } end, sliderItem = function(label, setting) return { label = label, setting = setting } end }))
for _, key in pairs(K.KEYS) do check('setting in group: ' .. key, text:find(key, 1, true) ~= nil) end
check('marker', text:find('"_slrr":"look-v1"', 1, true) ~= nil)
-- both groups into a layout, then the look group again (replaced, not doubled), and the AA group stays
local LO = require('slrr/optionsLayout')
local base = '{"items":[{"categoryId":"graphics","items":[{"setting":"GraphicAntialiasType","options":[]},{"setting":"Other"}]}]}'
local t1 = assert(LO.patchText(base, 'look-v1', K.optionsGroup(G.builders), 'GraphicAntialiasType'))
local t2 = assert(G.patchLayoutText(t1))
local t3 = assert(LO.patchText(t2, 'look-v1', K.optionsGroup(G.builders), 'GraphicAntialiasType'))
OUT = t3
check('both groups there once', select(2, t3:gsub('"_slrr"', '')) == 2 and t3:find('Wrench Works: look', 1, true) ~= nil and t3:find('anti-aliasing and sharpening', 1, true) ~= nil)
check('stripAll gives the base back', LO.stripAll(t3) == base)
print('look test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
lua.lua_getglobal(L, to_luastring('OUT'));
JSON.parse(Buffer.from(lua.lua_tostring(L, -1)).toString('utf8'));   // valid JSON with both groups
console.log('look test: layout with both groups is valid JSON');
