-- SLRR Garage: where the garages are.
-- Every site is described along its drive-in axis: `spot` is where the car ends up parked,
-- `dir` points INTO the garage, and the distances below are measured along that axis
-- (negative = outside, towards the street).

local M = {}

M.sites = {
  west_coast_usa = {
    {
      id = "belascoCityGarage",
      name = "Belasco City Garage",
      spot = vec3(904.487, -546.274, 163.65),
      dir = vec3(0.99281, -0.11969, 0),
      doorDist = -7.0,        -- door plane
      approachDist = -21.0,   -- where the drive-in animation starts
      triggerNear = -9.0,     -- auto-enter band in front of the door (along the axis)
      triggerFar = -17.0,
      triggerHalfWidth = 4.0,
      halfWidth = 5.4,        -- interior half width
      backDist = 5.6,         -- back wall
      ceiling = 4.5,
      -- the way out is the side door: ahead, a quarter turn to the left, and through it
      exitTurnAlong = 4.0,    -- where the turn starts (along the axis)
      exitRadius = 6.0,       -- radius of the turn; the door is centred on exitTurnAlong + exitRadius
      exitLeft = 21.5,        -- how far left of the axis the drive out ends
      exitClear = 17.5,       -- left of this the car is outside
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
    { id = "belascoAuto", name = "Belasco Auto", trade = "Interiors, trim and accessories",
      pos = vec3(-696.7, 799.3, 74.8),
      sells = { "interior", "paint", "body/plates", "body/electrics", "body/misc", "body/shells" } },
  },
}

function M.getShops()
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  return level and M.shops[level] or {}
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
