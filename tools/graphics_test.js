// Tests slrr/graphics.lua's plan (what should be on, from the settings and the player's anti-aliasing) outside the game. Needs fengari:  node tools/graphics_test.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const file = path.join(__dirname, '..', 'mod/lua/ge/extensions/slrr/graphics.lua').split(path.sep).join('/');
const test = `
local G = dofile(${JSON.stringify(file)})
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
local p = G.plan({ ultra = true, sharpen = true, strength = 0.7 }, { aa = true, aaType = 'smaa' })
check('both on with SMAA', p.ultra and p.sharpen and p.strength == 0.7 and p.note == nil)
p = G.plan({ ultra = true, sharpen = true }, { aa = true, aaType = 'fxaa' })
check('Ultra waits for SMAA, sharpening does not', not p.ultra and p.sharpen and p.note ~= nil)
p = G.plan({ ultra = true }, { aa = false, aaType = 'smaa' })
check('no anti-aliasing at all: no Ultra', not p.ultra and p.note ~= nil)
p = G.plan({}, { aa = true, aaType = 'smaa' })
check('everything off by default', not p.ultra and not p.sharpen and p.note == nil)
check('default strength 0.4', G.plan({ sharpen = true }, {}).strength == 0.4)
check('strength is clamped', G.plan({ sharpen = true, strength = 3 }, {}).strength == 1 and G.plan({ sharpen = true, strength = -1 }, {}).strength == 0)
check('strength 0 is no sharpening', not G.plan({ sharpen = true, strength = 0 }, {}).sharpen)
check('only a true turns it on', not G.plan({ ultra = 'yes', sharpen = 1 }, { aa = true, aaType = 'smaa' }).ultra)
check('the status works with no renderer', G.status().ultra == false and G.status().sharpen == false)
print('graphics test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
