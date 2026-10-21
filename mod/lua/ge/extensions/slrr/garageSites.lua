-- Wrench Works: where the garages are.
-- Every site is described along its drive-in axis: `spot` is where the car ends up parked,
-- `dir` points INTO the garage, and the distances below are measured along that axis
-- (negative = outside, towards the street).

local M = {}

-- A garage is described along its own axis: `spot` is where the car is parked (on the floor),
-- `dir` points from the front door into the building, and every distance is measured along
-- that axis from the spot. `exit` says how a car that came in by the front door leaves:
--   "side"    round a quarter turn to the left and out of a side door (you can come in there too)
--   "through" straight on, out of a back door on the same axis (you can come in there too)
--   "reverse" there is only the one door: the car backs out the way it came
M.sites = {
  utah = {
    {
      id = "utahServiceCenter",
      name = "Canyon Service Center",
      spot = vec3(796.44, -181.10, 144.43),       -- the one bay of the repair shop whose door stands open
      dir = vec3(-0.988, -0.154, 0),
      doorDist = -7.5,
      halfWidth = 3.4,
      backDist = 5.4,
      ceiling = 4.3,
      exit = "reverse",
      viewYaw = -40,          -- the bay's own columns stand ahead of the car: work from its rear quarter,
      filmAlong = 2.4,        -- and film the drive-in from beside the spot
    },
  },
  west_coast_usa = {
    {
      id = "belascoCityGarage",
      name = "Belasco City Garage",
      spot = vec3(904.487, -546.274, 163.65),
      dir = vec3(0.99281, -0.11969, 0),
      doorDist = -7.0,        -- front door plane
      halfWidth = 5.4,        -- the room the camera may move in: half its width,
      backDist = 5.6,         -- how far past the spot,
      ceiling = 4.5,          -- and its height
      exit = "side",
      exitTurnAlong = 4.0,    -- where the turn to the side door starts
      exitRadius = 6.0,       -- radius of the turn; the door is centred on exitTurnAlong + exitRadius
      sideDoorLeft = 14.8,    -- side door plane, this far left of the axis
      exitLeft = 21.5,        -- how far left of the axis the drive out ends
      exitClear = 17.5,       -- left of this the car is outside
    },
    {
      id = "alderDragwayGarage",
      name = "Alder Dragway Garage",
      spot = vec3(-203.3, -204.0, 118.81),      -- a tent: open towards the paddock, closed at the back
      dir = vec3(-0.5101, 0.8601, 0),
      doorDist = -7.0,
      halfWidth = 3.3,
      backDist = 4.2,
      ceiling = 4.8,
      exit = "reverse",
    },
    {
      id = "commercialGarage",
      name = "Industrial Garage",
      spot = vec3(-216.61, -26.93, 120.91),     -- the middle of the drive-through hall
      dir = vec3(-0.9915, -0.1302, 0),
      doorDist = -20.0,
      halfWidth = 3.8,
      backDist = 7.0,
      ceiling = 4.0,
      exit = "through",
      backDoorDist = 20.0,
    },
  },
}

