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
local known = { gfxAaMode = true, gfxPredication = true, gfxTemporal = true, gfxSharpener = true, gfxSharpenStrength = true }
for _, pr in ipairs(G.PRESETS) do
  for k, v in pairs(pr.values or {}) do check('preset key ' .. k, known[k]) end
  if pr.values then
    local pl = G.plan({ mode = pr.values.gfxAaMode, predication = pr.values.gfxPredication, temporal = pr.values.gfxTemporal, sharpener = pr.values.gfxSharpener, strength = pr.values.gfxSharpenStrength })
    check('preset ' .. pr.id .. ' picks real modes', pl.mode == pr.values.gfxAaMode and pl.sharpener == pr.values.gfxSharpener)
  end
end
check('preset values', G.presetValues('custom') == nil and G.presetValues('nope') == nil and G.presetValues('balanced').gfxAaMode == 'smaaUltra')
check('unavailable list', #G.UNAVAILABLE >= 5 and G.unavailableText():find('DLSS') ~= nil and G.unavailableText():find('FSR 2') ~= nil)
-- RCAS: full strength is AMD's sharpest (no attenuation), none at 0 is 2 stops down
check('rcas lobe', near(G.rcasLobe(1), 1) and near(G.rcasLobe(0), 0.25) and near(G.rcasLobe(0.5), 0.5))
-- NIS: NVSharpenUpdateConfig at the default 50 %
local c = G.nisConfig(0.5)
check('nis at 50 %', near(c.strMin, 0.4) and near(c.strScale, 1.2) and near(c.limMin, 0.14) and near(c.limScale, 0.36) and near(c.startY, 0.45) and near(c.scaleY, 1 / 0.45) and near(c.ratioNorm, 0.125))
c = G.nisConfig(1)
check('nis at 100 %', near(c.strMin, 0.4 + 0.5 * 1.25 * 1.2) and near(c.strMin + c.strScale, 1.6 + 0.5 * 1.25 * 1.8))
check('nis at 0 % never goes negative', G.nisConfig(0).strMin == 0 and G.nisConfig(0).limMin >= 0.1)
check('the status works with no renderer', G.status().sharpener == 'off' and G.status().tsmOn == false)
print('graphics test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
