-- Wrench Works: the camera.
-- Nothing ever cuts. During the drive-in the camera stands at a fixed spot inside the garage
-- and turns to watch the car come in; once the car has stopped it leaves that spot in a
-- single short swing to the garage's working view - an orbit you turn with the right mouse
-- button and zoom with the wheel, with a soft follow. On the way out it stays where it is
-- and watches the car leave.

local M = {}

local sites = require('slrr/garageSites')

local min, max, sin, cos, rad, exp = math.min, math.max, math.sin, math.cos, math.rad, math.exp

local ORBIT_FOV = 60
local FILM_FOV = 50
local PITCH_MIN, PITCH_MAX = rad(-4), rad(62)
local PITCH_MIN_LIFT = rad(-24)     -- with the car on the lift you may look up at it from below
local WALL_MARGIN = 0.45
local SETTLE_TIME = 1.7             -- seconds for the swing from the film view to the working view

local active = false
local site
local getCarCenter
local carLength = 4.5

-- orbit state (yaw 0 looks along the garage axis, from the door towards the back wall)
local yaw, pitch, dist, fov = 0, 0, 5, ORBIT_FOV
local sYaw, sPitch, sDist, sFov = 0, 0, 5, ORBIT_FOV
local distMin, distMax = 2.5, 7
local focus, sFocus             -- point the camera looks at (nil = the car's centre)
local wallWeight = 1            -- 0 = ignore the garage walls (car still outside), 1 = stay inside
local wallTarget = 1
local filming = false
local settleT                   -- running time of the swing into the working view (nil = done)
local lift = false
local flip = 0                  -- 180 degrees when the car is parked facing the front door
local rate = 9                  -- how eagerly the smoothed values chase their targets
local lastDist = 5              -- how far from its target the camera really was last frame
local lastPos                   -- where the camera was last frame
local filmPos                   -- where the camera stands while a drive-in or drive-out is filmed

local function smooth(current, target, r, dt)
  return current + (target - current) * (1 - exp(-r * dt))
end

local function carCenter()
  return (getCarCenter and getCarCenter()) or (site and site.spot + vec3(0, 0, 0.6)) or vec3()
end

-- how far along its arm the camera may sit before it would leave the room (1 = all the way)
local function roomLimit(target, offset)
  if not site then
    local len = offset:length()
    if len < 0.01 then return 1 end
    local hit = castRayStatic(target, offset / len, len + WALL_MARGIN)
    if hit < len + WALL_MARGIN then return max(0.15, (hit - WALL_MARGIN) / len) end
    return 1
  end
  local tAlong, tSide, tUp = sites.toAxis(site, target)
  local oAlong, oSide = offset:dot(site.dir), offset:dot(vec3(site.dir.y, -site.dir.x, 0))
  local oUp = offset.z
  local k = 1
  local function limit(t, o, lo, hi)
    if o > 0 and t + o > hi then k = min(k, max(0, (hi - t) / o)) end
    if o < 0 and t + o < lo then k = min(k, max(0, (lo - t) / o)) end
  end
  limit(tAlong, oAlong, site.doorDist + WALL_MARGIN, site.backDist - WALL_MARGIN)
  limit(tSide, oSide, -site.halfWidth + WALL_MARGIN, site.halfWidth - WALL_MARGIN)
  limit(tUp, oUp, 0.25, site.ceiling - 0.35)
  return k
end

local function orbitOffset(y, p, d)
  local dir = site and site.dir or vec3(0, 1, 0)
  local right = vec3(dir.y, -dir.x, 0)
  -- the camera sits opposite to where it looks
  local flat = dir * (-cos(y)) + right * (-sin(y))
  return (flat * cos(p) + vec3(0, 0, sin(p))) * d
end

-- called by the camera mode every frame
function M.update(dt)
  if not active then return nil end
  dt = min(dt or 0.016, 0.1)

  if settleT then
    settleT = settleT + dt
    -- ease the chase rate up as the swing progresses, so it starts gently and still arrives
    rate = 1.4 + 7.6 * min(1, settleT / SETTLE_TIME) ^ 2
    if settleT >= SETTLE_TIME then settleT = nil; rate = 9 end
  end

  sYaw = smooth(sYaw, yaw, rate, dt)
  sPitch = smooth(sPitch, pitch, rate, dt)
  sDist = smooth(sDist, dist, rate * 0.7, dt)
  sFov = smooth(sFov, fov, filming and 3 or 1.2, dt)
  wallWeight = smooth(wallWeight, wallTarget, 2.2, dt)

  local wanted = focus or carCenter()
  sFocus = sFocus and (sFocus + (wanted - sFocus) * (1 - exp(-(filming and 14 or 5) * dt))) or wanted

  local offset = orbitOffset(sYaw, sPitch, sDist)
  local pos
  if filming and filmPos then
    pos = filmPos
    offset = pos - sFocus
  else
    local k = roomLimit(sFocus, offset)
    offset = offset * (1 + (k - 1) * wallWeight)
    pos = sFocus + offset
  end
  lastDist = offset:length()
  lastPos = pos
  local rot = quatFromDir((sFocus - pos):normalized(), vec3(0, 0, 1))
  -- whoever draws things that must sit still on the screen needs this frame's camera, not the last
  if M.onPose then M.onPose(pos, rot, sFov, dt) end
  return pos, rot, sFov, sFocus
end

-- facingOut: the car came in through the side door and is parked nose to the front door
function M.setup(_site, centerFn, length, facingOut)
  site = _site
  flip = facingOut and math.pi or 0
  getCarCenter = centerFn
  carLength = max(2.5, length or 4.5)
  distMin = max(2.0, carLength * 0.5)
  distMax = max(distMin + 2, carLength * 1.75)
end

local function workingView()
  return rad(-145) + flip, rad(14), clamp(carLength * 1.25, distMin, distMax)
end

-- the drive-in: look at the front of the car from inside. The camera's
-- arm is far longer than the garage, so the walls hold the camera at the back of the room
-- and it waits there, sinking a little, while the car comes towards it.
function M.startFilm(pos)
  active, filming, settleT, lift = true, true, nil, false
  focus, sFocus = nil, nil
  filmPos = pos
  yaw, pitch, dist, fov = rad(-194) + flip, rad(5), 30, FILM_FOV
  sYaw, sPitch, sDist, sFov = yaw, pitch, dist, FILM_FOV
  wallWeight, wallTarget = 1, 1
  rate = 1.6
end

-- the drive out: stay in the garage and watch the car go
function M.startExit()
  if not active then return end
  filming, settleT, lift = true, nil, false
  focus = nil
  filmPos = lastPos           -- stay right here and turn to follow
  fov = FILM_FOV
  wallTarget = 1
  rate = 2.5
end

-- the car has stopped: swing round to the working view in one move and hand over the controls
function M.startOrbit(fromFilm)
  active = true
  local y, p, d = workingView()
  yaw, pitch, dist, fov = y, p, d, ORBIT_FOV
  wallTarget = 1
  focus = nil
  if fromFilm and filming and filmPos and sFocus then
    -- carry on from where the film camera stands: the same place, said in orbit terms
    local offset = filmPos - sFocus
    local dir = site and site.dir or vec3(0, 1, 0)
    local right = vec3(dir.y, -dir.x, 0)
    sDist = max(0.5, offset:length())
    sPitch = math.asin(clamp(offset.z / sDist, -1, 1))
    sYaw = math.atan2(-offset:dot(right), -offset:dot(dir))
    while sYaw - yaw > math.pi do sYaw = sYaw - 2 * math.pi end
    while sYaw - yaw < -math.pi do sYaw = sYaw + 2 * math.pi end
    wallWeight = 0            -- it may stand outside the orbit's room; ease it in
    settleT = 0
    rate = 1.4
  else
    sYaw, sPitch, sDist, sFov = yaw, pitch, dist, ORBIT_FOV - 14
    sFocus = nil
    wallWeight = 1
    settleT = nil
    rate = 9
  end
  filming = false
  filmPos = nil
end

function M.stop()
  M.onPose = nil
  filmPos, lastPos = nil, nil
  active, filming, settleT, lift = false, false, nil, false
  site, getCarCenter, focus, sFocus = nil, nil, nil, nil
end

-- the car has been turned round where it stands
function M.setFacingOut(facingOut) flip = facingOut and math.pi or 0 end

function M.isActive() return active end
function M.isFilming() return filming end

-- input -------------------------------------------------------------------------------------

function M.rotate(dxPixels, dyPixels)
  if not active or filming then return end
  if settleT then settleT = nil; rate = 9 end
  yaw = yaw + dxPixels * 0.0055
  pitch = clamp(pitch - dyPixels * 0.0045, lift and PITCH_MIN_LIFT or PITCH_MIN, PITCH_MAX)
end

function M.zoom(steps)
  if not active or filming then return end
  dist = clamp(dist * (1 - steps * 0.11), focus and 0.8 or distMin, distMax)
end

-- look at a point on the car (nil goes back to the whole car)
function M.setFocus(pos, radius)
  if not active or filming then return end
  focus = pos
  if pos and radius then dist = clamp(max(distMin * 0.6, radius * 3.2), 1.2, distMax) end
  if not pos then dist = clamp(carLength * 1.25, distMin, distMax) end
end

function M.hasFocus() return focus ~= nil end

-- "lift": the camera may drop low and look up at the underside
function M.setLift(on)
  lift = on == true
  if lift then
    pitch = rad(6)          -- the camera rises with the car; start just above level with it
  else
    pitch = clamp(pitch, PITCH_MIN, PITCH_MAX)
    if pitch < rad(8) then pitch = rad(14) end
  end
end

function M.isLift() return lift end

return M