-- Shops: real businesses on the map where parts can be bought over the counter - no delivery
-- charge, no waiting. Each sells its own trade; the keys are catalog chapters ("section/sub")
-- or whole sections. Stop on the marker to go in.
M.shops = {
  west_coast_usa = {
    { id = "torresTires", name = "Torres Tires", trade = "Wheels and tyres",
      pos = vec3(-582.1, 136.4, 101.2),
      sells = { "running/rims_f", "running/rims_r", "running/tyres_f", "running/tyres_r", "running/hubs" } },
    { id = "exhaustShop", name = "Belasco City Exhaust", trade = "Exhausts and intakes",
      pos = vec3(-572.7, 158.9, 100.5),
      sells = { "engine/exhaust", "engine/intake" } },
    { id = "fastAutomotive", name = "Fast Automotive", trade = "Engines and performance parts",
      pos = vec3(291.4, -142.4, 143.8),
      sells = { "engine/blocks", "engine/internals", "engine/forced", "engine/nitrous", "engine/management", "engine/transmission",
        "engine/clutch", "engine/cooling", "engine/fuel", "engine/mounts", "running/differentials", "running/driveline" } },
    { id = "smashAutoRepairs", name = "Smash Auto Repairs", trade = "Body panels and body kits",
      pos = vec3(-607.6, 120.9, 102.0),
      sells = { "body/bumpers_f", "body/bumpers_r", "body/hoods", "body/fenders", "body/doors", "body/trunk", "body/roof", "body/glass",
        "body/lights_f", "body/lights_r", "body/bulbs", "body/mirrors", "body/wings", "body/aero" } },
    { id = "jerryRigs", name = "Jerry Riggs", trade = "Suspension, brakes and chassis",
      pos = vec3(-82.5, -14.8, 119.7),
      sells = { "running/suspension_f", "running/suspension_r", "running/shocks_f", "running/shocks_r", "running/bars", "running/steering",
        "running/brakes_f", "running/brakes_r", "running/brakes", "body/chassis" } },
    { id = "rentabox", name = "Rent-A-Box Lock-up Sale", trade = "Used parts",
      pos = vec3(-143.0, 10.9, 121.4),
      yard = true },      -- sells a changing pick of everything, second-hand: cheap and bent
    { id = "belascoAuto", name = "Belasco Auto", trade = "Interiors, trim and accessories",
      pos = vec3(-696.7, 799.3, 74.8),
      sells = { "interior", "paint", "body/plates", "body/electrics", "body/misc", "body/shells" } },
  },
}

-- The doors of a garage: where each is (centre of the opening, on the floor) and which way is in.
function M.doors(site)
  local left = vec3(-site.dir.y, site.dir.x, 0)
  local doors = { { id = 'front', pos = site.spot + site.dir * site.doorDist, inward = site.dir } }
  if site.exit == 'side' then
    doors[2] = { id = 'second', pos = site.spot + site.dir * (site.exitTurnAlong + site.exitRadius) + left * site.sideDoorLeft, inward = -left }
  elseif site.exit == 'through' then
    doors[2] = { id = 'second', pos = site.spot + site.dir * site.backDoorDist, inward = -site.dir }
  end
  return doors
end

-- world position for a point `along` metres down the axis and `side` metres to the right
function M.point(site, along, side, up)
  local right = vec3(site.dir.y, -site.dir.x, 0)
  return site.spot + site.dir * along + right * (side or 0) + vec3(0, 0, up or 0)
end

-- axis coordinates (along, side) of a world position
function M.toAxis(site, pos)
  local rel = pos - site.spot
  local right = vec3(site.dir.y, -site.dir.x, 0)
  return rel:dot(site.dir), rel:dot(right), rel.z
end

----------------------------------------------------------------------------------------------
-- Garages and shops from files, so that nobody has to edit this one.
--
-- Any mod can bring a file  /wrench_works/sites/<anything>.json , and the player has one of
-- their own at  /settings/slrr_garage/sites.json  (slrr_garage.addGarageHere() and
-- addShopHere() write to it). Both look like this:
--
--   { "my_map": {
--       "garages": [ { "id": "myGarage", "name": "My Garage", "spot": [x, y, z], "dir": [dx, dy] } ],
--       "shops":   [ { "id": "myTyres", "name": "My Tyres", "trade": "Wheels and tyres",
--                      "pos": [x, y, z], "sells": ["running/rims_f", "running/tyres_f"] } ] } }
--
-- An entry with the id of one that already exists replaces it (that is how a point is moved),
-- and  "remove": true  takes it away. docs/adding_garages.md has every field.

local EXTRA_DIR = '/wrench_works/sites/'
M.USER_FILE = '/settings/slrr_garage/sites.json'

