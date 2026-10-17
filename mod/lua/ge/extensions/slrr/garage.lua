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
local doorway = require('slrr/garageDoorway')
local picker = require('slrr/garagePicker')
local parts = require('slrr/garageParts')
local camera = require('slrr/garageCamera')
local damage = require('slrr/garageDamage')
local shapes = require('slrr/garageShapes')
local preview = require('slrr/garagePreview')
local lift = require('slrr/garageLift')
local settings = require('slrr/garageSettings')
local music = require('slrr/garageMusic')

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

local phase = 'idle'      -- idle | film | garage | catalog | busy | leaving | shop | lot (on foot, choosing a body shell)
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
local markerTimer = 0     -- how long the car has stood on a garage's marker
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
local setCarLift           -- set further down
local cleanup              -- set further down
local tuneSelected         -- part path picked with the screwdriver (outlined, its adjustments shown)
local pickRay, pickAge = nil, 0   -- the cursor ray the hover was last worked out for, and how long ago
local fromLot = false     -- this visit began on foot, with a body shell bought for the empty lift
local boughtShell = false -- ... and that shell is the car in the garage now
local shellPrice = 0
local lotModels           -- the body shells on offer, as last sent to the UI

----------------------------------------------------------------------------------------------
-- small helpers

local function veh()
  return vehId and getObjectByID(vehId)
end

-- Sounds are the game's own. A .wav of the same name in art/sound/slrr_garage/ takes its place.
local soundEvents = {
  ['wrench.wav'] = 'event:>Vehicle>Latches>Special>tailgate_01_open',     -- a part comes off
  ['screw.wav'] = 'event:>Vehicle>Latches>Special>tailgate_01_close',     -- a part goes on
  ['dragdrop.wav'] = 'event:>Vehicle>Latches>Special>tailgate_01_open',
  ['money.wav'] = 'event:>UI>Career>Buy_01',
  ['warn.wav'] = 'event:>UI>Career>Drift_Canceled',
  ['flip.wav'] = 'event:>UI>Bigmap>Whoosh_In',
  ['mnuback.wav'] = 'event:>UI>Bigmap>Whoosh_Out',
  ['mnuselect.wav'] = 'event:>UI>Main>select',
  ['mnumove.wav'] = 'event:>UI>Main>hover_02',
  ['ok.wav'] = 'event:>UI>Missions>Checkpoint',
  ['spray.wav'] = 'event:>UI>Career>Fueling_Petrol_Simple',
  ['repair.wav'] = 'event:>UI>Missions>Vehicle_Recover',
  ['trash.wav'] = 'event:>UI>Career>Drift_Canceled',
  ['entergarage.wav'] = 'event:>UI>Missions>Info_Open',
  ['leavegarage.wav'] = 'event:>UI>Bigmap>Whoosh_Out',
}

local function playSound(name, volume)
  if not settings.get('sounds') then return end
  local file = SOUND_DIR .. name
  if FS:fileExists(file) then
    Engine.Audio.playOnce('AudioGui', file, { volume = volume or 1 })
  elseif soundEvents[name] then
    Engine.Audio.playOnce('AudioGui', soundEvents[name], { volume = volume or 1 })
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

local function swapOf(item)
  local ok, q = pcall(parts.engineSwapQuote, item)
  return ok and q or {}
end

local function inventoryForUi()
  local list = {}
  for _, item in ipairs(parts.getInventory()) do
    list[#list + 1] = {
      id = item.id, part = item.part, name = item.name, slot = item.slot, section = item.section, photo = 'item_' .. item.id,
      value = parts.itemPrice(item), count = item.count or 1, new = item.new == true, used = item.used == true,
      damaged = parts.itemDamaged(item), repairCost = parts.itemRepairCost(item), sellValue = parts.sellValue(item),
      contents = (item.count or 1) > 1 and parts.itemContents(item) or nil,
      wear = item.wear and math.floor(item.wear * 100 + 0.5) or nil,     -- (market parts: worn this much, in %)
      swap = swapOf(item).short, swapText = swapOf(item).text,      -- (an engine for the engine slot, in a career: the labour)
    }
  end
  return list
end

