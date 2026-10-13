-- Wrench Works (extension name: slrr_garage)
-- Street Legal Racing: Redline's garage, in BeamNG. Drive up to the Belasco City Garage on
-- West Coast USA: the car rolls in on its own, watched from inside, the camera swings round
-- into the garage view, and from there you work on the car the SLRR way - click parts off onto
-- the shelf, click them back on, tune them with the screwdriver, order new ones from the
-- catalog, repair, respray, and drive out through the side door.
--
-- This file is the conductor: it owns the state machine (idle -> film -> garage <-> catalog ->
-- leaving, and idle <-> shop for the parts shops around the map) and wires the picker, the parts model, the camera, the damage keeper and the UI
-- together.

local M = {}
M.dependencies = { 'core_jobsystem', 'core_vehicle_manager', 'core_camera', 'core_input_actionFilter' }

local sites = require('slrr/garageSites')
local picker = require('slrr/garagePicker')
local parts = require('slrr/garageParts')
local camera = require('slrr/garageCamera')
local damage = require('slrr/garageDamage')
local shapes = require('slrr/garageShapes')
local preview = require('slrr/garagePreview')
local lift = require('slrr/garageLift')
local settings = require('slrr/garageSettings')

local im = ui_imgui

local logTag = 'slrr_garage'
local SOUND_DIR = '/art/sound/slrr_garage/'
local FILM_SPEED = 5.2          -- m/s the car rolls in and out at
local FILM_ACCEL = 2.4
local FILM_START = -15          -- the drive-in starts no further out than this (metres along the axis)
local FILM_TIMEOUT = 14
local FADE_TIME = 0.22

local blockedActions = core_input_actionFilter.createActionTemplate({
  "funStuff", "bigMap", "vehicleMenues", "vehicleTeleporting", "physicsControls", "aiControls",
  "walkingMode", "resetPhysics", "vehicleSwitching", "freeCam", "gameCam", "photoMode", "miniMap",
  "radialMenuActivate", "couplers", "vehicleTriggers", "nodegrabber",
})

local phase = 'idle'      -- idle | film | garage | catalog | busy | leaving | shop
local shop                -- the parts shop we are in (phase 'shop')
local shopArmed = true    -- a shop opens again only after you have driven off its marker
local shopTimer = 0       -- how long the car has stood on a shop marker
local deliveryTimer = 0
local mode = 'mechanic'   -- mechanic (wrench: fit and remove) | tune (screwdriver: adjust and open)
local tool                -- nil | 'repair' | 'sell' : what the next click on a part does instead
local site                -- the garage we are in / entering
local viaSide = false     -- this visit came in through the garage's second door (and leaves by the front)
local centreZOffset       -- height of the car's centre above its position, noted once it is parked
local sillHeight = 0.2    -- how far the car's underside is off the floor, for the lift's pads
local restZ               -- height of the car's position while it stands on the floor
local sellAllTimer        -- running while "sell all" waits for its second click
local vehId
local armed = true        -- auto-enter is switched off until the car has left the doorway again
local fade = 0            -- what the UI's black overlay should be (0..1 target)
local message, messageTimer
local hoverPath
local mouseOverUi = false
local dragging = false
local engineOn = false
local previousCamera
local previousGameState
local respawnWaiter       -- function called when our own respawn has finished
local settleFrames = 0
local damageWaiter        -- function called when the vehicle has reported its damage
local frame = 0
local testHoverTimer       -- while set, a test is steering the hover and the real cursor is ignored
local onCameraPose         -- set further down: places the part models for this frame's camera
local sendTunePart         -- set further down
local tuneSelected         -- part path picked with the screwdriver (outlined, its adjustments shown)

----------------------------------------------------------------------------------------------
-- small helpers

local function veh()
  return vehId and getObjectByID(vehId)
end

local function playSound(name, volume)
  local file = SOUND_DIR .. name
  if FS:fileExists(file) then
    Engine.Audio.playOnce('AudioGui', file, { volume = volume or 1 })
  end
end

local function carCenter()
  local v = veh()
  if not v then return nil end
  local c = v:getSpawnWorldOOBB():getCenter()
  -- that box stays on the floor when the car goes up on the lift; the car's position does not
  if centreZOffset then c.z = v:getPosition().z + centreZOffset end
  return c
end

local START_ENGINE = [[
  if electrics.setIgnitionLevel then electrics.setIgnitionLevel(2) end
  for _, dev in pairs(powertrain.getDevices()) do
    if dev.activateStarter and dev.outputAV1 and math.abs(dev.outputAV1) < 20 then dev:activateStarter() end
  end
]]

local function freezeCar(frozen)
  local v = veh()
  if not v then return end
  -- straight to the vehicle's own Lua: lock the drivetrain, key off, handbrake on
  if frozen then
    v:queueLuaCommand('controller.setFreeze(1) if electrics.setIgnitionLevel then electrics.setIgnitionLevel(0) end input.event("parkingbrake", 1, FILTER_DIRECT)')
    engineOn = false
  else
    -- key on and crank the engine directly (the normal starter wants a foot on the clutch);
    -- the handbrake stays on, as on any freshly spawned car, so nothing creeps away
    v:queueLuaCommand('controller.setFreeze(0) ' .. START_ENGINE)
  end
end

local function placeCarAt(pos, dir)
  local v = veh()
  if not v then return end
  spawn.safeTeleport(v, pos, quatFromDir(dir, vec3(0, 0, 1)), true, nil, false, true, false)
end

local function placeCar(along, facingIn)
  if not site then return end
  placeCarAt(sites.point(site, along, 0, 0.05), facingIn and site.dir or -site.dir)
end

local function carName()
  local v = veh()
  if not v then return nil end
  local info = core_vehicles.getModel(v:getJBeamFilename())
  local m = info and info.model
  return m and ((m.Brand and (m.Brand .. ' ') or '') .. (m.Name or v:getJBeamFilename())) or v:getJBeamFilename()
end

----------------------------------------------------------------------------------------------
-- UI

local function inventoryForUi()
  local list = {}
  for _, item in ipairs(parts.getInventory()) do
    list[#list + 1] = {
      id = item.id, part = item.part, name = item.name, slot = item.slot, section = item.section, photo = 'item_' .. item.id,
      value = parts.itemPrice(item), count = item.count or 1, new = item.new == true,
      damaged = parts.itemDamaged(item), repairCost = parts.itemRepairCost(item), sellValue = parts.sellValue(item),
      contents = (item.count or 1) > 1 and parts.itemContents(item) or nil,
    }
  end
  return list
end

local function sendState()
  local inGarage = phase == 'garage' or phase == 'catalog' or phase == 'busy'
  guihooks.trigger('slrrGarageState', {
    phase = phase,
    mode = mode,
    tool = tool,
    fade = fade,
    garage = (shop and shop.name) or (site and site.name) or nil,
    shop = shop and { name = shop.name, trade = shop.trade, discount = settings.get('shopDiscount') } or nil,
    car = carName(),
    money = parts.getMoney(),
    unlimited = parts.isUnlimited(),
    shelfValue = inGarage and parts.shelfValue() or 0,
    career = parts.inCareer(),
    inventory = inGarage and inventoryForUi() or {},
    filters = parts.getSectionFilter(),
    message = message,
    focused = camera.hasFocus(),
    lift = camera.isLift(),
    engineOn = engineOn,
    damaged = damage.countAll() > 0,
    repairAllCost = inGarage and parts.repairAllCost() or 0,
    previews = settings.get('previews'),
    paint = (parts.getPaints()[1] or {}).baseColor,
    paintSmoke = settings.get('paintSmoke'),
    hints = settings.get('hints'),
  })
