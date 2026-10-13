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
      exitDist = -15.0,       -- where the car is put when leaving
    },
  },
}

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