-- Services other mods offer in the garage (an oil change, another of your cars, a race...). They
-- add entries to the list: onWrenchWorksServices(list, vehicleId) with
--   { id, label, desc, price (shown only), group, disabled, tab }   (tab: 'services' - the default, car servicing - 'races' or 'drivers': one top tab each)
-- and get the click back: onWrenchWorksService(id, vehicleId). Wrench Works itself offers none.
-- With the SLRR Drivers mod installed the garage offers its drivers, as SLRR's garage did.
-- A change is announced as onWrenchWorksDriverChanged(vehicleId, driverId) for mods that keep cars.
local function driverServices(list)
  if not slrrDrivers or not slrrDrivers.getDrivers or not slrrDrivers.setDriver then return end
  local current = slrrDrivers.getDriver and slrrDrivers.getDriver(vehId) or nil
  if current == 'none' then current = nil end
  list[#list + 1] = { id = 'driver:none', tab = 'drivers', group = 'Driver', label = 'No driver', desc = current and 'an empty seat' or 'in the car now', disabled = current == nil }
  for _, d in ipairs(slrrDrivers.getDrivers() or {}) do
    if type(d) == 'table' and d.id then
      list[#list + 1] = { id = 'driver:' .. tostring(d.id), tab = 'drivers', group = 'Driver', label = d.name or tostring(d.id),
        desc = d.id == current and 'in the car now' or 'put them behind the wheel', disabled = d.id == current }
    end
  end
  -- #37 the driver's outfit: shirt and trousers, and a helmet (only where this driver has a helmet mesh)
  local look = slrrDrivers.getAppearance and slrrDrivers.getAppearance(vehId) or {}
  for _, e in ipairs(require('slrr/garageOutfits').entries(current, look, current ~= nil and M.driverHasHelmet(current))) do list[#list + 1] = e end
end

local function servicesList()
  local list = {}
  driverServices(list)
  extensions.hook('onWrenchWorksServices', list, vehId)
  return list
end

-- the arrival scene's state (declared here: sendState reads it; one table, the chunk is near its limit of locals)
local scene = { on = false, skip = false }

local function sendState()
  local inGarage = phase == 'garage' or phase == 'catalog' or phase == 'busy'
  guihooks.trigger('slrrGarageState', {
    phase = phase,
    mode = mode,
    showcase = M.showcase == true,
    tool = tool,
    fade = fade,
    garage = (shop and shop.name) or (site and site.name) or nil,
    shop = shop and { name = shop.name, trade = shop.trade, discount = (not shop.yard) and settings.get('shopDiscount') or 0, yard = shop.yard } or nil,
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
    scene = scene.on,
    retro = settings.get('retroCatalog'),
    services = (phase == 'garage') and servicesList() or nil,      -- (never an empty table: it reaches the screen as an object, not a list)
    upgrades = (sl_upgrades ~= nil and parts.inCareer()) or nil,
    canStore = (phase == 'garage' and sl_fleet ~= nil and sl_fleet.carOfVehicle ~= nil and vehId ~= nil and sl_fleet.carOfVehicle(vehId) ~= nil) or nil,
    lifted = parts.getFeatures().lift, crane = parts.getFeatures().crane,
  })
end

local gs = require('slrr/garageStrings').t
local function say(text, seconds)
  message = text
  messageTimer = seconds or 3.5
  sendState()
end

-- cars other mods say aren't the player's (a career's job cars): parts off them sell for nothing
local jobCars = {}

local function sendHover()
  local d = hoverPath and parts.describe(hoverPath) or nil
  -- what the sell tool would pay for it, straight off the car (bent parts fetch half, as on the shelf)
  if d then d.sellValue = jobCars[vehId] and 0 or math.floor(d.value * settings.get('sellFactor') * (d.damaged and 0.5 or 1) + 0.5) end
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

-- every setting with its value, the other mods' groups included (the settings screen, and another mod's own screen: the phone's Settings)
local function settingsDefs()
  -- settings for another mod (the driver) only when that mod is there and new enough
  local defs = {}
  for _, d in ipairs(settings.describe()) do
    local ok = (d.needs == nil) or (d.needs == 'drivers' and slrrDrivers and slrrDrivers.setDisplayMode)
      or (d.needs == 'pedestrians' and slrrPedestrians and slrrPedestrians.setOptions)
      or (d.needs == 'appearance' and slrrDrivers and slrrDrivers.setAppearance)
      or (d.needs == 'injury' and slrrInjury and slrrInjury.setMode)
    if ok and d.dynamic and d.key == 'driverSkin' then                  -- the drivers the mod has
      d.options = { { id = '', label = 'Default' } }
      for _, dr in ipairs(slrrDrivers.getDrivers and slrrDrivers.getDrivers() or {}) do d.options[#d.options + 1] = { id = dr.id, label = dr.name or dr.id } end
    end
    if ok then defs[#defs + 1] = d end
  end
  -- other mods add their own groups (definitions in the same shape, with their value)
  extensions.hook('onWrenchWorksSettingsDefs', defs)
  return defs
end

local function sendSettings()
  guihooks.trigger('slrrGarageSettings', { defs = settingsDefs(), career = parts.inCareer() })
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
  extensions.hook('onWrenchWorksDamage', id, data)      -- other mods may keep a car's dents too
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
  -- (a car rebuilt while it was up on the lift comes back in mid-air with nothing holding it:
  -- it goes on the floor at once, before it can fall)
  local inTheAir = restZ and v:getPosition().z - restZ > 0.12
  if inTheAir or (nowCenter - center):length() > 0.12 or nowDir:dot(dir) < 0.998 then
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
  local side = math.min(site.halfWidth - 0.9, 2.4) * (site.filmSide or 1)
  if viaSide and site.exit == 'side' then
    return sites.point(site, site.exitTurnAlong - 0.6, side, 1.55)       -- right-hand wall, facing the side door
  elseif viaSide then
    return sites.point(site, math.max(site.doorDist + 1.4, -6.5), -side, 1.5)   -- on the front-door side, facing the back door
  end
  return sites.point(site, site.filmAlong or math.min(site.backDist - 0.6, 6.5), -side, 1.5)       -- on the far side, facing the front door
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

-- The arrival scene (#36, with the SLRR Drivers mod): the car has parked, the driver's door opens, the driver (the driver chosen for the car) gets out
-- and walks round the car looking it over, the door shuts. It runs in the background while the garage is already up and usable (B5: it never blocks
-- input); leaving the garage ends it.
local SCENE_MAX = 22                -- s: the scene never runs longer than this

-- where the driver walks: out of the door, round the nose and down the far side, across the back, home. Stops at the corners to look.
local function scenePath(v, driverLeft)
  local c = carCenter()
  if not c or not site then return nil end
  local f = vec3(v:getDirectionVector())
  f.z = 0
  f:normalize()
  local right = f:cross(vec3(0, 0, 1)):normalized()
  local halfL, halfW = v:getInitialLength() * 0.5, v:getInitialWidth() * 0.5
  local out = math.max(halfW + 0.35, math.min(site.halfWidth - 0.8, halfW + 1.0))
  local floorZ = sites.point(site, 0, 0, 0.03).z
  local door = driverLeft and -1 or 1
  local seat = halfL * 0.15
  local function P(along, lateral)
    local p = c + f * along + right * lateral
    p.z = floorZ
    return p
  end
  return {
    P(seat, door * (halfW + 0.45)),
    P(seat, door * out),
    { pos = P(halfL + 0.9, door * out), wait = 0.9 },
    { pos = P(halfL + 0.9, -door * out), wait = 0.9 },
    { pos = P(-halfL - 0.9, -door * out), wait = 0.9 },
    { pos = P(-halfL - 0.9, door * out), wait = 0.5 },
    P(seat, door * out),
  }
end

-- true when it ran
local function arrivalScene(job)
  if not settings.get('arrivalScene') then return false end
  local ped, drv = slrrPedestrians, slrrDrivers
  if not (ped and ped.playActor and drv and drv.getDriver and drv.setDisplayMode and drv.getDisplayMode) then return false end
  local v = veh()
  local id = v and drv.getDriver(vehId)
  if not id then return false end                      -- nobody drives it
  local dir = '/art/slrr_drivers/' .. id .. '/walker/'
  if not FS:directoryExists(dir) then return false end
  local st = drv.getState and drv.getState(vehId)
  local pts = scenePath(v, not st or st.seatLeft ~= false)
  if not pts then return false end
  scene.on, scene.skip = true, false
  sendState()
  core_jobsystem.create(driverDoorJob)                 -- the door swings open now and is pushed shut after 1.9 s
  job.sleep(0.7)
  local override = drv.getDisplayMode(vehId) ~= drv.getDisplayMode() and drv.getDisplayMode(vehId) or nil
  drv.setDisplayMode('hidden', vehId)                  -- he is out of the seat
  local actor = ped.playActor(dir, pts)
  local t = 0
  while actor and not ped.actorDone(actor) and t < SCENE_MAX and not scene.skip and phase ~= 'idle' and phase ~= 'leaving' and phase ~= 'shop' and veh() do
    job.sleep(0.05)
    t = t + 0.05
  end
  if actor then ped.stopActor(actor) end
  drv.setDisplayMode(override, vehId)                  -- back in the seat, as he was
  scene.on = false
  sendState()
  return true
end

-- a visit another mod's screen asked for (enterWith): what to open once the car is on the lift
local entryMode
local applyEntryMode

local function enterJob(job)
  local v = veh()
  if not v then phase = 'idle' return end
  local length = v:getInitialLength()
  local half = length * 0.5

  -- cut to black; everything that needs hiding happens now, so the film runs uninterrupted
  setFade(1)
  job.sleep(FADE_TIME + 0.05)
  if not fromLot then       -- (walking in has noted these already)
    previousCamera = core_camera.getActiveCamName(0)
    previousGameState = core_gamestate.state and deepcopy(core_gamestate.state) or nil
  end
  core_input_actionFilter.setGroup('slrrGarageBlocked', blockedActions)
  core_input_actionFilter.addAction(0, 'slrrGarageBlocked', true)
  v:queueLuaCommand('ai.scriptStop(true, true) ai.setMode("disabled") input.event("throttle", 0, FILTER_DIRECT) input.event("brake", 0, FILTER_DIRECT)')
  local route = entryRoute(half)

  captureDamage(job)                      -- note the dents before anything rebuilds the car
  parts.setForeign(jobCars[vehId] == true)
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
  lift.setup(site.spot, site.dir) lift.setLiftOwned(parts.getFeatures().lift) lift.setCraneOwned(parts.getFeatures().crane)           -- the car drives in between its posts
  sillHeight = measureSill()
  mode, tool = 'mechanic', nil

  if settings.get('playFilm') and not fromLot then
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
    -- the scene is eye candy in the background: the garage below is up the moment the car has stopped (a failing scene must never stop the entry)
    core_jobsystem.create(function(sceneJob)
      local okScene, ran = pcall(arrivalScene, sceneJob)
      if not okScene then
        log('E', 'slrr', 'arrival scene failed: ' .. tostring(ran))
        scene.on, ran = false, false
        if slrrDrivers and slrrDrivers.setDisplayMode then pcall(slrrDrivers.setDisplayMode, nil, vehId) end
        sendState()
      end
      if not ran and settings.get('driverDoor') then core_jobsystem.create(driverDoorJob) end
    end)
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
  if fromLot then
    -- it was bought as a bare shell: everything that unbolts is not there, and is not on the shelf either
    parts.stripToShell()
    parts.pay(shellPrice, 'Body shell')
    fromLot, boughtShell = false, true
  end
  phase = 'garage'
  sendState()
  sendHover()
  if entryMode and applyEntryMode then applyEntryMode() end
  entryMode = nil
end

local function startEnter(_site, id, side, wantMode)
  if phase ~= 'idle' then return end
  local open, why = parts.providerGarage(_site.id)
  if not open then say(why or gs('say.not_yet'), 5) return end
  entryMode = wantMode
  site = _site
  viaSide = side == true
  vehId = id
  phase = 'film'
  armed = false
  core_gamestate.setGameState('slrrGarage', 'slrrGarage', 'freeroam')
  sendState()
  core_jobsystem.create(enterJob)
end

-- On foot the doorway leads to the same garage, with nothing on the lift: a place to start a
-- car from nothing. Any car's bare body shell can be bought there; it is put on the lift and
-- from then on it is an ordinary visit.
local function sendLot()
  lotModels = {}
  local ok, list = pcall(function() return core_vehicles.getModelList(true).models end)
  local factor = settings.get('shellPrice') * settings.get('priceMultiplier')
  for _, m in ipairs(ok and type(list) == 'table' and list or {}) do
    if type(m) == 'table' and type(m.key) == 'string' and (m.Type == 'Car' or m.Type == 'Truck') then
      local full = core_vehicles.getModel(m.key)
      local cfg = full and full.configs and m.default_pc and full.configs[m.default_pc]
      local value = cfg and tonumber(cfg.Value) or 8000
      lotModels[#lotModels + 1] = {
        key = m.key, name = tostring(m.Name or m.key), brand = tostring(m.Brand or ''),
        price = math.floor(value * factor / 50 + 0.5) * 50, preview = type(m.preview) == 'string' and m.preview or nil,
      }
    end
  end
  table.sort(lotModels, function(a, b)
    if a.brand ~= b.brand then return a.brand < b.brand end
    return a.name < b.name
  end)
  guihooks.trigger('slrrGarageLot', { models = lotModels })
end

local function startLot(_site)
  if phase ~= 'idle' then return end
  local open, why = parts.providerGarage(_site.id)
  if not open then say(why or gs('say.not_yet'), 5) return end
  armed = false
  if parts.inCareer() then
    if ui_message then ui_message('In career mode cars come from the dealership. Drive one in to work on it.', 6, 'slrrGarage') end
    return
  end
  site, viaSide, vehId, shop = _site, false, nil, nil
  phase = 'lot'
  previousCamera = core_camera.getActiveCamName(0)
  previousGameState = core_gamestate.state and deepcopy(core_gamestate.state) or nil
  core_gamestate.setGameState('slrrGarage', 'slrrGarage', 'freeroam')
  core_input_actionFilter.setGroup('slrrGarageBlocked', blockedActions)
  core_input_actionFilter.addAction(0, 'slrrGarageBlocked', true)
  centreZOffset = nil
  -- the camera looks at the empty lift the way it would look at a car standing on it
  camera.setup(site, function() return carCenter() or sites.point(site, 0, 0, 0.7) end, 4.5, false)
  camera.onPose = onCameraPose
  lift.setup(site.spot, site.dir) lift.setLiftOwned(parts.getFeatures().lift) lift.setCraneOwned(parts.getFeatures().crane)
  camera.startOrbit(false)
  core_camera.setByName(0, 'slrrGarage', false)
  playSound('entergarage.wav')
  sendState()
  sendLot()
end

local function buyShell(key)
  if phase ~= 'lot' then return end
  local entry
  for _, m in ipairs(lotModels or {}) do
    if m.key == key then entry = m end
  end
  if not entry then return end
  if parts.getMoney() < entry.price then
    playSound('warn.wav', 0.6)
    say(gs('say.shell_no_money'))
    return
  end
  phase = 'film'
  fromLot, shellPrice = true, entry.price
  sendState()
  core_jobsystem.create(function(job)
    setFade(1)
    job.sleep(FADE_TIME + 0.05)
    local ok, car = pcall(core_vehicles.spawnNewVehicle, entry.key, {
      pos = sites.point(site, 0, 0, 0.3), rot = quatFromDir(site.dir, vec3(0, 0, 1)),
      autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false,
    })
    local id = ok and car and car:getID()
    local waited = 0
    while id and not core_vehicle_manager.getVehicleData(id) and waited < 15 do
      job.sleep(0.1)
      waited = waited + 0.1
    end
    if not id or not core_vehicle_manager.getVehicleData(id) or phase ~= 'film' then
      -- no car came of it: back to the list, nothing paid
      if id and getObjectByID(id) then getObjectByID(id):delete() end
      if phase == 'film' then
        fromLot, phase = false, 'lot'
        setFade(0)
        say(gs('say.shell_not_delivered'))
      end
      return
    end
    job.sleep(0.3)
    vehId = id
    -- the player takes the seat (and the walking figure is put away)
    if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(getObjectByID(id)) else be:enterVehicle(0, getObjectByID(id)) end
    previousCamera = nil      -- what was noted on the way in was the walking camera; the car gets its own
    job.sleep(0.25)
    enterJob(job)
    if phase == 'garage' then say(gs('say.shell_on_lift', entry.name), 5) end
  end)
end

local function leaveLot()
  if phase ~= 'lot' then return end
  playSound('mnuback.wav')
  cleanup()
  fade, armed = 0, false
  sendState()
end

----------------------------------------------------------------------------------------------
-- leaving

cleanup = function()
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
  fromLot, boughtShell = false, false
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

-- Career mode keeps its own record of what is on each car you own. After the car has been
-- rebuilt, career is asked to read it again, so its record (and the saved car) match what
-- left the garage. Parts taken off live on this garage's shelf, not in career's own store.
local function syncCareer()
  if not parts.inCareer() or not career_modules_inventory or not career_modules_partInventory then return end
  local ok, err = pcall(function()
    local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId(vehId)
    if inventoryId and career_modules_partInventory.updatePartsToMatchSpawnedVehicle then
      career_modules_partInventory.updatePartsToMatchSpawnedVehicle(inventoryId)
    end
  end)
  if not ok then log('W', logTag, 'could not update the career record of this car: ' .. tostring(err)) end
end

local function leaveJob(job)
  local store, vid = M.storeOnLeave, vehId      -- (B9: 'store' or 'walk': the car is put away once it stands outside, and you are on foot)
  M.storeOnLeave = nil
  local missing = parts.missingEssentials()
  local v = veh()
  local half = v and v:getInitialLength() * 0.5 or 2.2
  -- doors and lids that stand open (the driver's door, anything opened with the screwdriver)
  -- are pushed shut: an open door does not survive the doorway
  if v then v:queueLuaCommand('if slrrGarageVeh then slrrGarageVeh.shutLatches() end') end
  setFade(1)
  job.sleep(FADE_TIME + 0.05)
  preview.setSlots({})
  lift.setArms(false, true)
  lift.setPadHeight(nil, true)
  if camera.isLift() then
    camera.setLift(false)
    if parts.isDirty() then
      -- the car is about to be rebuilt: let go, it is put right on the floor
      if v then v:queueLuaCommand('if slrrGarageVeh then slrrGarageVeh.releaseLift() end') end
      job.sleep(0.6)
    else
      -- this car leaves as it is, so it comes down the way it went up instead of being dropped
      setCarLift(false)
      job.sleep(settings.get('liftHeight') / 0.55 + 0.4)
    end
  end
  if parts.isDirty() then
    respawnWithDesired(job, true)
    job.sleep(0.2)
    syncCareer()
  elseif parts.paintsDirty() and core_vehicle_partmgmt then
    -- the new colours are already on the car; make them part of its config too
    core_vehicle_partmgmt.setConfigPaints(parts.getPaints(), false)
  end
  -- the car as it leaves (its final parts tree and how many dents are left), for other mods: a career's
  -- repair ticket is checked here
  local vd = core_vehicle_manager.getVehicleData(vehId)
  extensions.hook('onWrenchWorksDriveOut', vehId, { partsTree = vd and vd.config and vd.config.partsTree, dents = damage.countAll() })
  parts.detach()
  picker.clear()
  freezeCar(false)
  -- The latches are pushed shut NOW, with the car free to move. The damage put back after a rebuild lets every latch go and pushes
  -- them shut again from the car's own update, but the car was frozen while that ran, and a frozen car cannot latch: the retries
  -- were spent before it moved and the doors were left open (B64). shutLatches starts the retries afresh.
  do
    local lv = veh()
    if lv then lv:queueLuaCommand('if slrrGarageVeh then slrrGarageVeh.shutLatches() end') end
  end

  local route = exitRoute(half)
  local outside = false
  centreZOffset, restZ = nil, nil
  v = veh()
  if v and settings.get('playFilm') and not missing then
    -- the car drives itself out while the camera stays behind in the garage
    v:queueLuaCommand('input.event("parkingbrake", 0, FILTER_DIRECT)')
    camera.startExit()
    job.sleep(0.9)
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
    if v then v:queueLuaCommand('ai.scriptStop(true, true) ai.setMode("disabled") input.event("throttle", 0, FILTER_DIRECT) input.event("brake", 0, FILTER_DIRECT) if slrrGarageVeh then slrrGarageVeh.shutLatches() end') end      -- (and once more, outside)
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
  if store and sl_fleet and sl_fleet.carOfVehicle and sl_fleet.despawn then
    local carId = sl_fleet.carOfVehicle(vid)
    if carId then
      local _, text = sl_fleet.despawn(carId)
      if ui_message then ui_message((text or '') .. ' ' .. gs(store == 'walk' and 'say.walk_hint' or 'say.store_hint'), 7, 'slrrGarage') end
    end
  end
end

-- Drive out. First the job sheet: what was done to the car this visit and what it cost.
local function leave(confirmed)
  if phase == 'catalog' then phase = 'garage' sendState() end      -- (Drive out from the catalog closes it first)
  if phase ~= 'garage' then return end
  if settings.get('jobSheet') and confirmed ~= true then
    local sheet = parts.visitSummary()
    if #sheet.fitted > 0 or #sheet.removed > 0 or sheet.net ~= 0 or sheet.tuned or sheet.painted then
      playSound('flip.wav')
      guihooks.trigger('slrrGarageJobSheet', sheet)
      return
    end
  end
  phase = 'leaving'
  setHover(nil)
  sendState()
  core_jobsystem.create(leaveJob)
end

-- B9: whatever car is on the lift, you can leave: drive out (above), put the car away and stay on foot (store / switch car), or walk out and leave it in the garage.
-- Both put the car away in the career (it waits in the garage; the phone's Cars app brings another, or this one, out).
M.storeCar = function(how)
  if phase ~= 'garage' or not (sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vehId)) then return end
  M.storeOnLeave = how == 'walk' and 'walk' or 'store'
  leave(true)
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

-- With labour switched on, taking a part off or fitting it takes time, more for heavy parts.
local function work(what, weight, fn)
  if not settings.get('labour') then
    fn()
    return
  end
  local seconds = clamp(0.6 + (weight or 2) * 0.04, 0.6, 9) / settings.get('labourSpeed')
  phase = 'busy'
  setHover(nil)
  sendState()
  guihooks.trigger('slrrGarageWork', { what = what, seconds = seconds })
  core_jobsystem.create(function(job)
    job.sleep(seconds)
    guihooks.trigger('slrrGarageWork', {})
    if phase ~= 'busy' then return end
    phase = 'garage'
    fn()
    sendState()
  end)
end

local sell                 -- set further down

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
    extensions.hook('onWrenchWorksRepaired', vehId, res)      -- (the car on the lift was repaired, for this much)
    tool = nil
    core_jobsystem.create(applyInGarage)
    return
  end
  if mode == 'tune' and tool ~= 'sell' then
    tuneClick(hoverPath)
    return
  end
  local path = hoverPath
  local d = parts.describe(path)
  if not d then return end
  if not d.removable then
    playSound('warn.wav', 0.6)
    say(d.reason or gs('say.cannot_come_off'))
    return
  end
  work('Taking off the ' .. d.name, parts.partWeight(d.partName), function()
    local item, err = parts.removePart(path)
    if not item then
      playSound('warn.wav', 0.6)
      say(err or gs('say.cannot_come_off'))
      return
    end
    playSound('wrench.wav')
    if parts.needsCrane(path) then lift.craneRun('out') end
    hoverPath = nil
    pickRay = nil
    sendHover()
    if tool == 'sell' then        -- the sell tool takes it off the car and straight over the counter
      sell(item.id)
      return
    end
    sendState()
    guihooks.trigger('slrrGarageItemAdded', { id = item.id })
  end)
end

sell = function(itemId)
  if phase ~= 'garage' and phase ~= 'catalog' then return end
  local ok, item, value = parts.sellItem(tonumber(itemId))
  if ok then
    extensions.hook('onWrenchWorksPartSold', vehId, item.slotPath, item.part, value)     -- (a career's salvage job counts them)
    playSound('money.wav')
    say(gs('say.sold_part', item.name, value), 2.5)
  end
end

-- sell everything on the shelf. It asks first: the second click within a few seconds does it.
local function sellAll()
  if phase ~= 'garage' then return end
  local count = #parts.getInventory()
  if count == 0 then
    say(gs('say.shelf_empty'), 2.5)
    return
  end
  if not sellAllTimer and settings.get('confirmSellAll') then
    sellAllTimer = 5
    playSound('warn.wav', 0.5)
    say(gs('say.sell_all_confirm', count, parts.shelfValue()), 5)
    return
  end
  sellAllTimer = nil
  local items = {}
  for _, it in ipairs(parts.getInventory()) do items[#items + 1] = { it.slotPath, it.part, parts.sellValue(it) } end
  local sold, total = parts.sellAll()
  for _, it in ipairs(items) do extensions.hook('onWrenchWorksPartSold', vehId, it[1], it[2], it[3]) end
  playSound('money.wav')
  say(gs('say.sold_parts', sold, total), 3)
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
  local wanted
  for _, item in ipairs(parts.getInventory()) do
    if item.id == tonumber(itemId) then wanted = item end
  end
  if not wanted then return end
  work('Fitting the ' .. wanted.name, parts.partWeight(wanted.part), function()
    local ok, text, needsLoad = parts.installItem(tonumber(itemId))
    if not ok then
      playSound('warn.wav', 0.6)
      say(text)
      return
    end
    playSound('screw.wav')
    if parts.needsCrane(wanted.slotId or wanted.slotPath) then lift.craneRun('in') end
    if needsLoad then
      core_jobsystem.create(applyInGarage)
    else
      sendState()
    end
  end)
end

-- fit everything on the shelf that was bought and has not been on the car yet
local function installNew()
  if phase ~= 'garage' then return end
  local count, weight = 0, 0
  for _, item in ipairs(parts.getInventory()) do
    if item.new or item.used then count, weight = count + 1, weight + parts.partWeight(item.part) end
  end
  if count == 0 then return end
  work('Fitting ' .. count .. ' new parts', weight, function()
    local fitted, needsLoad = parts.installNew()
    if fitted == 0 then
      playSound('warn.wav', 0.6)
      say(gs('say.nothing_to_bolt'))
      return
    end
    playSound('screw.wav')
    say(fitted == count and gs('say.parts_fitted', fitted) or gs('say.parts_fitted_some', fitted, count), 3.5)
    if needsLoad then core_jobsystem.create(applyInGarage) end
  end)
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
  extensions.hook('onWrenchWorksRepaired', vehId, res)
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
    for _, key in ipairs(shop.sells or {}) do sells[key] = true end
    if shop.yard or shop.all then sells = nil end  -- the yard sells anything it happens to have; so does a shop without a list
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

-- the visit started with enterWith: open the catalog, the tune mode, the repair tool or the paint drawer on the car
applyEntryMode = function()
  local m = entryMode
  entryMode = nil
  if m == 'catalog' then openCatalog()
  elseif m == 'tune' then setMode('tune')
  elseif m == 'repair' then setTool('repair')
  elseif m == 'paint' then guihooks.trigger('slrrGaragePanel', { panel = 'paint' }) end
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
local function buy(slotPath, partName, sub)
  if phase ~= 'catalog' and phase ~= 'shop' then return end
  local ok, res = parts.cartAdd(slotPath, partName, sub)
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

-- confirm the shopping list: pay, and the parts go on the shelf (shop), on their way (garage), or on the car at once ("Fit them here")
local function checkout(shippingId)
  if phase ~= 'catalog' and phase ~= 'shop' then return end
  -- the car is rebuilt at the counter (after "Fit them here"): as in the garage, without the lift and the camera
  local function applyInShop(job)
    phase = 'busy'
    setFade(1)
    job.sleep(FADE_TIME)
    respawnWithDesired(job, false)
    job.sleep(0.2)
    freezeCar(true)
    parts.attach(vehId, true)
    job.sleep(0.1)
    phase = 'shop'
    setFade(0)
    sendState()
    sendCatalog()
  end
  local ok, text, bought, fitHere = parts.checkout(tostring(shippingId), shop ~= nil)
  if not ok then
    playSound('warn.wav', 0.6)
    say(text)
    return
  end
  for _, p in ipairs(bought or {}) do     -- paid: other mods may count spending (a career's tune-to-spec budget)
    extensions.hook('onWrenchWorksPartBought', vehId, p.slotPath, p.part, p.price)
  end
  playSound('money.wav')
  say(text, 4)
  sendCatalog()
  if fitHere and phase == 'shop' then
    local fitted, needsLoad = parts.installNew()
    if fitted == 0 then
      playSound('warn.wav', 0.6)
      say(gs('say.nothing_to_bolt'))
      return
    end
    playSound('screw.wav')
    say(fitted == #bought and gs('say.parts_fitted', fitted) or gs('say.parts_fitted_some', fitted, #bought), 3.5)
    if needsLoad then core_jobsystem.create(applyInShop) else sendState() end
  end
end

-- deliveries that have arrived go on the shelf
local function checkDeliveries()
  local arrived = parts.collectDeliveries()
  if arrived > 0 then
    playSound('ok.wav')
    say(arrived == 1 and gs('say.delivery_one') or gs('say.delivery_many', arrived), 4)
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
  parts.setForeign(jobCars[vehId] == true)
  parts.attach(vehId, false)
  parts.cartClear()
  -- other mods may take a share more off at this shop (a career's perks): { extra = 0..0.5 }
  local more = { extra = 0 }
  extensions.hook('onWrenchWorksShopOpened', shop, more)
  parts.setCounterDiscount((shop.yard and 0 or settings.get('shopDiscount') / 100) + math.max(0, math.min(0.5, tonumber(more.extra) or 0)))
  parts.setYard(shop.yard == true)
  parts.setAtShop(true)
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
  parts.setYard(false)
  parts.setAtShop(false)
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
    say(gs('say.adjusted'), 3)
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
  if not parts.getFeatures().paint then say(gs('say.no_booth')) return end
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
  if phase ~= 'garage' or not parts.getFeatures().paint then return end
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
  info.builds = parts.getBuilds()
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
  local v = veh()
  if v then v:queueLuaCommand('extensions.load("slrrGarageVeh") slrrGarageVeh.dyno()') end   -- the power curve follows
  info.note = (parts.isDirty() or parts.paintsDirty()) and 'Figures are for the car as it came in; your changes take effect when you drive out.' or nil
  guihooks.trigger('slrrGarageInfo', info)
end

-- lift: raise the car off the floor (the camera may then look up at it from below)
setCarLift = function(on)
  local v = veh()
  if not v then return end
  v:queueLuaCommand('extensions.load("slrrGarageVeh") slrrGarageVeh.setLift(' .. (on and settings.get('liftHeight') or 0) .. ')')
end

local function toggleLift()
  if phase ~= 'garage' then return end
  if not camera.isLift() and not parts.getFeatures().lift then
    playSound('warn.wav', 0.6)
    say(gs('say.no_lift'), 4)
    return
  end
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

-- Wrench Works: Drivers & Pedestrians: the "Driver" setting picks how its drivers are shown
-- (hidden, not in first person, full, still); only with a version of the mod that has setDisplayMode
local function driversCanDisplay() return slrrDrivers ~= nil and slrrDrivers.setDisplayMode ~= nil end
-- and its pedestrians: the World group's settings (each def's `ped` names the option), only when one differs
local function applyPedestrians()
  if not (slrrPedestrians and slrrPedestrians.setOptions) then return end
  local now = slrrPedestrians.getOptions and slrrPedestrians.getOptions() or {}
  local want, differs = {}, false
  for _, d in ipairs(settings.defs) do
    if d.ped then
      want[d.ped] = settings.get(d.key)
      if now[d.ped] ~= want[d.ped] then differs = true end
    end
  end
  if differs then slrrPedestrians.setOptions(want) end
end

-- and how the driver looks: the Driver look group, sent only when something differs
local COLOURS = { black = { 0.05, 0.05, 0.06 }, white = { 0.9, 0.9, 0.9 }, red = { 0.75, 0.08, 0.08 }, blue = { 0.1, 0.25, 0.7 },
  green = { 0.12, 0.45, 0.18 }, orange = { 0.95, 0.45, 0.05 }, grey = { 0.45, 0.45, 0.47 } }
local function applyAppearance()
  if not (slrrDrivers and slrrDrivers.setAppearance) then return end
  local colour = function(key) return COLOURS[settings.get(key)] or false end
  local skin = settings.get('driverSkin')
  local want = { shirt = colour('driverShirt'), trousers = colour('driverTrousers'), scale = settings.get('driverScale'),
    helmet = settings.get('driverHelmet') == true, helmetColor = COLOURS[settings.get('driverHelmetColor')] or COLOURS.white }
  if skin and skin ~= '' then want.skin = skin end
  local now = slrrDrivers.getAppearance and slrrDrivers.getAppearance() or {}
  local same = true
  for k, v in pairs(want) do
    if type(v) == 'table' then
      local n = now[k]
      if type(n) ~= 'table' or math.abs((n[1] or n.r or -1) - v[1]) > 1e-3 or math.abs((n[2] or n.g or -1) - v[2]) > 1e-3 or math.abs((n[3] or n.b or -1) - v[3]) > 1e-3 then same = false end
    elseif v == false then
      if now[k] then same = false end
    elseif now[k] ~= v then same = false end
  end
  if not same then slrrDrivers.setAppearance(nil, want) end
end

-- and the picture: the Graphics group (slrr/graphics), applied when it changes, at the start of a level and when the anti-aliasing type changes
-- (a field of the module table, not a local: this file is at LuaJIT's limit of 200 locals)
M.applyGraphics = function()
  require('slrr/graphics').onSettingsChanged()
end

local function applyDriverAnimation()
  applyPedestrians()
  applyAppearance()
  if not driversCanDisplay() then return end
  local mode = settings.get('driverMode') or 'full'
  -- only when it differs: setting it restarts every driver's animation and saves their settings file
  if not slrrDrivers.getDisplayMode or slrrDrivers.getDisplayMode() ~= mode then slrrDrivers.setDisplayMode(mode) end
end

local function setSetting(key, value)
  if key == '__reset' then settings.reset() extensions.hook('onWrenchWorksSetting', key)
  elseif not settings.set(key, value) then extensions.hook('onWrenchWorksSetting', key, value) end   -- (another mod's setting)
  if key == 'driverMode' or key == '__reset' or key:find('^ped') or key:find('^driver') then applyDriverAnimation() end
  if key == 'freeroamMoney' then parts.setWallet(settings.get('freeroamMoney')) end
  if (key == 'injuryMode' or key == '__reset') and slrrInjury and slrrInjury.setMode then slrrInjury.setMode(settings.get('injuryMode')) end
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
  if best and v:getJBeamFilename() == 'unicycle' then
    if parts.providerAllows('walkIn') then startLot(best) end
  elseif best then
    startEnter(best, v:getID(), second)
  end
end

-- the garage (site) whose doors are within 50 m of a point, for another mod's screen ("is this car at that garage?")
local function garageAt(pos)
  local best, bestDist
  for _, s in ipairs(sites.getSites()) do
    for _, door in ipairs(sites.doors(s)) do
      local d = (pos - door.pos):length()
      if d < 50 and (not bestDist or d < bestDist) then best, bestDist = s, d end
    end
  end
  return best
end

-- another mod's screen (Street Legal's laptop) sends a car into the garage it stands at and opens it in a mode:
-- 'catalog', 'tune', 'paint' or 'repair'. The same visit as driving in (the player is put in the car first, as the doorway does).
-- false and a reason when it cannot (busy, no such car, not at a garage)
local ENTRY_MODES = { catalog = true, tune = true, paint = true, repair = true, work = true }      -- (work: the visit as it is, no mode opened)
local function enterWith(id, wantMode)
  if phase ~= 'idle' then return false, 'The garage is busy.' end
  if not ENTRY_MODES[wantMode] then return false, 'Unknown mode.' end
  local car = getObjectByID(tonumber(id) or -1)
  if not car then return false, 'The car is not here.' end
  local at = garageAt(car:getPosition())
  if not at then return false, 'Bring the car into the garage first.' end
  local player = getPlayerVehicle(0)
  if not player or player:getID() ~= car:getID() then
    if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(car) else be:enterVehicle(0, car) end
  end
  startEnter(at, car:getID(), false, wantMode)
  return true
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
    local label = settings.get('autoEnter') and (s.name .. ' - stop here or drive in') or s.name
    debugDrawer:drawTextAdvanced(base + vec3(0, 0, 3.1), String(label), markerTextColor, true, false, markerTextBg)
  end
end

-- shops: a blue marker on their forecourt; stop on it to go in
local shopColor = ColorF(0.1, 0.55, 1, 0.25)
-- in a Street Legal career the shops keep its hours (sl/core/hours, absent without it)
local function shopClosedText()
  local _, career = parts.providerCar()
  local ok, hours = pcall(require, 'sl/core/hours')
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  if not (career and ok and type(tod) == 'table' and tod.time) then return nil end
  -- the career's night phase shuts the counter (D2) whatever the clock says
  if sl_career and sl_career.phase and sl_career.phase() == 'night' then return 'Closed. Opens in the morning.' end
  return hours.closedText('shop', tod.time)
end

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
      local closed = shopClosedText()
      if closed then
        shopArmed = false      -- (said once; the counter works again once you have left it)
        if ui_message then ui_message(closed, 5, 'slrrGarage') end
      else
        enterShop(on, v:getID())
      end
    end
  else
    shopTimer = 0
  end
end

-- on foot at a doorway with the car stored: the career is bringing it out; when it stands there we go in with it
local fetching

local function updateIdle(dt)
  local v = getPlayerVehicle(0)
  if not v then return end
  local onFoot = v:getJBeamFilename() == 'unicycle'
  if not onFoot then updateShops(v, dt) end      -- the shops sell parts for the car you came in
  if phase ~= 'idle' then return end
  local list = sites.getSites()
  if #list == 0 then return end
  -- out driving: say so, once, when an order has reached the garage
  deliveryTimer = deliveryTimer + dt
  if deliveryTimer > 3 then
    deliveryTimer = 0
    local arrived = parts.announceArrivals()
    if arrived > 0 and ui_message then
      playSound('ok.wav')
      ui_message(arrived == 1 and 'Your part has been delivered. It is waiting at the garage.' or (arrived .. ' parts have been delivered. They are waiting at the garage.'), 6, 'slrrGarage')
    end
  end
  local pos = v:getPosition()
  local centre = v:getSpawnWorldOOBB():getCenter()
  local heading = v:getDirectionVector()
  local nose = centre + heading * (v:getInitialLength() * 0.5)
  if fetching then
    fetching.t = fetching.t + dt
    local car = parts.providerCar()
    if car then
      local f = fetching
      fetching = nil
      if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(car) else be:enterVehicle(0, car) end
      startEnter(f.site, car:getID(), f.second)
    elseif fetching.t > 25 then
      fetching = nil
    end
    return
  end
  local nearDoor, onMarker = false, false
  for _, s in ipairs(list) do
    if (pos - s.spot):squaredLength() < 110 * 110 then
      local open, why = parts.providerGarage(s.id)
      for _, door in ipairs(sites.doors(s)) do
        local distance = (pos - door.pos):length()
        local base = door.pos - door.inward * 1.2
        if not open then
          -- a garage above your level: no marker, no way in; at its door it says why, once
          if armed and distance < 3.5 then
            armed = false
            say(why or gs('say.not_yet'), 6)
          end
          if distance < 12 then nearDoor = true end
          goto nextDoor
        end
        if distance < 90 and settings.get('markers') then drawMarker(s, distance, base) end
        if (onFoot and distance < 5) or (not onFoot and (centre - door.pos):length() < 9) then nearDoor = true end
        -- stopping on the marker goes in too, whichever way the car faces (as a shop's marker does)
        if armed and settings.get('autoEnter') and not onFoot and (pos - base):length() < 2.2 then
          onMarker = true
          if v:getVelocity():length() < 1 then
            markerTimer = markerTimer + dt
            if markerTimer > 1 then
              markerTimer = 0
              startEnter(s, v:getID(), door.id == 'second')
              return
            end
          else
            markerTimer = 0
          end
        end
        -- the way in is the doorway itself: the nose of the car reaching the door, heading in; a walker anywhere in it, any way, any speed
        local rel = (onFoot and pos or nose) - door.pos
        local depth = rel:dot(door.inward)
        local across = math.abs(rel:dot(vec3(-door.inward.y, door.inward.x, 0)))
        local inZone = onFoot and doorway.footZone(depth, across, s.halfWidth) or (not onFoot and doorway.carZone(depth, across))
        if armed and settings.get('autoEnter') and inZone then
          local vel = v:getVelocity()
          if onFoot then
            -- walking in: the lift is empty, and there are body shells for sale
            if settings.get('walkIn') and parts.providerAllows('walkIn') then
              startLot(s)
              return
            else
              armed = false      -- (once; the doorway works again when you have left it)
              -- in a career the doorway shows the career's garage panel: take another car out, put this one away
              if parts.providerPanel(s.id) then return end
              local car, career = parts.providerCar()
              if car then
                if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(car) else be:enterVehicle(0, car) end
                startEnter(s, car:getID(), door.id == 'second')
                return
              elseif career then
                armed = false      -- (said once; the doorway works again once you have left it)
                if parts.providerFetch() then
                  -- your car is in the garage: the career brings it out front and we go in with it
                  fetching = { site = s, second = door.id == 'second', t = 0 }
                  if ui_message then ui_message('Bringing your car out...', 4, 'slrrGarage') end
                elseif ui_message then ui_message('Your car is not out. Get it from My cars on the phone, then walk or drive in.', 6, 'slrrGarage') end
                return
              end
            end
          -- at walking pace only: anything faster is somebody driving (or drifting) through
          elseif vel:length() < settings.get('enterSpeed') / 3.6 and heading:dot(door.inward) > 0.55 and vel:dot(door.inward) > 0.3 then
            startEnter(s, v:getID(), door.id == 'second')
            return
          end
        end
        ::nextDoor::
      end
    end
  end
  if not onMarker then markerTimer = 0 end
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
    pickRay = nil
  else
    -- Finding the part under the cursor goes through the vertices of the whole car. It is done
    -- when the cursor or the camera has moved, at most 30 times a second, and a few times a
    -- second regardless, for parts that have come off or gone on in the meantime.
    local ray = getCameraMouseRay()
    pickAge = pickAge + dt
    if not ray then
      setHover(nil)
      pickRay = nil
    else
      local moved = not pickRay or (ray.pos - pickRay.pos):squaredLength() > 1e-10 or (ray.dir - pickRay.dir):squaredLength() > 1e-10
      if (moved and pickAge > 0.033) or pickAge > 0.25 then
        pickRay, pickAge = { pos = vec3(ray.pos), dir = vec3(ray.dir) }, 0
        local picked = picker.pick(ray.pos, ray.dir, parts.isMeshHidden)
        setHover(picked and parts.removableAncestor(picked) or picked)
      end
    end
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
  require('slrr/graphics').tick(dtReal)
  music.update(dtReal, phase ~= 'idle', (site and sites.radio(site)) or (shop and shop.pos + vec3(0, 0, 1.5)) or nil)
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
    if M.showcase and phase == 'garage' then camera.rotate(dtReal * 28.6, 0) end      -- #32 the showcase: a slow turn round the car (about 40 s a lap)
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
  applyDriverAnimation()                                   -- (cheap; the drivers mod may have loaded after us)
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
  if v and boughtShell then
    v:delete()        -- a body shell bought on this visit goes back with the money
  elseif v then
    v:setMeshAlpha(1, '', false)
    v:queueLuaCommand('controller.setFreeze(0) if slrrGarageVeh then slrrGarageVeh.setLift(0) end')
    if config then
      v:setDynDataFieldbyName('autoEnterVehicle', 0, 'false')   -- the player may be elsewhere by now: a respawn would take them
      v:respawn(serialize(config))
    end
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
  require('slrr/graphics').onLevelEnd()
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
  music.stop()
  sites.reload()
  armed = true
end

local function onExtensionLoaded()
  local current = getPlayerVehicle(0)
  if current then current:queueLuaCommand('extensions.load("slrrGarageVeh")') end
  applyDriverAnimation()
  require('slrr/graphics').ensureDefaults()
  require('slrr/graphics').installOptions()
  M.applyGraphics()
  log('I', logTag, 'Wrench Works loaded')
end

local function onExtensionUnloaded()
  abort()
  music.stop()
  require('slrr/graphics').apply({})        -- the game's own anti-aliasing, shaders and effects again
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
M.onClientPostStartMission = function() M.applyGraphics() end
M.onModDeactivated = function(modData)       -- (the game: a mod was switched off) ours: take our group out of the Options page again
  local name = type(modData) == 'table' and tostring(modData.modname or modData.modID or '') or ''
  if name:find('slrr_garage', 1, true) then require('slrr/graphics').uninstallOptions() end
end
M.onSettingsChanged = function() M.applyGraphics() end            -- (the game's: some setting changed, the Graphics group of Options is ours too)
M.onPreRender = onPreRender
M.onVehicleSpawned = onVehicleSpawned
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleDestroyed = onVehicleDestroyed
M.onClientEndMission = onClientEndMission
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onDamageCaptured = onDamageCaptured
-- the dyno's "before": the first run on a model (kept between visits), or the run pinned as baseline;
-- later runs are drawn over it
local DYNO_FILE = '/settings/slrr_garage/dyno.json'
local dynoBase, lastDyno
local function modelOf(id) local v = getObjectByID(id) return v and v:getJBeamFilename() or nil end
local function sendDyno()
  if not lastDyno then return end
  local out = shallowcopy(lastDyno.data)
  if not parts.getFeatures().dyno then out.torque, out.power, out.noCurve = nil, nil, true end     -- (no dyno: the figures, no curve)
  local base = dynoBase and dynoBase[lastDyno.model]
  if base and base.maxPower and (base.maxPower ~= out.maxPower or base.maxTorque ~= out.maxTorque) then out.baseline = base end
  guihooks.trigger('slrrGarageDyno', out)
end
M.onDyno = function(id, data)
  extensions.hook('onWrenchWorksDyno', id, data)      -- other mods may want the figures (a career's tuning challenge)
  if id ~= vehId or type(data) ~= 'table' then return end
  local model = modelOf(id)
  dynoBase = dynoBase or jsonReadFile(DYNO_FILE) or {}
  if model and data.maxPower and not dynoBase[model] then
    dynoBase[model] = data
    jsonWriteFile(DYNO_FILE, dynoBase, true)
  end
  lastDyno = { model = model, data = data }
  sendDyno()
end
-- "Pin this run as baseline"
M.pinDyno = function()
  if not lastDyno or not lastDyno.model then return end
  dynoBase = dynoBase or jsonReadFile(DYNO_FILE) or {}
  dynoBase[lastDyno.model] = lastDyno.data
  jsonWriteFile(DYNO_FILE, dynoBase, true)
  sendDyno()
end

M.enter = enterNearest
M.enterWith = enterWith
M.garageAt = function(pos) local g = garageAt(pos) return g and g.id or nil end   -- (the site's id, for comparing)
M.leave = leave
M.skipScene = function() scene.skip = true end
M.abort = abort
M.click = click
M.install = install
M.installNew = installNew
M.buyShell = function(key) buyShell(tostring(key)) end
M.leaveLot = function() leaveLot() end
M.sell = sell
M.saveBuild = function(name)
  if phase ~= 'garage' then return end
  local ok, saved = parts.saveBuild(name)
  if ok then playSound('ok.wav') say(gs('say.saved_as', saved), 2.5) end
  sendInfo()
end
M.deleteBuild = function(index)
  parts.deleteBuild(tonumber(index) or 0)
  sendInfo()
end
M.loadBuild = function(index)
  if phase ~= 'garage' then return end
  local ok, text = parts.loadBuild(tonumber(index) or 0)
  playSound(ok and 'screw.wav' or 'warn.wav', ok and 1 or 0.6)
  say(text, 4)
  sendState()
  sendInfo()
end
M.sellAll = sellAll
M.setTool = setTool
M.setMode = setMode
M.repairAll = repairAll
M.toggleFilter = toggleFilter
M.openCatalog = openCatalog
M.closeCatalog = closeCatalog
M.buy = buy
-- the catalog asks what can be chosen for a part's own slots before it is bought
M.requestSlots = function(slotPath, partName)
  if phase ~= 'catalog' and phase ~= 'shop' then return end
  slotPath, partName = tostring(slotPath), tostring(partName)
  guihooks.trigger('slrrGarageSlots', { key = slotPath .. partName, slots = parts.partSlots(slotPath, partName) })
end
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
-- the garage screen's player-facing text (slrr/garageStrings), once
M.requestStrings = function() guihooks.trigger('slrrGarageStrings', { text = require('slrr/garageStrings').TEXT }) end
-- the catalog's hover card: what the part does, read from its jbeam (slrr/garageStats)
M.requestPartStats = function(partName)
  local part = parts.resolvePart(partName)
  local ok, rows = pcall(function() return require('slrr/garageStats').of(part, parts.partWeight(partName)) end)
  guihooks.trigger('slrrGaragePartStats', { part = partName, rows = ok and rows or {} })
end
M.toggleLift = toggleLift
M.toggleEngine = toggleEngine
M.advanceTime = advanceTime
-- does this driver have a helmet mesh? (the SLRR Drivers mod's model folder of the driver: models/<model>/helmet.dae)
M.driverHasHelmet = function(id)
  local d = id and jsonReadFile('/art/slrr_drivers/' .. tostring(id) .. '/driver.json')
  local model = type(d) == 'table' and d.model
  return model ~= nil and model ~= false and FS:fileExists('/art/slrr_drivers/models/' .. tostring(model) .. '/helmet.dae') or false
end

M.service = function(id)
  if phase ~= 'garage' then return end
  id = tostring(id)
  local outfit = slrrDrivers and slrrDrivers.setAppearance and require('slrr/garageOutfits').look(id, slrrDrivers.getAppearance and slrrDrivers.getAppearance(vehId))
  if outfit then
    slrrDrivers.setAppearance(vehId, outfit)
    core_jobsystem.create(function(job) job.sleep(0.2) sendState() end)
    sendState()
    return
  end
  local driver = id:match('^driver:(.+)$')
  if driver and slrrDrivers and slrrDrivers.setDriver then
    if driver == 'none' then driver = nil end
    slrrDrivers.setDriver(vehId, driver)
    extensions.hook('onWrenchWorksDriverChanged', vehId, driver)
    core_jobsystem.create(function(job) job.sleep(0.2) sendState() end)   -- the driver changes a frame later: show it then
  else
    extensions.hook('onWrenchWorksService', id, vehId)
  end
  sendState()
end
M.refresh = function() sendState() end
M.requestSettings = requestSettings
M.settingsDefs = settingsDefs
M.setSetting = setSetting
M.cameraDrag = cameraDrag
M.cameraZoom = cameraZoom
M.focus = focus
M.resetView = resetView
-- #32 photos in the garage. The showcase turns the camera slowly round the car. A photo hides the UI, waits a moment, saves a screenshot of
-- the 3D view to <user folder>/screenshots/slrr_garage/ and brings the UI back. photoMode hands over to the game's own photo mode.
M.toggleShowcase = function()
  if phase ~= 'garage' then return end
  M.showcase = not M.showcase
  sendState()
end
M.photo = function()
  if phase ~= 'garage' or M.photoBusy then return end
  M.photoBusy = true
  core_jobsystem.create(function(job)
    local was
    pcall(function() extensions.load('ui_visibility') was = ui_visibility.get() ui_visibility.set(false) end)
    job.sleep(0.6)
    local dir = 'screenshots/slrr_garage/'
    if not FS:directoryExists(dir) then FS:directoryCreate(dir, true) end
    local name = dir .. tostring(carName()):gsub('[^%w_%-]', '_') .. '_' .. os.date('%Y%m%d_%H%M%S')
    pcall(function() createScreenshot2({ filename = name, writeJPG = false, superSampling = 2 }) end)
    job.sleep(1.5)
    if was ~= nil then pcall(function() ui_visibility.set(was) end) end
    M.photoBusy = false
    say(gs('say.photo_saved', name), 6)
  end)
end
M.photoMode = function()
  if phase ~= 'garage' then return end
  M.showcase = false
  sendState()
  guihooks.trigger('MenuOpenModule', 'pause.photomode')      -- what the game's own photo mode key does
end
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
----------------------------------------------------------------------------------------------
-- For people adding garages and shops to a map: stand where the point should be and run one
-- line in the console (the ~ key). It goes into settings/slrr_garage/sites.json and works at
-- once. docs/adding_garages.md has the rest.

local function slug(name)
  return (tostring(name):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''))
end

local function round3(x) return math.floor(x * 1000 + 0.5) / 1000 end

-- the floor under the player's car and the way it points
local function standing()
  local v = getPlayerVehicle(0)
  if not v then return nil end
  local c = v:getSpawnWorldOOBB():getCenter()
  local drop = castRayStatic(c, vec3(0, 0, -1), 6)
  local dir = vec3(v:getDirectionVector())
  dir.z = 0
  dir:normalize()
  return vec3(c.x, c.y, c.z - math.min(drop, 6)), dir
end

local function tell(text)
  log('I', logTag, text)
  if ui_message then ui_message(text, 10, 'slrrGarage') end
  return text
end

-- Park the car where it should stand in the garage, nose pointing in (away from the door).
M.addGarageHere = function(name)
  if phase ~= 'idle' then return tell('Leave the garage first.') end
  local floor, dir = standing()
  if not floor then return tell('There is no vehicle to take the place from.') end
  name = (type(name) == 'string' and name ~= '') and name or 'My Garage'
  local file = sites.saveUserEntry('garages', {
    id = slug(name), name = name, spot = { round3(floor.x), round3(floor.y), round3(floor.z) }, dir = { round3(dir.x), round3(dir.y) },
    doorDist = -7, halfWidth = 3.5, backDist = 5, ceiling = 4.5, exit = 'reverse',
  })
  if not file then return tell('Could not save the garage: no map is loaded.') end
  armed = false       -- the car standing in it is not a customer
  return tell(string.format('"%s" added. Its door is taken to be 7 m behind the car; drive to the doorway and run slrr_garage.setDoorHere() to put it right. Saved in %s', name, file))
end

-- Stand in the doorway of a garage you added: its door is put there.
M.setDoorHere = function(id)
  if phase ~= 'idle' then return tell('Leave the garage first.') end
  local floor = standing()
  if not floor then return tell('There is no vehicle to take the place from.') end
  local best, bestDist
  for _, s in ipairs(sites.getSites()) do
    if sites.getUserEntry('garages', s.id) and (not id or s.id == id) then
      local d = (floor - s.spot):length()
      if not bestDist or d < bestDist then best, bestDist = s, d end
    end
  end
  if not best then return tell('None of your own garages is on this map. Add one with slrr_garage.addGarageHere("Name").') end
  local along = sites.toAxis(best, floor)
  if along > -1.5 then return tell('The door has to be in front of the parking spot: this is ' .. round3(along) .. ' m along, it must be behind the car.') end
  local entry = sites.getUserEntry('garages', best.id)
  entry.doorDist = round3(along)
  sites.saveUserEntry('garages', entry)
  armed = false
  return tell(string.format('The door of "%s" is now %.1f m from its parking spot.', best.name, -along))
end

-- Stop where customers should stop. sells: a list of catalog chapters ("running/rims_f") or
-- whole sections ("engine"); leave it out and the shop sells everything.
M.addShopHere = function(name, trade, sells)
  if phase ~= 'idle' then return tell('Leave the garage first.') end
  local floor = standing()
  if not floor then return tell('There is no vehicle to take the place from.') end
  name = (type(name) == 'string' and name ~= '') and name or 'My Parts Shop'
  local file = sites.saveUserEntry('shops', {
    id = slug(name), name = name, trade = type(trade) == 'string' and trade or 'Parts',
    pos = { round3(floor.x), round3(floor.y), round3(floor.z) }, sells = type(sells) == 'table' and sells or nil,
  })
  if not file then return tell('Could not save the shop: no map is loaded.') end
  shopArmed = false
  return tell(string.format('"%s" added. Saved in %s', name, file))
end

M.reloadSites = function()
  sites.reload()
  return tell(string.format('%d garages and %d shops on this map.', #sites.getSites(), #sites.getShops()))
end

M.uiSound = function(name) if type(name) == 'string' and name:match('^[%w_]+%.wav$') then playSound(name, 0.7) end end
M.getPhase = function() return phase end
M.getMode = function() return mode end
M.markJobCar = function(id, on) jobCars[id] = on ~= false or nil end
M.addShelfPart = function(model, p) return parts.addShelfPart(model, p) end
-- what this garage has: another mod's career decides (nil: everything, as on its own)
M.setFeatures = function(f)
  parts.setFeatures(f)
  if phase ~= 'idle' then lift.setLiftOwned(parts.getFeatures().lift) lift.setCraneOwned(parts.getFeatures().crane) end
  sendState()
end

-- B8: the garage's upgrades (a career sells them: Street Legal's sl_upgrades). The panel lists them; Buy asks the career.
M.requestUpgrades = function()
  local list = (sl_upgrades and sl_upgrades.summary and sl_upgrades.summary()) or {}
  guihooks.trigger('slrrGarageUpgrades', { list = list, money = parts.getMoney() })
end
M.buyUpgrade = function(id)
  if not (sl_upgrades and sl_upgrades.buy) then return end
  local ok, text = sl_upgrades.buy(tostring(id))
  playSound(ok and 'money.wav' or 'warn.wav', 0.6)
  say(text or '', 4)
  M.requestUpgrades()
  sendState()
end
M.getFeatures = function() return parts.getFeatures() end
M.shelfItems = function(model) return parts.shelfItems(model) end
M.takeShelfItem = function(model, id) if phase ~= 'idle' then return nil end return parts.takeShelfItem(model, tonumber(id)) end   -- (not while the garage shows that shelf)
M.putShelfItem = function(model, item) return parts.putShelfItem(model, item) end

return M
