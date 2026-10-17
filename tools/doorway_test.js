// Tests slrr/garageDoorway.lua (where a garage's doorway is) outside the game. Needs fengari:  node tools/doorway_test.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const file = path.join(__dirname, '..', 'mod/lua/ge/extensions/slrr/garageDoorway.lua').split(path.sep).join('/');
const test = `
local D = dofile(${JSON.stringify(file)})
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
-- a car: the nose reaching the door
check('car at the door', D.carZone(0, 0) and D.carZone(-1, 2) and D.carZone(1, 0))
check('car well outside or beside is not', not D.carZone(-3, 0) and not D.carZone(0, 3) and not D.carZone(2, 0))
-- a walker: anywhere in front of and in the door, any speed or direction (the zone knows neither)
check('walker at the door and in it', D.footZone(0, 0, 3.4) and D.footZone(-2, 0, 3.4) and D.footZone(2, 0, 3.4))
check('walker at the side of a wide garage (half width 5.4)', D.footZone(0, 5.5, 5.4) and not D.footZone(0, 6.5, 5.4))
check('walker on a narrow garage still gets 3 m each side', D.footZone(0, 2.9, 1) and not D.footZone(0, 3.1, 1))
check('walker far in front or behind is not', not D.footZone(-3, 0, 3.4) and not D.footZone(3, 0, 3.4))
check('a missing width does not break it', D.footZone(0, 2, nil))
check('the walker zone is wider than the car zone', D.footZone(-2.4, 0, 3.4) and not D.carZone(-2.4, 0))
print('doorway test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