local GARAGE_DEFAULTS = { doorDist = -7, halfWidth = 3.5, backDist = 5, ceiling = 4.5, exit = 'reverse' }
local GARAGE_NUMBERS = { 'doorDist', 'halfWidth', 'backDist', 'ceiling', 'exitTurnAlong', 'exitRadius', 'sideDoorLeft',
  'exitLeft', 'exitClear', 'backDoorDist', 'viewYaw', 'filmAlong', 'filmSide' }
local SIDE_NEEDS = { 'exitTurnAlong', 'exitRadius', 'sideDoorLeft', 'exitLeft', 'exitClear' }

local function toVec(t)
  if type(t) ~= 'table' then return nil end
  local x, y, z = tonumber(t[1] or t.x), tonumber(t[2] or t.y), tonumber(t[3] or t.z) or 0
  if not x or not y then return nil end
  return vec3(x, y, z)
end

-- a garage as written in a file -> a site, or nil and what is wrong with it
local function readGarage(raw)
  if type(raw) ~= 'table' or type(raw.id) ~= 'string' then return nil, 'it has no "id"' end
  local spot, dir = toVec(raw.spot), toVec(raw.dir)
  if not spot then return nil, '"spot" must be [x, y, z]' end
  if not dir then return nil, '"dir" must be [x, y]' end
  dir.z = 0
  if dir:length() < 0.01 then return nil, '"dir" points nowhere' end
  local site = { id = raw.id, name = type(raw.name) == 'string' and raw.name or raw.id, spot = spot, dir = dir:normalized() }
  for key, value in pairs(GARAGE_DEFAULTS) do site[key] = value end
  for _, key in ipairs(GARAGE_NUMBERS) do
    if tonumber(raw[key]) then site[key] = tonumber(raw[key]) end
  end
  if raw.exit == 'side' or raw.exit == 'through' or raw.exit == 'reverse' then site.exit = raw.exit end
  -- a second door needs to know where it is; without that the car backs out of the first
  if site.exit == 'side' then
    for _, key in ipairs(SIDE_NEEDS) do
      if not site[key] then
        log('W', 'slrr_garage', string.format('garage "%s": exit "side" needs "%s"; the car will back out instead', site.id, key))
        site.exit = 'reverse'
        break
      end
    end
  elseif site.exit == 'through' and not site.backDoorDist then
    log('W', 'slrr_garage', string.format('garage "%s": exit "through" needs "backDoorDist"; the car will back out instead', site.id))
    site.exit = 'reverse'
  end
  if site.doorDist > -1 then site.doorDist = GARAGE_DEFAULTS.doorDist end     -- the door is in front of the spot, not behind it
  if type(raw.radio) == 'table' and tonumber(raw.radio[1]) and tonumber(raw.radio[2]) then
    site.radio = { tonumber(raw.radio[1]), tonumber(raw.radio[2]), tonumber(raw.radio[3]) or 1.2 }
  end
  return site
end

