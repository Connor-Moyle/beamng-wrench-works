-- Wrench Works: the routes the car drives in and out of a garage, and where the camera stands to film them.
-- Pure geometry on a site (slrr/garageSites) and the visit's door (viaSide); garage.lua runs them. It lives in its own file
-- because garage.lua is near LuaJIT's limit of 200 top-level locals (tools/locals_check.js).

local sites = require('slrr/garageSites')
local settings = require('slrr/garageSettings')

local M = {}

local FILM_SPEED = 5.2          -- m/s the car rolls in and out at
local FILM_ACCEL = 2.4

-- points: world positions the front of the car passes through. Returns a timed path for the
-- script AI (ease up to FILM_SPEED, ease down to a stop) and how long it takes.
function M.buildDrivePath(points)
  local lengths, total = {}, 0
  for i = 2, #points do
    lengths[i] = (points[i] - points[i - 1]):length()
    total = total + lengths[i]
  end
  local FILM_SPEED = FILM_SPEED * settings.get('driveSpeed')
  local accelDist = FILM_SPEED * FILM_SPEED / (2 * FILM_ACCEL)
  local function timeAt(s)
    local a = FILM_ACCEL
    local d1 = math.min(accelDist, total / 2)
    if s <= d1 then return math.sqrt(2 * s / a) end
    local t1 = math.sqrt(2 * d1 / a)
    local vPeak = a * t1
    local cruise = total - 2 * d1
    if s <= d1 + cruise then return t1 + (s - d1) / vPeak end
    local rem = math.max(0, total - s)
    return t1 + cruise / vPeak + (t1 - math.sqrt(2 * rem / a))
  end
  local path = {}
  local step, done = 0.75, 0
  for i = 2, #points do
    local len = lengths[i]
    local s = 0
    while s < len do
      local p = points[i - 1] + (points[i] - points[i - 1]) * (s / len)
      path[#path + 1] = { x = p.x, y = p.y, z = p.z, t = timeAt(done + s) }
      s = s + step
    end
    done = done + len
  end
  local last = points[#points]
  path[#path + 1] = { x = last.x, y = last.y, z = last.z, t = timeAt(total) }
  return path, timeAt(total)
end

-- A garage has a front door on its axis and, most of them, a second one: at the side, reached
-- by a quarter turn to the left, or at the back, straight on. A visit comes in through one
-- and leaves through the other; with a single door the car backs out.
local function leftOf(s) return vec3(-s.dir.y, s.dir.x, 0) end
local function axisPoint(s, along, left) return s.spot + s.dir * along + leftOf(s) * left + vec3(0, 0, 0.3) end

-- where the front of the car goes between the parking spot and the forecourt of a side door
local function sideRoute(site, half, farLeft)
  local turn, radius = site.exitTurnAlong, site.exitRadius
  local points = { axisPoint(site, half, 0) }
  if turn > half + 0.5 then points[#points + 1] = axisPoint(site, turn, 0) end
  for i = 1, 8 do
    local a = (i / 8) * math.pi * 0.5
    points[#points + 1] = axisPoint(site, turn + radius * math.sin(a), radius - radius * math.cos(a))
  end
  points[#points + 1] = axisPoint(site, turn + radius, farLeft)
  return points
end

-- the drive in: { points, startPos, startDir, parkDir }. It starts where the car is (c, its centre), in the doorway.
function M.entry(site, viaSide, half, c)
  local left = leftOf(site)
  if viaSide and site.exit == 'side' then
    -- in through the side door: round to the right, and stop facing the front door
    local startLeft = clamp((c - site.spot):dot(left), site.sideDoorLeft + half - 1, site.exitLeft + 3)
    local turn, radius = site.exitTurnAlong, site.exitRadius
    local points = { axisPoint(site, turn + radius, startLeft - half) }
    for i = 7, 0, -1 do
      local a = (i / 8) * math.pi * 0.5
      points[#points + 1] = axisPoint(site, turn + radius * math.sin(a), radius - radius * math.cos(a))
    end
    points[#points + 1] = axisPoint(site, -half, 0)
    return { points = points, startPos = axisPoint(site, turn + radius, startLeft) - vec3(0, 0, 0.25), startDir = -left, parkDir = -site.dir }
  elseif viaSide then
    -- in through the back door, straight to the spot, facing the front door
    local startAlong = clamp(sites.toAxis(site, c), site.backDoorDist + half - 1, site.backDoorDist + 12)
    return {
      points = { axisPoint(site, startAlong - half, 0), axisPoint(site, -half, 0) },
      startPos = sites.point(site, startAlong, 0, 0.05), startDir = -site.dir, parkDir = -site.dir,
    }
  end
  local startAlong = clamp(sites.toAxis(site, c), site.doorDist - 12, site.doorDist - half + 1)
  return {
    points = { axisPoint(site, startAlong + half, 0), axisPoint(site, half, 0) },
    startPos = sites.point(site, startAlong, 0, 0.05), startDir = site.dir, parkDir = site.dir,
  }
end

-- the drive out: { points, isOutside(carCentre), endPos, endDir }
function M.exit(site, viaSide, half)
  local left = leftOf(site)
  if viaSide or site.exit == 'reverse' then
    -- straight out of the front door: nose first for a car that came in the other way, backwards
    -- for one that came in by this door (the script driver reverses towards points behind it)
    local far = site.doorDist - 11
    local backing = not viaSide
    return {
      points = { axisPoint(site, -half, 0), axisPoint(site, far, 0) },
      isOutside = function(c) return (c - site.spot):dot(site.dir) < site.doorDist - 2.5 end,
      endPos = sites.point(site, backing and (far - half) or (far + half), 0, 0.05), endDir = backing and site.dir or -site.dir,
    }
  elseif site.exit == 'through' then
    local far = site.backDoorDist + 11
    return {
      points = { axisPoint(site, half, 0), axisPoint(site, far, 0) },
      isOutside = function(c) return (c - site.spot):dot(site.dir) > site.backDoorDist + 2.5 end,
      endPos = sites.point(site, far - half, 0, 0.05), endDir = site.dir,
    }
  end
  local points = sideRoute(site, half, site.exitLeft)
  return {
    points = points,
    isOutside = function(c) return (c - site.spot):dot(left) > site.exitClear end,
    endPos = points[#points] - left * half - vec3(0, 0, 0.25), endDir = left,
  }
end

-- where the camera stands to film the drive in: across the room from the door the car uses
function M.filmSpot(site, viaSide)
  local side = math.min(site.halfWidth - 0.9, 2.4) * (site.filmSide or 1)
  if viaSide and site.exit == 'side' then
    return sites.point(site, site.exitTurnAlong - 0.6, side, 1.55)       -- right-hand wall, facing the side door
  elseif viaSide then
    return sites.point(site, math.max(site.doorDist + 1.4, -6.5), -side, 1.5)   -- on the front-door side, facing the back door
  end
  return sites.point(site, site.filmAlong or math.min(site.backDist - 0.6, 6.5), -side, 1.5)       -- on the far side, facing the front door
end

return M