end

local function say(text, seconds)
  message = text
  messageTimer = seconds or 3.5
  sendState()
end

local function sendHover()
  local d = hoverPath and parts.describe(hoverPath) or nil
  guihooks.trigger('slrrGarageHover', d or {})
end

local function setFade(target)
  fade = target
  sendState()
end

local function setHover(partPath)
  if partPath == hoverPath then return end
  hoverPath = partPath
  parts.setHighlight(settings.get('highlight') and partPath or nil)
  sendHover()
end

local function sendTuning(category)
  guihooks.trigger('slrrGarageTuning', { vars = parts.getTuning(), category = category })
end

local function sendSettings()
  guihooks.trigger('slrrGarageSettings', { defs = settings.describe(), career = parts.inCareer() })
end

----------------------------------------------------------------------------------------------
-- damage that survives rebuilding the car

local function captureDamage(job)
  damage.clear()
  local v = veh()
  if not v or not settings.get('keepDamage') then return end
  local done = false
  damageWaiter = function() done = true end
  v:queueLuaCommand('extensions.load("slrrGarageVeh") slrrGarageVeh.capture()')
  local waited = 0
  while not done and waited < 2 do
    job.sleep(0.03)
    waited = waited + 0.03
  end
  damageWaiter = nil
end

local function onDamageCaptured(id, data)
  if id ~= vehId then return end
  damage.setCar(data)
  if damageWaiter then damageWaiter() end
end

local function applyDamage()
  local v = veh()
  if not v or not settings.get('keepDamage') then return false end
  local data = damage.buildApply(parts.getShelfDamages())
  if #data.beams == 0 then return false end
  v:queueLuaCommand('extensions.load("slrrGarageVeh") slrrGarageVeh.apply(' .. serialize(data) .. ')')
  return true
end

----------------------------------------------------------------------------------------------
-- rebuilding the car for real (one vehicle respawn, hidden behind a fade)

local function respawnWithDesired(job, final)
  local v = veh()
  local config = parts.buildConfig(final)
  if not v or not config then return end
  -- remember where the car stands (centre + heading); a respawn does not put it back exactly
  local center, dir = carCenter(), vec3(v:getDirectionVector())
  dir.z = 0
  dir:normalize()
  setHover(nil)
  picker.clear()
  local done = false
  respawnWaiter = function() done = true end
  v:respawn(serialize(config))
  local waited = 0
  while not done and waited < 10 do
    job.sleep(0.05)
    waited = waited + 0.05
  end
  respawnWaiter = nil
  job.sleep(0.05)
  v = veh()
  if not v then return end
  local nowCenter, nowDir = carCenter(), v:getDirectionVector()
  if (nowCenter - center):length() > 0.12 or nowDir:dot(dir) < 0.998 then
    local floorZ = site and site.spot.z or (center.z - 0.6)
    spawn.safeTeleport(v, vec3(center.x, center.y, floorZ + 0.05), quatFromDir(dir, vec3(0, 0, 1)), true, nil, false, true, false)
    job.sleep(0.2)
  end
  -- a rebuilt car is a repaired car; put the dents back
  job.sleep(0.15)
  if applyDamage() then job.sleep(0.3) end
  return true
end

-- in the garage: make the spawned car match what is shown, then carry on
local function applyInGarage(job)
  phase = 'busy'
  setFade(1)
  job.sleep(FADE_TIME)
  respawnWithDesired(job, false)
  job.sleep(0.2)
  freezeCar(true)
  parts.attach(vehId, true)
  if camera.isLift() then
    -- a rebuilt car is back on the floor; put it up again before the fade lifts
    setCarLift(true)
    job.sleep(2.6)
  end
  picker.begin(vehId)
  job.sleep(0.1)
  phase = 'garage'
  setFade(0)
  sendHover()
  if mode == 'tune' then
    sendTuning()
    sendTunePart()
  end
end

----------------------------------------------------------------------------------------------
-- entering

-- points: world positions the front of the car passes through. Returns a timed path for the
-- script AI (ease up to FILM_SPEED, ease down to a stop) and how long it takes.
local function buildDrivePath(points)
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

-- tell the UI which parts have no model, so it shows its icon for them instead
local function sendPreview(partName, hasModel)
  if not hasModel then guihooks.trigger('slrrGaragePreview', { part = partName, none = true }) end
end

-- ... and which previews are in place right now, so it opens a hole only over those
local function sendPreviewLive(ids)
  guihooks.trigger('slrrGaragePreviewLive', { ids = ids })
end

-- A garage has a front door on its axis and, most of them, a second one: at the side, reached
-- by a quarter turn to the left, or at the back, straight on. A visit comes in through one
-- and leaves through the other; with a single door the car backs out.
local function leftOf(s) return vec3(-s.dir.y, s.dir.x, 0) end
local function axisPoint(s, along, left) return s.spot + s.dir * along + leftOf(s) * left + vec3(0, 0, 0.3) end

-- where the front of the car goes between the parking spot and the forecourt of a side door
local function sideRoute(half, farLeft)
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

