// Tests slrr/camera.lua (plan, presets, letterbox size, the game's blur and depth of field set and put back exactly, photo mode left alone, options group) outside the game.
// Needs fengari:  node tools/camera_test.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const ext = path.join(__dirname, '..', 'mod', 'lua', 'ge', 'extensions').split(path.sep).join('/');
const test = `
package.path = ${JSON.stringify(ext + '/?.lua;')} .. package.path
local K = dofile(${JSON.stringify(ext + '/slrr/camera.lua')})
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
local function near(a, b) return math.abs(a - b) < 1e-4 end
log = function() end

-- plan
check('defaults inactive', not K.plan({}).active and not K.plan(nil).active)
check('each control activates', K.plan({ blur = 0.1 }).active and K.plan({ dof = 0.1 }).active and K.plan({ letterbox = '2.39' }).active)
check('off letterbox is no ratio', K.plan({ letterbox = 'off' }).ratio == 0)
local p = K.plan({ blur = 9, dof = -3 })
check('clamped', p.blur == 2 and p.dof == 0)
-- letterbox only: a ratio wider than the screen gets bars top and bottom, anything else none (16:9 and 21:9 x each ratio)
local function bars(r, a, want) return math.abs(K.barHeight(r, a) - want) < 1e-3 end
check('2.39 on 16:9: 12.8%', bars(2.39, 16 / 9, 0.1277))
check('2.0 on 16:9: 5.6%', bars(2.0, 16 / 9, 0.0556))
check('1.85 on 16:9: 1.9%', bars(1.85, 16 / 9, 0.0193))
check('2.39 on 21:9: 1.2%', bars(2.39, 21 / 9, 0.0119))
check('2.0 on 21:9: none', K.barHeight(2.0, 21 / 9) == 0)
check('1.85 on 21:9: none', K.barHeight(1.85, 21 / 9) == 0)
check('same ratio and bad input: none', K.barHeight(2, 2) == 0 and K.barHeight(nil, 2) == 0 and K.barHeight(2, 0) == 0)

-- presets
local ids = {}
for _, pr in ipairs(K.PRESETS) do ids[pr.id] = true check('note ' .. pr.id, #pr.note > 10) end
check('presets', ids.off and ids.subtle and ids.film and ids.dramatic and ids.custom)
check('off inactive', not K.plan(K.presetValues('off')).active)
for _, id in ipairs({ 'subtle', 'film', 'dramatic' }) do
  check(id .. ' active', K.plan(K.presetValues(id)).active)
  check(id .. ' matches itself', K.matchPreset(K.presetValues(id)) == id)
end
local v = K.presetValues('film'); v.letterbox = '1.85'
check('changed is custom', K.matchPreset(v) == 'custom')

-- settings flow
local store = {}
settings = { getValue = function(key, d) local x = store[key] if x == nil then return d end return x end, setValue = function(key, x) store[key] = x end }
K.ensureDefaults()
check('defaults written', store.slrrCamPreset == 'off' and store.slrrCamLetterbox == 'off')
store.slrrCamPreset = 'film'
K.onSettingsChanged()
check('preset fills', near(store.slrrCamBlur, 1) and store.slrrCamLetterbox == '2.39')
store.slrrCamBlur = 0.3
K.onSettingsChanged()
check('change makes custom', store.slrrCamPreset == 'custom')

-- the game's effects: fakes
local function fx(extra) local o = { on = false } o.enable = function(s) s.on = true end o.disable = function(s) s.on = false end o.isEnabled = function(s) return s.on end
  for k, x in pairs(extra or {}) do o[k] = x end return o end
local mb = fx({ strength = 0.7, on = true })
local dofFx = fx({})
local objs = { PostFxMotionBlur = mb, DOFPostEffect = dofFx }
scenetree = { findObject = function(n) return objs[n] end }
createObject = function() local base = fx({ getRenderTargetSize = function() return { x = 3440, y = 1440 } end, setShaderConst = function() end, registerObject = function(s, n) objs[n] = s end, setField = function() end, inheritParentFields = function() end })
  return setmetatable({}, { __index = base, __newindex = function(t, k, x) if k ~= 'isEnabled' then base[k] = x end end }) end   -- (the engine's isEnabled is a field and a method; enable/disable act on base)
local reg = { ['$DOFPostFx::Enable'] = false, ['$DOFPostFx::EnableAutoFocus'] = false, ['$DOFPostFx::BlurMax'] = 0.25 }
VariableRegistry = { get = function(k) return reg[k] end, set = function(k, x) reg[k] = x end }
local updates = 0
package.loaded['client/postFx/dof'] = { updateDOFSettings = function() updates = updates + 1 end }

K.apply({ blur = 1.2, dof = 0.6, letterbox = '2.0', preset = 'custom' })
check('blur set', mb.strength == 1.2 and mb.on)
check('dof set', reg['$DOFPostFx::Enable'] == true and reg['$DOFPostFx::EnableAutoFocus'] == true and reg['$DOFPostFx::BlurMax'] == 0.6 and updates > 0)
check('letterbox effect on', objs.SLRR_Cam_PostEffect and objs.SLRR_Cam_PostEffect.on)
-- photo mode opens: the game's values come back and stay while it is open
ui_photomode_shared = { S = { sessionActive = true } }
K.apply()
check('photo mode: values restored', mb.strength == 0.7 and reg['$DOFPostFx::Enable'] == false and reg['$DOFPostFx::BlurMax'] == 0.25 and not K.status().holding)
mb.strength = 1.9
K.apply()
check('photo mode: left alone', mb.strength == 1.9)
ui_photomode_shared.S.sessionActive = false
mb.strength = 0.7
K.apply()
check('after photo mode: ours again', mb.strength == 1.2 and K.status().holding)
-- off puts everything back exactly
K.apply({ blur = 0, dof = 0, letterbox = 'off' })
check('restored exactly', mb.strength == 0.7 and mb.on and reg['$DOFPostFx::Enable'] == false and reg['$DOFPostFx::EnableAutoFocus'] == false and reg['$DOFPostFx::BlurMax'] == 0.25 and not dofFx.on)
check('letterbox off', not objs.SLRR_Cam_PostEffect.on and not K.status().holding)
-- only blur: dof untouched
K.apply({ blur = 1, dof = 0, letterbox = 'off' })
check('blur only', mb.strength == 1 and reg['$DOFPostFx::BlurMax'] == 0.25)
K.unload()
check('unload restores', mb.strength == 0.7 and not K.status().holding)

print('camera test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
