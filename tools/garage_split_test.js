// Tests the pieces taken out of slrr/garage.lua (garageRoute, garageDyno, garageDrivers, the console helpers in garageSites) outside the game, and that every garage*.lua still compiles.
// Needs fengari:  node tools/garage_split_test.js
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const dir = path.join(__dirname, '..', 'mod/lua/ge/extensions/slrr').split(path.sep).join('/');
const files = fs.readdirSync(dir).filter((f) => /^garage.*\.lua$/.test(f));
const test = `
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local dir = ${JSON.stringify(dir)}
for _, f in ipairs({ ${files.map((f) => JSON.stringify(f)).join(", ")} }) do
  local fn, err = loadfile(dir .. '/' .. f)
  check('compiles: ' .. f .. ' ' .. tostring(err), fn)
end

-- a minimal vec3 and the game's clamp
local V = {}
V.__index = V
local function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, V) end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return vec3(-a.x, -a.y, -a.z) end
V.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end return vec3(a.x * b, a.y * b, a.z * b) end
function V:length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function V:dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
_G.vec3 = vec3
_G.clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
_G.log = function() end
package.path = dir .. '/../?.lua;' .. package.path
package.loaded['slrr/garageSettings'] = { get = function(k) return k == 'driveSpeed' and 1 or nil end }
package.loaded['slrr/garageSites'] = {
  toAxis = function(s, p) return (p - s.spot):dot(s.dir) end,
  point = function(s, along, left, up) return s.spot + s.dir * along + vec3(-s.dir.y, s.dir.x, 0) * left + vec3(0, 0, up or 0) end,
}
local R = dofile(dir .. '/garageRoute.lua')

local site = { spot = vec3(10, 20, 0), dir = vec3(1, 0, 0), doorDist = -7, backDoorDist = 6, halfWidth = 3.5, backDist = 5, exit = 'reverse',
  exitTurnAlong = 1, exitRadius = 3, exitLeft = 9, exitClear = 6, sideDoorLeft = 3 }

-- the timed path: starts at the first point at t=0, ends at the last point, time only goes forward, the end time is returned
local pts = { vec3(0, 0, 0), vec3(10, 0, 0), vec3(10, 5, 0) }
local path, dur = R.buildDrivePath(pts)
check('path starts at the first point at t=0', near(path[1].x, 0) and near(path[1].t, 0))
check('path ends at the last point', near(path[#path].x, 10) and near(path[#path].y, 5) and near(path[#path].t, dur))
for i = 2, #path do check('time only goes forward', path[i].t >= path[i - 1].t) end
check('15 m at 5.2 m/s with 2.4 m/s2 takes about 4.8 s', math.abs(dur - (15 / 5.2 + 5.2 / 2.4)) < 0.01)

-- the three entries and the exits
local c = vec3(site.spot.x - 9, 20, 0)
local e = R.entry(site, false, 2, c)
check('front door entry parks facing in', e.parkDir == site.dir and e.startDir == site.dir and #e.points == 2)
local eb = R.entry({ spot = site.spot, dir = site.dir, doorDist = -7, backDoorDist = 6, exit = 'through' }, true, 2, vec3(site.spot.x + 12, 20, 0))
check('back door entry parks facing the front door', near(eb.parkDir.x, -1) and #eb.points == 2)
local es = R.entry(site, true, 2, vec3(10, 29, 0))
site.exit = 'side'
es = R.entry(site, true, 2, vec3(10, 29, 0))
check('side door entry curves round (10 points) and parks facing the front door', #es.points == 10 and near(es.parkDir.x, -1))
local xs = R.exit(site, false, 2)
check('side exit: 10 route points and the car is outside once past the clearance', #xs.points == 10 and xs.isOutside(vec3(10, 27, 0)) and not xs.isOutside(vec3(10, 21, 0)))
site.exit = 'reverse'
local xr = R.exit(site, false, 2)
check('reverse exit goes out backwards, nose still to the garage', near(xr.endDir.x, 1) and xr.isOutside(vec3(0, 20, 0)) and not xr.isOutside(vec3(10, 20, 0)))
local xt = R.exit({ spot = site.spot, dir = site.dir, doorDist = -7, backDoorDist = 6, exit = 'through' }, false, 2)
check('through exit leaves by the back door', xt.endDir.x == 1 and xt.isOutside(vec3(20, 20, 0)))
check('the film camera is a point in the garage', R.filmSpot(site, false).z == 1.5 and R.filmSpot(site, true).z == 1.5)

-- the dyno: a first run is the baseline and is written once, a later run is drawn over it
local written, store = 0, {}
_G.shallowcopy = function(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
_G.getObjectByID = function(id) return { getJBeamFilename = function() return 'pessima' end } end
_G.jsonReadFile = function() return store.f end
_G.jsonWriteFile = function(_, t) store.f = t written = written + 1 end
local sent = {}
_G.guihooks = { trigger = function(n, d) sent[#sent + 1] = d end }
_G.extensions = { hook = function() end }
package.loaded['slrr/garageParts'] = { getFeatures = function() return { dyno = true } end }
local D = dofile(dir .. '/garageDyno.lua')
D.onDyno(5, { maxPower = 100, maxTorque = 200 }, 5)
check('first run is saved as baseline and sent without one', written == 1 and sent[1].baseline == nil)
D.onDyno(5, { maxPower = 120, maxTorque = 210 }, 5)
check('a better run is sent with the baseline, nothing written', written == 1 and sent[2].baseline.maxPower == 100)
D.onDyno(6, { maxPower = 1 }, 5)
check('another car is ignored', #sent == 2)
D.pin()
check('pin makes the last run the baseline', written == 2 and store.f.pessima.maxPower == 120 and #sent == 3 and sent[3].baseline == nil)

-- the drivers panel: a pick goes to Drivers' own saved store (the global look, the default driver), never to a per-car copy that a respawn loses
local look, drv = {}, {}
_G.slrrDrivers = {
  setAppearance = function(vid, l) look[#look + 1] = { vid = vid, l = l } end,
  setDriver = function(vid, d) drv[#drv + 1] = 'car:' .. tostring(vid) .. ':' .. tostring(d) end,
  setDefaultDriver = function(d) drv[#drv + 1] = 'default:' .. tostring(d) end,
}
local Dr = dofile(dir .. '/garageDrivers.lua')
Dr.pickOutfit({ helmet = true })
check('an outfit pick is the global look (vehicle nil), saved by Drivers', #look == 1 and look[1].vid == nil and look[1].l.helmet == true)
Dr.pickDriver(7, 'racer')
check('a driver pick is for this car now and the saved default', drv[1] == 'car:7:racer' and drv[2] == 'default:racer')
check('WW applies no look, mode or pedestrian options by itself any more', Dr.apply == nil and Dr.applyAppearance == nil)

-- the settings the garage lists: the driver look, the driver mode and the pedestrian options are retired (hidden, keys kept so old files load)
package.loaded['slrr/garageSettings'] = nil
_G.jsonReadFile = function() return { driverHelmet = true, driverMode = 'still', pedAmount = 'high', driveSpeed = 1.5 } end
_G.jsonWriteFile = function() end
_G.deepcopy = function(t) if type(t) ~= 'table' then return t end local o = {} for k, v in pairs(t) do o[k] = _G.deepcopy(v) end return o end
local S = dofile(dir .. '/garageSettings.lua')
local listed = {}
for _, d in ipairs(S.describe()) do
  listed[d.key] = true
  check('no retired setting is listed: ' .. d.key, d.group ~= 'Driver look' and d.key ~= 'driverMode' and d.ped == nil)
end
check('the other settings are still listed', listed.driveSpeed and listed.carRadio)
check('old files still load: the retired keys exist and keep their values, the others too', S.get('driverHelmet') == true and S.get('pedAmount') == 'high' and S.get('driveSpeed') == 1.5)
print('garage split test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