-- the drive in: { points, startPos, startDir, parkDir }. It starts where the car is, in the doorway.
local function entryRoute(half)
  local left = leftOf(site)
  local c = carCenter()
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
local function exitRoute(half)
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
  local points = sideRoute(half, site.exitLeft)
  return {
    points = points,
    isOutside = function(c) return (c - site.spot):dot(left) > site.exitClear end,
    endPos = points[#points] - left * half - vec3(0, 0, 0.25), endDir = left,
  }
end

-- where the camera stands to film the drive in: across the room from the door the car uses
local function filmSpot()
  local side = math.min(site.halfWidth - 0.9, 2.4)
  if viaSide and site.exit == 'side' then
    return sites.point(site, site.exitTurnAlong - 0.6, side, 1.55)       -- right-hand wall, facing the side door
  elseif viaSide then
    return sites.point(site, math.max(site.doorDist + 1.4, -6.5), -side, 1.5)   -- on the front-door side, facing the back door
  end
  return sites.point(site, math.min(site.backDist - 0.6, 6.5), -side, 1.5)       -- on the far side, facing the front door
end

-- how far the underside of the car is off the floor, from its jbeam: lowest node of the body
-- shell above the lowest node of all (the bottom of the tyres)
local function measureSill()
  local vd = vehId and core_vehicle_manager.getVehicleData(vehId)
  local rn = vd and vd.vdata.refNodes and vd.vdata.refNodes[0]
  local chassis = rn and vd.vdata.nodes[rn.ref] and vd.vdata.nodes[rn.ref].partPath
  local lowest, lowestBody = math.huge, math.huge
  for _, node in pairs(vd and vd.vdata.nodes or {}) do
    local z = node.pos and tonumber(node.pos.z)
    if z then
      if z < lowest then lowest = z end
      if node.partPath == chassis and z < lowestBody then lowestBody = z end
    end
  end
  if lowest == math.huge or lowestBody == math.huge then return 0.2 end
  return clamp(lowestBody - lowest, lift.restHeight() + 0.01, 0.5)
end

-- the driver gets out: the door on their side swings open and is pushed shut again
local function driverDoorJob(job)
  local vd = vehId and core_vehicle_manager.getVehicleData(vehId)
  local name
  for _, ctrl in pairs(vd and vd.vdata.controller or {}) do
    if type(ctrl) == 'table' and ctrl.fileName == 'advancedCouplerControl' and type(ctrl.name) == 'string' then
      local n = ctrl.name:lower()
      if n:find('door_fl', 1, true) or (n:find('door_l', 1, true) and not name) then name = ctrl.name end
    end
  end
  local v = veh()
  if not name or not v then return end
  v:queueLuaCommand(string.format('do local c = controller.getControllerSafe(%q) if c and c.detachGroup then c.detachGroup() end end', name))
  job.sleep(1.9)
  v = veh()
  if v and phase ~= 'idle' and phase ~= 'leaving' then
    v:queueLuaCommand(string.format('do local c = controller.getControllerSafe(%q) if c and c.tryAttachGroupImpulse then c.tryAttachGroupImpulse() end end', name))
  end
end

local function enterJob(job)
  local v = veh()
  if not v then phase = 'idle' return end
  local length = v:getInitialLength()
  local half = length * 0.5

  -- cut to black; everything that needs hiding happens now, so the film runs uninterrupted
  setFade(1)
  job.sleep(FADE_TIME + 0.05)
  previousCamera = core_camera.getActiveCamName(0)
  previousGameState = core_gamestate.state and deepcopy(core_gamestate.state) or nil
  core_input_actionFilter.setGroup('slrrGarageBlocked', blockedActions)
  core_input_actionFilter.addAction(0, 'slrrGarageBlocked', true)
  v:queueLuaCommand('ai.scriptStop(true, true) ai.setMode("disabled") input.event("throttle", 0, FILTER_DIRECT) input.event("brake", 0, FILTER_DIRECT)')
  local route = entryRoute(half)

  captureDamage(job)                      -- note the dents before anything rebuilds the car
  parts.attach(vehId, false)
  shapes.setup(parts.resolvePart, parts.getSkin())
  preview.setup(parts.getModel(), sendPreview, sendPreviewLive)
  preview.setPaintFrom(v)
  parts.collectDeliveries()                -- whatever was ordered and has arrived is on the shelf
  parts.cartClear()

  v = veh()
  if not v then phase = 'idle' setFade(0) return end
  centreZOffset = nil
  camera.setup(site, carCenter, length, viaSide)
  camera.onPose = onCameraPose
  lift.setup(site.spot, site.dir)           -- the car drives in between its posts
  sillHeight = measureSill()
  mode, tool = 'mechanic', nil

  if settings.get('playFilm') then
    freezeCar(false)
    v:queueLuaCommand('input.event("parkingbrake", 0, FILTER_DIRECT)')
    placeCarAt(route.startPos, route.startDir)
    job.sleep(0.3)
    camera.startFilm(filmSpot())
    core_camera.setByName(0, 'slrrGarage', false)
    playSound('entergarage.wav')
    local path, duration = buildDrivePath(route.points)
    v:queueLuaCommand('ai.startFollowing(' .. serialize({ path = path }) .. ', 0, 1, "neverReset")')
    job.sleep(0.1)
    setFade(0)

    -- one unbroken shot from inside the garage: the car comes in nose first, towards the camera
    local clock = hptimer()
    local t = 0
    while t < math.min(FILM_TIMEOUT, duration + 4) do
      job.sleep(0.02)
      t = clock:stop() / 1000
      v = veh()
      if not v then break end
      local along, side = sites.toAxis(site, carCenter())
      local arrived = viaSide and (along < 0.5 and math.abs(side) < 1.5) or (not viaSide and along > -0.5)
      if t < 1.2 then arrived = false end      -- it starts in the doorway, give it time to get going
      if arrived or (t > duration and v:getVelocity():length() < 0.3) then break end
    end

    v = veh()
    if not v then phase = 'idle' setFade(0) return end
    v:queueLuaCommand('ai.scriptStop(true, true) ai.setMode("disabled") input.event("throttle", 0, FILTER_DIRECT) input.event("brake", 1, FILTER_DIRECT)')
    -- the camera starts its swing to the working view while the car settles on its springs
    camera.startOrbit(true)
    local along, side = sites.toAxis(site, carCenter())
    if math.abs(along) > 1.2 or math.abs(side) > 1.0 then
      -- the car did not make it (stalled, broken, blocked): cut and park it properly
      setFade(1)
      job.sleep(FADE_TIME)
      placeCarAt(sites.point(site, 0, 0, 0.05), route.parkDir)
      job.sleep(0.3)
      camera.startOrbit(false)
      setFade(0)
    else
      -- it stops a hand's breadth out, never dead centre: ease it onto the middle of the lift
      job.sleep(0.25)
      v = veh()
      local from = v and carCenter()
      if from and (math.abs(along) > 0.03 or math.abs(side) > 0.03) then
        local base = v:getPosition()
        local shift = sites.point(site, 0, 0, 0) - from
        shift.z = 0
        local ref = v:getRefNodeId()
        local clock = hptimer()
        local time = clamp(shift:length() / 0.9, 0.25, 1.1)
        while true do
          local k = math.min(1, clock:stop() / 1000 / time)
          local e = k * k * (3 - 2 * k)
          local p = base + shift * e
          v:setClusterPosRelRot(ref, p.x, p.y, p.z, 0, 0, 0, 1)     -- moved as it stands, nothing reset
          if k >= 1 then break end
          job.sleep(0)
          v = veh()
          if not v then break end
        end
      end
    end
    job.sleep(0.35)
    v:queueLuaCommand('input.event("brake", 0, FILTER_DIRECT)')
    if settings.get('driverDoor') then core_jobsystem.create(driverDoorJob) end
  else
    placeCarAt(sites.point(site, 0, 0, 0.05), route.parkDir)
    job.sleep(0.35)
    camera.startOrbit(false)
    core_camera.setByName(0, 'slrrGarage', false)
    playSound('entergarage.wav')
    setFade(0)
  end

  freezeCar(true)
  picker.begin(vehId)
  v = veh()
  if v then
    local c = v:getSpawnWorldOOBB():getCenter()
    centreZOffset = c.z - v:getPosition().z
    restZ = v:getPosition().z
  end
  lift.setArms(true)                         -- the arms swing in under the sills
  phase = 'garage'
  sendState()
  sendHover()
end

local function startEnter(_site, id, side)
  if phase ~= 'idle' then return end
  site = _site
  viaSide = side == true
  vehId = id
  phase = 'film'
  armed = false
  core_gamestate.setGameState('slrrGarage', 'slrrGarage', 'freeroam')
  sendState()
  core_jobsystem.create(enterJob)
end

----------------------------------------------------------------------------------------------
-- leaving

local function cleanup()
  core_input_actionFilter.setGroup('slrrGarageBlocked', blockedActions)
  core_input_actionFilter.addAction(0, 'slrrGarageBlocked', false)
  camera.stop()
  picker.clear()
  preview.clear()
  lift.clear()
  shapes.release()
  parts.detach()
  damage.clear()
  centreZOffset, restZ = nil, nil
  hoverPath, tool, mode, tuneSelected = nil, nil, 'mechanic', nil
  if core_camera.getActiveCamName(0) == 'slrrGarage' then
    core_camera.setByName(0, (previousCamera and previousCamera ~= 'slrrGarage') and previousCamera or 'orbit', false)
  end
  if previousGameState and previousGameState.state and previousGameState.state ~= 'slrrGarage' then
    core_gamestate.setGameState(previousGameState.state, previousGameState.appLayout, previousGameState.menuItems, previousGameState.options)
  else
    core_gamestate.setGameState('freeroam', 'freeroam', 'freeroam')
  end
  phase = 'idle'
  site = nil
end

local function leaveJob(job)
  local missing = parts.missingEssentials()
  local v = veh()
  local half = v and v:getInitialLength() * 0.5 or 2.2
  setFade(1)
  job.sleep(FADE_TIME + 0.05)
  preview.setSlots({})
  lift.setArms(false, true)
  lift.setPadHeight(nil, true)
  if camera.isLift() then
    camera.setLift(false)
    if v then v:queueLuaCommand('if slrrGarageVeh then slrrGarageVeh.releaseLift() end') end
    job.sleep(0.6)
  end
  if parts.isDirty() then
    respawnWithDesired(job, true)
    job.sleep(0.2)
  elseif parts.paintsDirty() and core_vehicle_partmgmt then
    -- the new colours are already on the car; make them part of its config too
    core_vehicle_partmgmt.setConfigPaints(parts.getPaints(), false)
  end
  parts.detach()
  picker.clear()
  freezeCar(false)

  local route = exitRoute(half)
  local outside = false
  centreZOffset, restZ = nil, nil
  v = veh()
  if v and settings.get('playFilm') and not missing then
    -- the car drives itself out while the camera stays behind in the garage
    v:queueLuaCommand('input.event("parkingbrake", 0, FILTER_DIRECT)')
    camera.startExit()
    job.sleep(0.5)
    local path, duration = buildDrivePath(route.points)
    v:queueLuaCommand('ai.startFollowing(' .. serialize({ path = path }) .. ', 0, 1, "neverReset")')
    playSound('leavegarage.wav')
    setFade(0)
    local clock = hptimer()
    local t, from = 0, carCenter()
    while t < duration + 3 do
      job.sleep(0.03)
      t = clock:stop() / 1000
      v = veh()
      if not v then break end
      local c = carCenter()
      outside = route.isOutside(c)
      -- it rolls to a stop on the forecourt before you get the wheel back
      if outside and t > duration * 0.6 and v:getVelocity():length() < 0.5 then break end
      if t > 3 and (c - from):length() < 1 then break end      -- it is not going anywhere
    end
    v = veh()
    if v then v:queueLuaCommand('ai.scriptStop(true, true) ai.setMode("disabled") input.event("throttle", 0, FILTER_DIRECT) input.event("brake", 0, FILTER_DIRECT)') end
    setFade(1)
    job.sleep(FADE_TIME)
  else
    playSound('leavegarage.wav')
  end
  if not outside then
    -- no film, or the car cannot move by itself: put it outside the door
    placeCarAt(route.endPos, route.endDir)
    job.sleep(0.3)
  end
  cleanup()
  core_camera.resetCamera(0)
  job.sleep(0.15)
  setFade(0)
  if missing and ui_message then
    ui_message('You left the garage without ' .. missing .. '.', 6, 'slrrGarage')
  end
end

local function leave()
  if phase ~= 'garage' then return end
  phase = 'leaving'
  setHover(nil)
  sendState()
  core_jobsystem.create(leaveJob)
end

----------------------------------------------------------------------------------------------
-- the screwdriver: open panels, jump to a part's adjustments

-- latch controllers (doors, hood, boot) that hold the given part shut
local function latchesOf(partPath)
  local vd = core_vehicle_manager.getVehicleData(vehId)
  if not vd then return {} end
  local pathOfNode = {}
  for _, node in pairs(vd.vdata.nodes or {}) do
    if node.name then pathOfNode[node.name] = node.partPath end
  end
  local chassis = vd.vdata.refNodes and vd.vdata.refNodes[0] and vd.vdata.refNodes[0].partPath
  -- climb from the clicked part to the first part that a latch is attached to
  local path = partPath
  while path and path ~= '' do
    local slotPath = parts.getSlotPath(path)
    if not slotPath or path == chassis then break end
    local found = {}
    for _, ctrl in pairs(vd.vdata.controller or {}) do
      if type(ctrl) == 'table' and ctrl.fileName == 'advancedCouplerControl' and ctrl.name then
        local section = vd.vdata[ctrl.name]
        for i, row in ipairs(section and section.couplerNodes or {}) do
          if i > 1 and type(row) == 'table' then
            for k = 1, 2 do
              local nodePath = pathOfNode[row[k]]
              if nodePath and nodePath:sub(1, #slotPath) == slotPath then found[ctrl.name] = true end
            end
          end
        end
      end
    end
    if next(found) then return tableKeysSorted(found) end
    -- one level up: "/a/b/c/part" -> the part chosen in slot "/a/b/"
    local parentSlot = slotPath:match('^(.*/)[^/]+/$')
    path = parentSlot and parts.partPathAtSlot(parentSlot) or nil
  end
  return {}
end

-- tell the UI about the part picked with the screwdriver: what it is and what can be adjusted
sendTunePart = function()
  local d = tuneSelected and parts.describe(tuneSelected)
  if not d then
    tuneSelected = nil
    guihooks.trigger('slrrGarageTunePart', {})
    return
  end
  local tuning = parts.getPartTuning(tuneSelected) or { vars = {} }
  guihooks.trigger('slrrGarageTunePart', {
    partPath = tuneSelected, name = d.name, slot = d.slot, damaged = d.damaged,
    vars = tuning.vars, owner = tuning.owner, canOpen = #latchesOf(tuneSelected) > 0,
  })
end

-- screwdriver click: pick the part. It gets an outline and its own small tuning menu.
local function tuneClick(partPath)
  if tuneSelected == partPath then
    tuneSelected = nil
  else
    tuneSelected = partPath
    playSound('mnuselect.wav', 0.7)
  end
  sendTunePart()
end

-- open or close the selected door, hood or boot
local function toggleOpen()
  local v = veh()
  if phase ~= 'garage' or not v or not tuneSelected then return end
  local latches = latchesOf(tuneSelected)
  if #latches == 0 then return end
  local cmds = {}
  for _, name in ipairs(latches) do
    cmds[#cmds + 1] = string.format('do local c = controller.getControllerSafe(%q) if c and c.toggleGroup then c.toggleGroup() end end', name)
  end
  v:queueLuaCommand(table.concat(cmds, ' '))
  playSound('dragdrop.wav', 0.8)
end

-- an outline box around a part
local boxEdges = { {1, 2}, {3, 4}, {5, 6}, {7, 8}, {1, 3}, {2, 4}, {5, 7}, {6, 8}, {1, 5}, {2, 6}, {3, 7}, {4, 8} }
local boxColor = ColorF(1, 0.4, 0, 1)
local function drawPartBox(partPath, alpha, thickness)
  local corners = picker.getMeshesCorners(parts.getPartMeshes(partPath))
  if not corners then return end
  boxColor.a = alpha
  for _, e in ipairs(boxEdges) do
    debugDrawer:drawCylinder(corners[e[1]], corners[e[2]], thickness, boxColor)
  end
end

----------------------------------------------------------------------------------------------
-- things the UI asks for

-- left click on the 3D view
local function click()
  if phase ~= 'garage' or not hoverPath then return end
  if tool == 'repair' then
    local ok, res = parts.repairPart(hoverPath)
    if not ok then
      playSound('warn.wav', 0.6)
      say(res)
      return
    end
    playSound('repair.wav')
    tool = nil
    core_jobsystem.create(applyInGarage)
    return
  end
  if mode == 'tune' then
    tuneClick(hoverPath)
    return
  end
  local item, err = parts.removePart(hoverPath)
  if not item then
    playSound('warn.wav', 0.6)
    say(err or "That cannot come off.")
    return
  end
  playSound('wrench.wav')
  hoverPath = nil
  sendHover()
  sendState()
  guihooks.trigger('slrrGarageItemAdded', { id = item.id })
end

local function sell(itemId)
  if phase ~= 'garage' and phase ~= 'catalog' then return end
  local ok, item, value = parts.sellItem(tonumber(itemId))
  if ok then
    playSound('money.wav')
    say(string.format('Sold the %s for $%d.', item.name, value), 2.5)
  end
end

-- sell everything on the shelf. It asks first: the second click within a few seconds does it.
local function sellAll()
  if phase ~= 'garage' then return end
  local count = #parts.getInventory()
  if count == 0 then
    say('There is nothing on the shelf to sell.', 2.5)
    return
  end
  if not sellAllTimer and settings.get('confirmSellAll') then
    sellAllTimer = 5
    playSound('warn.wav', 0.5)
    say(string.format('Sell all %d parts on the shelf for $%d? Click again to confirm.', count, parts.shelfValue()), 5)
    return
  end
  sellAllTimer = nil
  local sold, total = parts.sellAll()
  playSound('money.wav')
  say(string.format('Sold %d parts for $%d.', sold, total), 3)
end

-- click on a shelf part: fit it (or sell / repair it when that tool is armed)
local function install(itemId)
  if phase ~= 'garage' then return end
  if tool == 'sell' then
    sell(itemId)
    return
  end
  if tool == 'repair' then
    local ok, res = parts.repairItem(tonumber(itemId))
    if not ok then
      playSound('warn.wav', 0.6)
      say(res)
      return
    end
    playSound('repair.wav')
    tool = nil
    core_jobsystem.create(applyInGarage)   -- the part may be loaded on the car, hidden; straighten that copy too
    return
  end
  local ok, text, needsLoad = parts.installItem(tonumber(itemId))
  if not ok then
    playSound('warn.wav', 0.6)
    say(text)
    return
  end
  playSound('screw.wav')
  if needsLoad then
    core_jobsystem.create(applyInGarage)
  else
    sendState()
  end
end

local function setTool(name)
  if phase ~= 'garage' then return end
  if name ~= 'repair' and name ~= 'sell' then name = nil end
  tool = (tool ~= name) and name or nil
  sendState()
end

local function repairAll()
  if phase ~= 'garage' then return end
  local ok, res = parts.repairAll()
  if not ok then
    playSound('warn.wav', 0.6)
    say(res)
    return
  end
  playSound('repair.wav')
  core_jobsystem.create(applyInGarage)
end

local function setMode(name)
  if phase ~= 'garage' then return end
  mode = name == 'tune' and 'tune' or 'mechanic'
  tool = nil
  tuneSelected = nil
  setHover(nil)
  sendState()
  sendTunePart()
  if mode == 'tune' then sendTuning() end
end

local function toggleFilter(section)
  if phase ~= 'garage' then return end
  parts.toggleSectionFilter(section)
  setHover(nil)
  sendState()
end

local function sendCart()
  guihooks.trigger('slrrGarageCart', parts.cartSummary(shop ~= nil))
end

local function sendCatalog()
  local bySub = parts.buildCatalog()
  local sells
  if shop then
    sells = {}
    for _, key in ipairs(shop.sells) do sells[key] = true end
  end
  local out = {}
  for _, section in ipairs(parts.getSections()) do
    local s = { id = section.id, title = section.title, subs = {} }
    for _, sub in ipairs(section.subs) do
      local key = section.id .. '/' .. sub.id
      if not sells or sells[section.id] or sells[key] then
        s.subs[#s.subs + 1] = { id = sub.id, title = sub.title, items = bySub[key] or {} }
      end
    end
    if #s.subs > 0 then out[#out + 1] = s end
  end
  guihooks.trigger('slrrGarageCatalog', { sections = out, money = parts.getMoney() })
  sendCart()
end

local function openCatalog()
  if phase ~= 'garage' then return end
  phase = 'catalog'
  tool = nil
  setHover(nil)
  playSound('flip.wav')
  sendState()
  sendCatalog()
end

local leaveShop

local function closeCatalog()
  if phase == 'shop' then leaveShop() return end
  if phase ~= 'catalog' then return end
  playSound('mnuback.wav')
  phase = 'garage'
  sendState()
end

-- "buy" in the catalog: onto the shopping list; nothing is paid until the order is confirmed
local function buy(slotPath, partName)
  if phase ~= 'catalog' and phase ~= 'shop' then return end
  local ok, res = parts.cartAdd(slotPath, partName)
  if not ok then
    playSound('warn.wav', 0.6)
    say(res)
    return
  end
  playSound('mnuselect.wav', 0.7)
  sendCart()
end

local function cartRemove(index)
  parts.cartRemove(tonumber(index) or 0)
  sendCart()
end

local function cartClear()
  parts.cartClear()
  sendCart()
end

-- confirm the shopping list: pay, and the parts go on the shelf (shop) or on their way (garage)
local function checkout(shippingId)
  if phase ~= 'catalog' and phase ~= 'shop' then return end
  local ok, text = parts.checkout(tostring(shippingId), shop ~= nil)
  if not ok then
    playSound('warn.wav', 0.6)
    say(text)
    return
  end
  playSound('money.wav')
  say(text, 4)
  sendCatalog()
end

-- deliveries that have arrived go on the shelf
local function checkDeliveries()
  local arrived = parts.collectDeliveries()
  if arrived > 0 then
    playSound('ok.wav')
    say(arrived == 1 and 'A delivery has arrived. The part is on the shelf.' or (arrived .. ' parts have been delivered. They are on the shelf.'), 4)
    if phase == 'catalog' then sendCart() end
  end
  return arrived
end

----------------------------------------------------------------------------------------------
-- shops: over-the-counter parts in town

local function enterShop(_shop, id)
  if phase ~= 'idle' then return end
  local v = getObjectByID(id)
  if not v then return end
  shop, vehId, site = _shop, id, nil
  phase = 'shop'
  shopArmed = false
  previousGameState = core_gamestate.state and deepcopy(core_gamestate.state) or nil
  core_gamestate.setGameState('slrrGarage', 'slrrGarage', 'freeroam')
  core_input_actionFilter.setGroup('slrrGarageBlocked', blockedActions)
  core_input_actionFilter.addAction(0, 'slrrGarageBlocked', true)
  -- engine off at the counter: an idling engine shakes the camera, and the part previews wait for it to be still
  v:queueLuaCommand('controller.setFreeze(1) input.event("throttle", 0, FILTER_DIRECT) if electrics.setIgnitionLevel then electrics.setIgnitionLevel(0) end')
  parts.attach(vehId, false)
  parts.cartClear()
  parts.setCounterDiscount(settings.get('shopDiscount') / 100)
  shapes.setup(parts.resolvePart, parts.getSkin())
  preview.setup(parts.getModel(), sendPreview, sendPreviewLive)
  preview.setPaintFrom(v)
  playSound('flip.wav')
  sendState()
  sendCatalog()
end

leaveShop = function()
  if phase ~= 'shop' then return end
  local v = veh()
  if v then v:queueLuaCommand('controller.setFreeze(0) ' .. START_ENGINE) end
  playSound('mnuback.wav')
  parts.cartClear()
  parts.setCounterDiscount(0)
  preview.clear()
  shapes.release()
  parts.detach()
  core_input_actionFilter.setGroup('slrrGarageBlocked', blockedActions)
  core_input_actionFilter.addAction(0, 'slrrGarageBlocked', false)
  if previousGameState and previousGameState.state and previousGameState.state ~= 'slrrGarage' then
    core_gamestate.setGameState(previousGameState.state, previousGameState.appLayout, previousGameState.menuItems, previousGameState.options)
  else
    core_gamestate.setGameState('freeroam', 'freeroam', 'freeroam')
  end
  phase, shop, vehId = 'idle', nil, nil
  sendState()
end

-- the UI says where on the screen it wants which part shown (see garagePreview)
local function setPreviewSlots(list)
  local showing = (phase == 'garage' or phase == 'catalog' or phase == 'busy' or phase == 'shop') and settings.get('previews')
  preview.setSlots(showing and type(list) == 'table' and list or {})
end

-- tuning: the UI sends back the values the player set. Nothing is rebuilt for them here; the
-- car gets them when it is built for the drive out.
local function applyTuning(values)
  if phase ~= 'garage' then return end
  if parts.setTuning(values) and parts.varsDirty() then
    playSound('screw.wav')
    say('Adjusted. The car is set up this way when you drive out.', 3)
  end
  sendTuning()
  sendTunePart()
end

local function requestTuning()
  sendTuning()
end

-- the camera as the previews and the paint cloud need it
local function cameraInfo(pos, q, fovDeg)
  q = q or core_camera.getQuat()
  pos = pos or core_camera.getPosition()
  if not q or not pos then return nil end
  local tanY = math.tan(math.rad(fovDeg or core_camera.getFovDeg() or 60) * 0.5)
  local mode = GFXDevice.getVideoMode()
  local aspect = (mode and mode.height and mode.height > 0) and (mode.width / mode.height) or (16 / 9)
  return { pos = pos, forward = q * vec3(0, 1, 0), right = q * vec3(1, 0, 0), up = q * vec3(0, 0, 1), tanY = tanY, tanX = tanY * aspect }
end

-- the box on the screen that holds the car, in fractions of the screen: { x, y, w, h }
local function carScreenRect()
  local v = veh()
  local cam = cameraInfo()
  if not v or not cam then return { x = 0.25, y = 0.3, w = 0.5, h = 0.4 } end
  local box = v:getSpawnWorldOOBB()
  local minX, minY, maxX, maxY = 1, 1, 0, 0
  for i = 0, 7 do
    local r = box:getPoint(i) - cam.pos
    local depth = math.max(0.3, r:dot(cam.forward))
    local sx = 0.5 + 0.5 * r:dot(cam.right) / (depth * cam.tanX)
    local sy = 0.5 - 0.5 * r:dot(cam.up) / (depth * cam.tanY)
    minX, minY, maxX, maxY = math.min(minX, sx), math.min(minY, sy), math.max(maxX, sx), math.max(maxY, sy)
  end
  minX, minY, maxX, maxY = clamp(minX, 0, 1), clamp(minY, 0, 1), clamp(maxX, 0, 1), clamp(maxY, 0, 1)
  return { x = minX, y = minY, w = math.max(0.1, maxX - minX), h = math.max(0.1, maxY - minY) }
end

-- paint booth
local function sendPaint()
  local v = veh()
  if not v then return end
  local swatches = {}
  local info = core_vehicles.getModel(v:getJBeamFilename())
  for name, paint in pairs(info and info.model and info.model.paints or {}) do
    if type(paint) == 'table' and type(paint.baseColor) == 'table' then
      swatches[#swatches + 1] = { name = name, paint = paint }
    end
  end
  table.sort(swatches, function(a, b) return a.name < b.name end)
  guihooks.trigger('slrrGaragePaint', { slots = parts.getPaints(), swatches = swatches, price = settings.get('paintPrice') })
end

local function setPaint(index, paint)
  if phase ~= 'garage' then return end
  local v = veh()
  if not v or type(paint) ~= 'table' or type(paint.baseColor) ~= 'table' then return end
  index = tonumber(index)
  local clean = {
    baseColor = { tonumber(paint.baseColor[1]) or 1, tonumber(paint.baseColor[2]) or 1, tonumber(paint.baseColor[3]) or 1, tonumber(paint.baseColor[4]) or 1 },
    metallic = tonumber(paint.metallic) or 0.5, roughness = tonumber(paint.roughness) or 0.5,
    clearcoat = tonumber(paint.clearcoat) or 1, clearcoatRoughness = tonumber(paint.clearcoatRoughness) or 0.05,
  }
  local ok, why = parts.setPaint(index, clean)
  if not ok then
    playSound('warn.wav', 0.6)
    say(why)
    return
  end
  local function spray()
    local car = veh()
    if not car or phase == 'idle' then return end
    core_vehicle_manager.liveUpdateVehicleColors(vehId, car, index, clean)
    preview.setPaintFrom(car)
  end
  playSound('spray.wav')
  if settings.get('paintSmoke') then
    -- the car disappears in a cloud of the new colour and comes out of it resprayed
    guihooks.trigger('slrrGaragePaintFx', { color = clean.baseColor, rect = carScreenRect() })
    core_jobsystem.create(function(job)
      job.sleep(0.7)
      spray()
      job.sleep(0.1)
      local car = veh()
      if car then preview.setPaintFrom(car) end
    end)
  else
    spray()
  end
  sendState()
  sendPaint()
end

-- car info sheet
local function sendInfo()
  local info = parts.getCarInfo()
  info.name = carName()
  local details = core_vehicles.getCurrentVehicleDetails and core_vehicles.getCurrentVehicleDetails() or {}
  local cfg, mdl = details.configs or {}, details.model or {}
  local rows = {}
  local function row(label, value, unit)
    if value ~= nil and value ~= '' then rows[#rows + 1] = { label = label, value = tostring(value) .. (unit or '') } end
  end
  row('Configuration', cfg.Configuration or cfg.Name)
  row('Country', mdl.Country)
  row('Body style', cfg['Body Style'] or mdl['Body Style'])
  row('Drivetrain', cfg.Drivetrain)
  row('Transmission', cfg.Transmission)
  row('Power', cfg.Power and math.floor(cfg.Power + 0.5), ' hp')
  row('Torque', cfg.Torque and math.floor(cfg.Torque + 0.5), ' Nm')
  row('Weight', cfg.Weight and math.floor(cfg.Weight + 0.5), ' kg')
  row('Top speed', cfg['Top Speed'] and math.floor(cfg['Top Speed'] * 3.6 + 0.5), ' km/h')
  row('0-100 km/h', cfg['0-100 km/h'] and string.format('%.1f', cfg['0-100 km/h']), ' s')
  info.rows = rows
  info.note = (parts.isDirty() or parts.paintsDirty()) and 'Figures are for the car as it came in; your changes take effect when you drive out.' or nil
  guihooks.trigger('slrrGarageInfo', info)
end

-- lift: raise the car off the floor (the camera may then look up at it from below)
local function setCarLift(on)
  local v = veh()
  if not v then return end
  v:queueLuaCommand('extensions.load("slrrGarageVeh") slrrGarageVeh.setLift(' .. (on and settings.get('liftHeight') or 0) .. ')')
end

local function toggleLift()
  if phase ~= 'garage' then return end
  camera.setLift(not camera.isLift())
  playSound('mnuselect.wav', 0.7)
  sendState()
  if camera.isLift() then
    -- the pads come up to the sills first; from there they follow the car (see onUpdate)
    local reach = math.max(0, sillHeight - lift.getPadHeight()) / 0.55
    core_jobsystem.create(function(job)
      job.sleep(reach)
      if phase ~= 'idle' and camera.isLift() then setCarLift(true) end
    end)
  else
    setCarLift(false)
  end
end

-- test the engine where it stands (the drivetrain stays locked)
local function toggleEngine()
  if phase ~= 'garage' then return end
  local v = veh()
  if not v then return end
  engineOn = not engineOn
  if engineOn then
    v:queueLuaCommand(START_ENGINE)
  else
    v:queueLuaCommand('if electrics.setIgnitionLevel then electrics.setIgnitionLevel(0) end')
  end
  sendState()
end

-- advance the clock, as SLRR's garage does
local function advanceTime()
  if not core_environment or not core_environment.getTimeOfDay then return end
  local tod = core_environment.getTimeOfDay()
  if type(tod) ~= 'table' or not tod.time then return end
  tod.time = (tod.time + 0.125) % 1
  core_environment.setTimeOfDay(tod)
  playSound('mnumove.wav', 0.7)
end

local function requestSettings()
  sendSettings()
end

local function setSetting(key, value)
  if key == '__reset' then settings.reset() else settings.set(key, value) end
  if key == 'freeroamMoney' then parts.setWallet(settings.get('freeroamMoney')) end
  if key == 'saveBetweenSessions' then parts.saveNow() end
  if phase == 'catalog' or phase == 'shop' then sendCart() end
  if not settings.get('highlight') then parts.setHighlight(nil) end
  sendSettings()
  sendState()
  if phase == 'catalog' then sendCatalog() end
end

local function cameraDrag(dx, dy)
  dx = tonumber(dx) or 0
  if settings.get('invertCameraX') then dx = -dx end
  local k = settings.get('cameraSensitivity')
  camera.rotate(dx * k, (tonumber(dy) or 0) * k)
end

local function cameraZoom(steps)
  camera.zoom(tonumber(steps) or 0)
end

-- middle click: look at the part under the cursor, or back at the whole car
local function focus()
  if phase ~= 'garage' then return end
  if hoverPath then
    local center, radius = picker.getMeshesBounds(parts.getPartMeshes(hoverPath))
    if center then camera.setFocus(center, radius) end
  else
    camera.setFocus(nil)
  end
  sendState()
end

local function resetView()
  camera.setFocus(nil)
  sendState()
end

local function setMouseOverUi(over)
  mouseOverUi = over == true
  if mouseOverUi then setHover(nil) end
end

local function setDragging(value)
  dragging = value == true
  if dragging then setHover(nil) end
end

-- enter by hand (console / key binding): the nearest garage on this map, by its nearest door
local function enterNearest()
  if phase ~= 'idle' then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  local pos = v:getPosition()
  local best, bestDist, second
  for _, s in ipairs(sites.getSites()) do
    for _, door in ipairs(sites.doors(s)) do
      local d = (pos - door.pos):length()
      if not bestDist or d < bestDist then best, bestDist, second = s, d, door.id == 'second' end
    end
  end
  if best then startEnter(best, v:getID(), second) end
end

----------------------------------------------------------------------------------------------
-- frame update

-- a soft beacon in front of the door, like SLRR's garage marker, so the way in is obvious
local markerColor, markerTextColor, markerTextBg = ColorF(1, 0.4, 0, 0.28), ColorF(1, 1, 1, 1), ColorI(20, 20, 24, 200)
local function drawMarker(s, distance, base)
  local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
  markerColor.a = 0.16 + 0.14 * pulse
  debugDrawer:drawCylinder(base, base + vec3(0, 0, 0.12), 2.2, markerColor)
  debugDrawer:drawCylinder(base, base + vec3(0, 0, 2.6 + 0.3 * pulse), 0.07, markerColor)
  if distance < 45 then
    local label = settings.get('autoEnter') and (s.name .. ' - drive in') or s.name
    debugDrawer:drawTextAdvanced(base + vec3(0, 0, 3.1), String(label), markerTextColor, true, false, markerTextBg)
  end
end

-- shops: a blue marker on their forecourt; stop on it to go in
local shopColor = ColorF(0.1, 0.55, 1, 0.25)
local function updateShops(v, dt)
  if not settings.get('shops') then return end
  local pos = v:getPosition()
  local on
  for _, s in ipairs(sites.getShops()) do
    local d = (pos - s.pos):length()
    if d < 120 and settings.get('markers') then
      local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
      shopColor.a = 0.16 + 0.12 * pulse
      debugDrawer:drawCylinder(s.pos, s.pos + vec3(0, 0, 0.12), 3.2, shopColor)
      debugDrawer:drawCylinder(s.pos, s.pos + vec3(0, 0, 2.6 + 0.3 * pulse), 0.07, shopColor)
      if d < 60 then
        debugDrawer:drawTextAdvanced(s.pos + vec3(0, 0, 3.1), String(s.name .. ' - ' .. s.trade), ColorF(1, 1, 1, 1), true, false, ColorI(20, 20, 24, 200))
      end
    end
    if d < 4.5 then on = s end
  end
  if not on then
    shopArmed, shopTimer = true, 0
  elseif shopArmed and v:getVelocity():length() < 0.6 then
    shopTimer = shopTimer + dt
    if shopTimer > 0.8 then
      shopTimer = 0
      enterShop(on, v:getID())
    end
  else
    shopTimer = 0
  end
end

local function updateIdle(dt)
  local v = getPlayerVehicle(0)
  if not v then return end
  updateShops(v, dt)
  if phase ~= 'idle' then return end
  local list = sites.getSites()
  if #list == 0 then return end
  local pos = v:getPosition()
  local centre = v:getSpawnWorldOOBB():getCenter()
  local heading = v:getDirectionVector()
  local nose = centre + heading * (v:getInitialLength() * 0.5)
  local nearDoor = false
  for _, s in ipairs(list) do
    if (pos - s.spot):squaredLength() < 110 * 110 then
      for _, door in ipairs(sites.doors(s)) do
        local distance = (pos - door.pos):length()
        if distance < 90 and settings.get('markers') then drawMarker(s, distance, door.pos - door.inward * 1.2) end
        if (centre - door.pos):length() < 9 then nearDoor = true end
        -- the way in is the doorway itself: the nose of the car reaching the door, heading in
        local rel = nose - door.pos
        local depth = rel:dot(door.inward)
        local across = math.abs(rel:dot(vec3(-door.inward.y, door.inward.x, 0)))
        if armed and settings.get('autoEnter') and depth > -1.6 and depth < 1.2 and across < 2.6 then
          local vel = v:getVelocity()
          -- at walking pace only: anything faster is somebody driving (or drifting) through
          if vel:length() < settings.get('enterSpeed') / 3.6 and heading:dot(door.inward) > 0.55 and vel:dot(door.inward) > 0.3 then
            startEnter(s, v:getID(), door.id == 'second')
            return
          end
        end
      end
    end
  end
  -- after a visit the doors only work again once the car has left the doorway
  if not armed and not nearDoor then armed = true end
end

local function updateGarage(dt)
  picker.update()
  deliveryTimer = deliveryTimer + dt
  if deliveryTimer > 1.5 then
    deliveryTimer = 0
    if checkDeliveries() > 0 then sendState() end
  end
  -- middle mouse button: look at the part under the cursor
  if not mouseOverUi and im.IsMouseClicked(2) then focus() end
  if testHoverTimer then
    testHoverTimer = testHoverTimer - dt
    if testHoverTimer <= 0 then testHoverTimer = nil end
    parts.updateHighlight(dt)
    if mode == 'tune' and tuneSelected then drawPartBox(tuneSelected, 0.95, 0.008) end
    return
  end
  if mouseOverUi or dragging or not picker.isReady() then
    if hoverPath then setHover(nil) end
  else
    local ray = getCameraMouseRay()
    local partPath
    if ray then
      local picked = picker.pick(ray.pos, ray.dir, parts.isMeshHidden)
      partPath = picked and parts.removableAncestor(picked) or picked
    end
    setHover(partPath)
  end
  parts.updateHighlight(dt)
  if mode == 'tune' then
    -- the picked part keeps a solid outline; the one under the cursor gets a faint one
    if tuneSelected then drawPartBox(tuneSelected, 0.95, 0.008) end
    if hoverPath and hoverPath ~= tuneSelected then drawPartBox(hoverPath, 0.4, 0.005) end
  end
end

local function onUpdate(dtReal)
  frame = frame + 1
  if messageTimer then
    messageTimer = messageTimer - dtReal
    if messageTimer <= 0 then
      messageTimer, message = nil, nil
      sendState()
    end
  end
  if phase ~= 'idle' then
    -- the lift's pads stay under the sills: once they touch, they go wherever the car goes
    local v = veh()
    if v and restZ and (phase == 'garage' or phase == 'catalog' or phase == 'busy') then
      local rise = v:getPosition().z - restZ + v:getVelocity().z * 0.1      -- a touch ahead: the model trails
      local touching = lift.getPadHeight() >= sillHeight - 0.004
      if camera.isLift() then
        if touching then lift.setPadHeight(sillHeight + math.max(0, rise), true) else lift.setPadHeight(sillHeight) end
      elseif rise > 0.012 then
        lift.setPadHeight(sillHeight + rise, true)
      else
        lift.setPadHeight(nil)
      end
    end
    lift.update(dtReal)
  end
  if sellAllTimer then
    sellAllTimer = sellAllTimer - dtReal
    if sellAllTimer <= 0 then sellAllTimer = nil end
  end
  if phase == 'idle' then
    updateIdle(dtReal)
  elseif phase == 'garage' then
    updateGarage(dtReal)
  elseif phase == 'busy' or phase == 'film' then
    picker.update()
  end
end

----------------------------------------------------------------------------------------------
-- game hooks

local function onVehicleSpawned(id)
  -- every car gets the damage keeper while it is still new, so it knows what "undamaged" looks like
  local spawned = getObjectByID(id)
  if spawned then spawned:queueLuaCommand('extensions.load("slrrGarageVeh")') end
  if id ~= vehId then return end
  if respawnWaiter then
    settleFrames = 3
  end
end

local function onPreRender(dtReal)
  if settleFrames > 0 then
    settleFrames = settleFrames - 1
    if settleFrames == 0 and respawnWaiter then respawnWaiter() end
  end
  -- in a shop the camera is the player's own; the previews follow it from here
  if phase == 'shop' then onCameraPose(nil, nil, nil, dtReal or 0.016) end
end

-- Part models - the turning previews in front of the camera and the stand-ins on the car - are
-- placed from inside the camera's own update, so they never trail a frame behind it.
onCameraPose = function(pos, rot, fovDeg, dt)
  if phase ~= 'garage' and phase ~= 'catalog' and phase ~= 'busy' and phase ~= 'shop' then return end
  local speed = settings.get('spinSpeed') * 0.75 * (settings.get('spinClockwise') and 1 or -1)
  preview.update(dt, cameraInfo(pos, rot, fovDeg), speed, preview.hasStandins() and picker.getFrame() or nil)
end

-- something pulled the rug (vehicle switched or removed, mod reloaded): undo the visit so the
-- shelf and the car cannot disagree about where a part is
local function abort()
  if phase == 'idle' then return end
  if phase == 'shop' then leaveShop() return end
  local v = veh()
  local config = parts.revertVisit()
  if v then
    v:setMeshAlpha(1, '', false)
    v:queueLuaCommand('controller.setFreeze(0)')
    if config then v:respawn(serialize(config)) end
  end
  cleanup()
  fade = 0
  armed = false
  sendState()
end

-- our own respawns briefly tear the vehicle down too; those are not interruptions
local function onVehicleSwitched(oldId, newId)
  if respawnWaiter then return end
  if phase ~= 'idle' and vehId and newId ~= vehId then
    log('I', logTag, 'player switched vehicle, closing the garage')
    abort()
  end
end

local function onVehicleDestroyed(id)
  if respawnWaiter then return end
  if id == vehId and phase ~= 'idle' then
    log('I', logTag, 'vehicle removed, closing the garage')
    abort()
  end
end

local function onClientEndMission()
  if phase ~= 'idle' then
    camera.stop()
    picker.clear()
    preview.clear()
    lift.clear()
    shapes.release()
    parts.detach()
    damage.clear()
    phase, site, vehId, fade, shop = 'idle', nil, nil, 0, nil
  end
  armed = true
end

local function onExtensionLoaded()
  local current = getPlayerVehicle(0)
  if current then current:queueLuaCommand('extensions.load("slrrGarageVeh")') end
  log('I', logTag, 'Wrench Works loaded')
end

local function onExtensionUnloaded()
  abort()
end

-- the UI app asks for the current state when it (re)loads
local function requestState()
  sendState()
  sendHover()
  if phase == 'catalog' or phase == 'shop' then sendCatalog() end
  if mode == 'tune' and phase == 'garage' then
    sendTuning()
    sendTunePart()
  end
end

-- the game calls this while it assembles a vehicle from jbeam; the parts model uses it to
-- leave out the driver aids on a car that is built without wheels
M.onJbeamLoadingPhase2 = function(loadingProgress, objID, vehicle)
  parts.onJbeamLoadingPhase2(objID, vehicle)
end

M.onUpdate = onUpdate
M.onPreRender = onPreRender
M.onVehicleSpawned = onVehicleSpawned
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleDestroyed = onVehicleDestroyed
M.onClientEndMission = onClientEndMission
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onDamageCaptured = onDamageCaptured

M.enter = enterNearest
M.leave = leave
M.abort = abort
M.click = click
M.install = install
M.sell = sell
M.sellAll = sellAll
M.setTool = setTool
M.setMode = setMode
M.repairAll = repairAll
M.toggleFilter = toggleFilter
M.openCatalog = openCatalog
M.closeCatalog = closeCatalog
M.buy = buy
M.cartRemove = cartRemove
M.cartClear = cartClear
M.checkout = checkout
M.requestCart = sendCart
M.setPreviewSlots = setPreviewSlots
M.parkPreviews = function() preview.park() end
M.requestTuning = requestTuning
M.applyTuning = applyTuning
M.toggleOpen = toggleOpen
M.clearTunePart = function() tuneSelected = nil sendTunePart() end
M.requestPaint = sendPaint
M.setPaint = setPaint
M.requestInfo = sendInfo
M.toggleLift = toggleLift
M.toggleEngine = toggleEngine
M.advanceTime = advanceTime
M.requestSettings = requestSettings
M.setSetting = setSetting
M.cameraDrag = cameraDrag
M.cameraZoom = cameraZoom
M.focus = focus
M.resetView = resetView
M.setMouseOverUi = setMouseOverUi
M.setDragging = setDragging
M.requestState = requestState
-- test hook: behave as if the cursor pointed at a world position
M.debugPointAt = function(target)
  if phase ~= 'garage' then return nil end
  local from = core_camera.getPosition()
  local picked = picker.pick(from, (target - from):normalized(), parts.isMeshHidden)
  local partPath = picked and parts.removableAncestor(picked) or picked
  testHoverTimer = 1.5 -- keep the real cursor from overriding the test hover, briefly
  setHover(partPath)
  return picked, partPath
end
M.uiSound = function(name) if type(name) == 'string' and name:match('^[%w_]+%.wav$') then playSound(name, 0.7) end end
M.getPhase = function() return phase end

return M
