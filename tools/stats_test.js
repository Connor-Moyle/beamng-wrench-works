// Tests slrr/garageStats.lua (what a part does, from its jbeam data) outside the game. Needs fengari:  node tools/stats_test.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const file = path.join(__dirname, '..', 'mod/lua/ge/extensions/slrr/garageStats.lua').split(path.sep).join('/');
const test = `
local S = dofile(${JSON.stringify(file)})
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
local function find(rows, label) for _, r in ipairs(rows) do if r.label == label then return r.value end end end

local engine = { mainEngine = { torque = { { 'rpm', 'torque' }, { 0, 0 }, { 1000, 107 }, { 4000, 193 }, { 5000, 197 }, { 6300, 179 }, { 9000, 40 } },
  idleRPM = 900, maxRPM = 6500, maxTorqueRating = 285, cylinderWallTemperatureDamageThreshold = 120 } }
local rows = S.of(engine, 112)
check('engine: peak power is torque x rpm / 9549 in hp, at the right rpm', find(rows, 'Peak power') == '158 hp at 6300 rpm')
check('engine: peak torque and where', find(rows, 'Peak torque') == '197 Nm at 5000 rpm')
check('engine: rev range', find(rows, 'Rev range') == '900 - 6500 rpm')
check('engine: strength and heat limit', find(rows, 'Strength') == 'rated for 285 Nm' and find(rows, 'Heat limit') == '120 C at the cylinder wall')
check('engine: weight last, and no spring rows', find(rows, 'Weight') == '112 kg' and rows[#rows].label == 'Weight' and not find(rows, 'Spring rate'))
engine.mainEngine.revLimiterRPM = 7200
check('a rev limiter beats the physical max', find(S.of(engine), 'Rev range') == '900 - 7200 rpm')

local turbo = { turbocharger = { wastegateStart = 14.5 } }
check('a turbo shows its boost', find(S.of(turbo, 6), 'Turbo') == 'up to 14.5 psi of boost' and find(S.of(turbo, 6), 'Weight') == '6.0 kg')

local spring = { beams = { { beamSpring = 5001000 }, { 'id1', 'id2' }, { beamSpring = 85000, beamDamp = 1200 } } }
local sr = S.of(spring, 3.5)
check('a spring: the soft rate, not the rigid beams', find(sr, 'Spring rate') == '85 N/mm' and find(sr, 'Damping') == '1200' and find(sr, 'Weight') == '3.5 kg')
local tyre = { pressureWheels = { { frictionCoef = 1.1 }, { frictionCoef = 1.35 } }, wheels = { { brakeTorque = 2000 } } }
local tr = S.of(tyre, 0)
check('a tyre: grip, brake torque; no weight when unknown', find(tr, 'Grip') == '1.35 friction' and find(tr, 'Brake torque') == '2000 Nm' and not find(tr, 'Weight'))
check('nothing known: nothing shown, no error', #S.of({}, nil) == 0 and #S.of(nil, 5) == 0 and #S.of({ mainEngine = {} }, nil) == 0)
print('stats test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
