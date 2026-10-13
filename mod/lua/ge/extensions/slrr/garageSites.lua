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

function M.getShops()
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  return level and M.shops[level] or {}
end

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

function M.getSites()
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  return level and M.sites[level] or {}
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

return M
