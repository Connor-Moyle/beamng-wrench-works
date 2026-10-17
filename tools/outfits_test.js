// Tests slrr/garageOutfits.lua (the Drivers tab's outfits) outside the game. Needs fengari:  node tools/outfits_test.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const file = path.join(__dirname, '..', 'mod/lua/ge/extensions/slrr/garageOutfits.lua').split(path.sep).join('/');
const test = `
local O = dofile(${JSON.stringify(file)})
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
local function find(list, id) for _, e in ipairs(list) do if e.id == id then return e end end end

local e = O.entries('hd_eric', { helmet = false }, true)
check('a helmet switch and every outfit, all on the Drivers tab under Outfit', find(e, 'helmet:toggle') and #e == 1 + #O.OUTFITS and e[1].tab == 'drivers' and e[2].group == 'Outfit')
check('the helmet says how it stands and can be switched', find(e, 'helmet:toggle').label == 'Helmet: off' and not find(e, 'helmet:toggle').disabled and O.entries('x', { helmet = true }, true)[1].label == 'Helmet: on')
local none = O.entries('hd_eric', {}, false)
check('a driver with no helmet mesh: the switch is off and says so', find(none, 'helmet:toggle').disabled and find(none, 'helmet:toggle').desc == 'this driver has no helmet')
check('no driver: nothing can be changed', find(O.entries(nil, {}, false), 'outfit:Racing red').disabled and find(O.entries(nil, {}, false), 'helmet:toggle').disabled)
check('the outfit in use is marked and cannot be picked again', find(O.entries('d', { shirt = { 0.75, 0.08, 0.08 }, trousers = { 0.1, 0.1, 0.12 } }, true), 'outfit:Racing red').disabled and find(O.entries('d', {}, true), 'outfit:Original').disabled and not find(O.entries('d', {}, true), 'outfit:Racing red').disabled)

local h = O.look('helmet:toggle', { helmet = false })
check('the helmet click turns it on, then off', h.helmet == true and O.look('helmet:toggle', { helmet = true }).helmet == false and O.look('helmet:toggle', nil).helmet == true)
local r = O.look('outfit:Racing red', {})
check('an outfit click gives the tints; Original clears them (false)', r.shirt[1] == 0.75 and r.trousers[3] == 0.12 and O.look('outfit:Original', {}).shirt == false and O.look('outfit:Original', {}).trousers == false)
check('anything else is not an outfit click', O.look('driver:x', {}) == nil and O.look('outfit:Nonsense', {}) == nil and O.look(nil, {}) == nil)
print('outfits test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
