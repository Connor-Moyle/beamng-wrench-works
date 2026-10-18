// Tests slrr/graphics.lua's plan (what should be on, from the settings and the player's anti-aliasing) outside the game. Needs fengari:  node tools/graphics_test.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const file = path.join(__dirname, '..', 'mod/lua/ge/extensions/slrr/graphics.lua').split(path.sep).join('/');
const test = `
local G = dofile(${JSON.stringify(file)})
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
local function near(a, b) return math.abs(a - b) < 1e-4 end
local p = G.plan({})
check('everything is the games own by default', p.mode == 'game' and p.base == nil and not p.ultra and not p.hq and not p.temporal and p.sharpener == 'off')
p = G.plan({ mode = 'nonsense', sharpener = 'nonsense' })
check('unknown values fall back', p.mode == 'game' and p.sharpener == 'off')
p = G.plan({ mode = 'off' })
check('off', p.base == 'off' and not p.ultra)
p = G.plan({ mode = 'fxaa' })
check('fxaa', p.base == 'fxaa' and not p.hq)
p = G.plan({ mode = 'fxaaHQ' })
check('fxaa hq', p.base == 'fxaa' and p.hq and not p.ultra)
p = G.plan({ mode = 'smaa', predication = true })
check('smaa high has no ultra and no predication', p.base == 'smaa' and not p.ultra and not p.predication)
p = G.plan({ mode = 'smaaUltra' })
check('ultra, predication on unless switched off', p.base == 'smaa' and p.ultra and p.predication and not p.temporal)
check('predication off', not G.plan({ mode = 'smaaUltra', predication = false }).predication)
p = G.plan({ mode = 'smaaUltraTemporal', temporal = 1 })
check('temporal mode', p.ultra and p.temporal and near(p.temporalWeight, 0.95))
check('temporal weight range', near(G.plan({ mode = 'smaaUltraTemporal', temporal = 0 }).temporalWeight, 0.6) and near(G.plan({ mode = 'smaaUltraTemporal', temporal = 9 }).temporalWeight, 0.95))
check('temporal default amount', near(G.plan({ mode = 'smaaUltraTemporal' }).temporalWeight, 0.6 + 0.35 * 0.7))
p = G.plan({ sharpener = 'nis', strength = 0.7 })
check('sharpener with strength', p.sharpener == 'nis' and p.strength == 0.7)
check('sharpener default strength 0.4', G.plan({ sharpener = 'cas' }).strength == 0.4)
check('strength is clamped', G.plan({ sharpener = 'cas', strength = 3 }).strength == 1 and G.plan({ sharpener = 'cas', strength = -1 }).strength == 0)
check('strength 0 is no sharpening', G.plan({ sharpener = 'rcas', strength = 0 }).sharpener == 'off')
check('sharpening is independent of the mode', G.plan({ mode = 'game', sharpener = 'rcas' }).sharpener == 'rcas')
-- every mode, sharpener and preset has a note and a label; presets only set known settings
for _, list in ipairs({ G.MODES, G.SHARPENERS, G.PRESETS }) do
  for _, o in ipairs(list) do check('note for ' .. o.id, type(o.note) == 'string' and #o.note > 10 and type(o.label) == 'string') end
end
local known = { mode = true, predication = true, temporal = true, edgeAA = true, spec = true, sharpener = true, strength = true }
for _, pr in ipairs(G.PRESETS) do
  for k, v in pairs(pr.values or {}) do check('preset key ' .. k, known[k]) end
  if pr.values then
    local pl = G.plan(pr.values)
    check('preset ' .. pr.id .. ' picks real modes', pl.mode == pr.values.mode and pl.sharpener == pr.values.sharpener)
  end
end
check('preset values', G.presetValues('custom') == nil and G.presetValues('nope') == nil and G.presetValues('balanced').mode == 'smaaUltra')
check('unavailable list', #G.UNAVAILABLE >= 5 and G.unavailableText():find('DLSS') ~= nil and G.unavailableText():find('FSR 2') ~= nil)
-- RCAS: full strength is AMD's sharpest (no attenuation), none at 0 is 2 stops down
check('rcas lobe', near(G.rcasLobe(1), 1) and near(G.rcasLobe(0), 0.25) and near(G.rcasLobe(0.5), 0.5))
-- NIS: NVSharpenUpdateConfig at the default 50 %
local c = G.nisConfig(0.5)
check('nis at 50 %', near(c.strMin, 0.4) and near(c.strScale, 1.2) and near(c.limMin, 0.14) and near(c.limScale, 0.36) and near(c.startY, 0.45) and near(c.scaleY, 1 / 0.45) and near(c.ratioNorm, 0.125))
c = G.nisConfig(1)
check('nis at 100 %', near(c.strMin, 0.4 + 0.5 * 1.25 * 1.2) and near(c.strMin + c.strScale, 1.6 + 0.5 * 1.25 * 1.8))
check('nis at 0 % never goes negative', G.nisConfig(0).strMin == 0 and G.nisConfig(0).limMin >= 0.1)
-- the options as the game's settings keep them
local store = {}
local function get(key, default) local v = store[key]; if v == nil then return default end return v end
local o = G.readOptions(get)
check('defaults from empty settings', o.preset == 'custom' and o.mode == 'game' and o.predication == true and o.temporal == 0.7 and o.edgeAA == false and o.sharpener == 'off' and o.strength == 0.4)
check('specular default off, clamped', o.spec == 0 and G.plan({ spec = 0.5 }).spec == 0.5 and G.plan({ spec = 9 }).spec == 1 and G.plan({}).spec == 0)
check('presets: smooth 0.5, max 0.7, balanced 0', G.presetValues('smooth').spec == 0.5 and G.presetValues('max').spec == 0.7 and (G.presetValues('balanced').spec or 0) == 0)
check('edge aa in the plan', G.plan({ edgeAA = true }).edgeAA == true and G.plan({}).edgeAA == false)
store[G.KEYS.mode] = 'smaaUltra'; store[G.KEYS.sharpener] = 'cas'; store[G.KEYS.predication] = false
o = G.readOptions(get)
check('read back', o.mode == 'smaaUltra' and o.sharpener == 'cas' and o.predication == false)
check('a changed preset is custom', G.matchPreset(o) == 'custom')
local balanced = G.presetValues('balanced')
local filled = {}
for name, v in pairs(G.DEFAULTS) do filled[name] = balanced[name] ~= nil and balanced[name] or v end
check('a preset is recognised from its values', G.matchPreset(filled) == 'balanced')
filled.strength = 0.9
check('and not once one differs', G.matchPreset(filled) == 'custom')
for _, pr in ipairs(G.PRESETS) do
  if pr.values then
    local f = {}
    for name, v in pairs(G.DEFAULTS) do f[name] = pr.values[name] ~= nil and pr.values[name] or v end
    check('each preset matches itself: ' .. pr.id, G.matchPreset(f) == pr.id)
  end
end
check('the status works with no renderer', G.status().sharpener == 'off' and G.status().tsmOn == false)
print('graphics test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }

// two mods' groups side by side in one layout: each is replaced and removed by its own marker, and stripAll gives the game's text back
{
  const base = JSON.stringify({ items: [{ categoryId: 'graphics', items: [{ setting: 'GraphicAntialiasType', options: [] }, { setting: 'Other' }] }] });
  const extDir = path.join(__dirname, '..', 'mod', 'lua', 'ge', 'extensions').split(path.sep).join('/');
  const L4 = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L4);
  lua.lua_pushstring(L4, to_luastring(base));
  lua.lua_setglobal(L4, to_luastring('BASE'));
  const code = `package.path = ${JSON.stringify(extDir + '/?.lua;')} .. package.path
    local L = require('slrr/optionsLayout')
    local a = assert(L.patchText(BASE, 'a-v1', { label = 'A', items = {} }, 'GraphicAntialiasType'))
    local ab = assert(L.patchText(a, 'b-v1', { label = 'B', items = {} }, 'GraphicAntialiasType'))
    local ab2 = assert(L.patchText(ab, 'a-v1', { label = 'A2', items = {} }, 'GraphicAntialiasType'))
    OK = (L.stripAll(ab) == BASE) and (L.strip(ab, 'a-v1') == L.patchText(BASE, 'b-v1', { label = 'B', items = {} }, 'GraphicAntialiasType')) and (L.stripAll(ab2) == BASE)
      and select(2, ab2:gsub('"_slrr"', '')) == 2 and ab2:find('A2', 1, true) ~= nil and not ab2:find('"A"', 1, true)`;
  if (lauxlib.luaL_dostring(L4, to_luastring(code)) !== lua.LUA_OK) { console.error('two groups: ' + to_jsstring(lua.lua_tostring(L4, -1))); process.exit(1); }
  lua.lua_getglobal(L4, to_luastring('OK'));
  if (!lua.lua_toboolean(L4, -1)) { console.error('two groups: groups did not coexist'); process.exit(1); }
  JSON.parse(base);
  console.log('layout groups coexist ok');
}