local function readShop(raw)
  if type(raw) ~= 'table' or type(raw.id) ~= 'string' then return nil, 'it has no "id"' end
  local pos = toVec(raw.pos)
  if not pos then return nil, '"pos" must be [x, y, z]' end
  local shop = { id = raw.id, name = type(raw.name) == 'string' and raw.name or raw.id,
    trade = type(raw.trade) == 'string' and raw.trade or 'Parts', pos = pos, yard = raw.yard == true or nil }
  if type(raw.sells) == 'table' and #raw.sells > 0 then
    shop.sells = {}
    for _, key in ipairs(raw.sells) do
      if type(key) == 'string' then shop.sells[#shop.sells + 1] = key end
    end
  elseif not shop.yard then
    shop.all = true         -- no list: it sells everything
  end
  return shop
end

local cache = {}      -- level -> { sites = {...}, shops = {...} }

local function merge(list, raws, read, what, file)
  for _, raw in ipairs(type(raws) == 'table' and raws or {}) do
    local id = type(raw) == 'table' and raw.id
    for i = #list, 1, -1 do
      if list[i].id == id then table.remove(list, i) end
    end
    if type(raw) ~= 'table' or raw.remove ~= true then
      local entry, why = read(raw)
      if entry then
        list[#list + 1] = entry
      else
        log('W', 'slrr_garage', string.format('%s: a %s was left out, %s', file, what, tostring(why)))
      end
    end
  end
end

local function forLevel()
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if not level then return { sites = {}, shops = {} } end
  local hit = cache[level]
  if hit then return hit end
  hit = { sites = {}, shops = {} }
  for _, site in ipairs(M.sites[level] or {}) do hit.sites[#hit.sites + 1] = site end
  for _, shop in ipairs(M.shops[level] or {}) do hit.shops[#hit.shops + 1] = shop end
  local files = FS:findFiles(EXTRA_DIR, '*.json', 0, false, false) or {}
  table.sort(files)
  files[#files + 1] = M.USER_FILE       -- the player's own file has the last word
  for _, file in ipairs(files) do
    local data = FS:fileExists(file) and jsonReadFile(file)
    local here = type(data) == 'table' and data[level]
    if type(here) == 'table' then
      merge(hit.sites, here.garages, readGarage, 'garage', file)
      merge(hit.shops, here.shops, readShop, 'shop', file)
    end
  end
  cache[level] = hit
  return hit
end

function M.getSites() return forLevel().sites end
function M.getShops() return forLevel().shops end

-- read the files again (a level was loaded, or one of them was just written)
function M.reload() cache = {} end

-- where a garage's radio stands: said in its entry (along, to the right, up), or on a bench in
-- the back corner
function M.radio(site)
  local r = site.radio
  if r then return M.point(site, r[1], r[2], r[3]) end
  return M.point(site, site.backDist - 0.5, -(site.halfWidth - 0.6), 1.2)
end

-- Add an entry to the player's own file (or replace the one with the same id) and use it at once.
-- kind: "garages" | "shops". Returns the file it went into.
function M.saveUserEntry(kind, entry)
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if not level or type(entry) ~= 'table' or not entry.id then return nil end
  local data = FS:fileExists(M.USER_FILE) and jsonReadFile(M.USER_FILE) or nil
  if type(data) ~= 'table' then data = {} end
  if type(data[level]) ~= 'table' then data[level] = {} end
  local list = type(data[level][kind]) == 'table' and data[level][kind] or {}
  for i = #list, 1, -1 do
    if type(list[i]) == 'table' and list[i].id == entry.id then table.remove(list, i) end
  end
  list[#list + 1] = entry
  data[level][kind] = list
  jsonWriteFile(M.USER_FILE, data, true)
  M.reload()
  return M.USER_FILE
end

-- the raw entry of one of the player's own garages or shops (to change a field of it)
function M.getUserEntry(kind, id)
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  local data = FS:fileExists(M.USER_FILE) and jsonReadFile(M.USER_FILE) or nil
  for _, entry in ipairs(type(data) == 'table' and level and type(data[level]) == 'table' and type(data[level][kind]) == 'table' and data[level][kind] or {}) do
    if type(entry) == 'table' and entry.id == id then return entry end
  end
end

-- the console tools of garage.lua (addGarageHere, setDoorHere, addShopHere): their helpers live here because garage.lua is near LuaJIT's limit of 200 top-level locals
function M.slug(name)
  return (tostring(name):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''))
end

function M.round3(x) return math.floor(x * 1000 + 0.5) / 1000 end

-- the floor under the player's car and the way it points
function M.standing()
  local v = getPlayerVehicle(0)
  if not v then return nil end
  local c = v:getSpawnWorldOOBB():getCenter()
  local drop = castRayStatic(c, vec3(0, 0, -1), 6)
  local dir = vec3(v:getDirectionVector())
  dir.z = 0
  dir:normalize()
  return vec3(c.x, c.y, c.z - math.min(drop, 6)), dir
end

function M.tell(text)
  log('I', 'slrr_garage', text)
  if ui_message then ui_message(text, 10, 'slrrGarage') end
  return text
end

return M
