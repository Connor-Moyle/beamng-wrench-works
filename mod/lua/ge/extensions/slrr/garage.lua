-- SLRR Garage (extension name: slrr_garage)
-- Street Legal Racing: Redline's garage, in BeamNG. Drive up to the Belasco City Garage on
-- West Coast USA: the car rolls in on its own while the camera follows it, the camera swings
-- round into the garage view, and from there you work on the car the SLRR way - click parts off
-- onto the shelf, click them back on, tune them with the screwdriver, order new ones from the
-- catalog, repair, respray, and drive out.
--
-- This file is the conductor: it owns the state machine (idle -> film -> garage <-> catalog ->
-- leaving) and wires the picker, the parts model, the camera, the damage keeper and the UI
-- together.

local M = {}
M.dependencies = { 'core_jobsystem', 'core_vehicle_manager', 'core_camera', 'core_input_actionFilter' }

local sites = require('slrr/garageSites')
local picker = require('slrr/garagePicker')
local parts = require('slrr/garageParts')
local camera = require('slrr/garageCamera')
local damage = require('slrr/garageDamage')
local meshes = require('slrr/garageMeshes')
local settings = require('slrr/garageSettings')
local studio = require('slrr/garageStudio')

local logTag = 'slrr_garage'
local SOUND_DIR = '/art/sound/slrr_garage/'
local FILM_SPEED = 4.2          -- m/s the car rolls in at
local FILM_ACCEL = 1.6
local FILM_TIMEOUT = 14
local ENTER_MAX_SPEED = 14      -- m/s; faster than this and you are just driving past
local FADE_TIME = 0.22

local blockedActions = core_input_actionFilter.createActionTemplate({
  "funStuff", "bigMap", "vehicleMenues", "vehicleTeleporting", "physicsControls", "aiControls",
  "walkingMode", "resetPhysics", "vehicleSwitching", "freeCam", "gameCam", "photoMode", "miniMap",
  "radialMenuActivate", "couplers", "vehicleTriggers", "nodegrabber",
})

local phase = 'idle'      -- idle | film | garage | catalog | busy | leaving
local mode = 'mechanic'   -- mechanic (wrench: fit and remove) | tune (screwdriver: adjust and open)
local tool                -- nil | 'repair' | 'sell' : what the next click on a part does instead
local site                -- the garage we are in / entering
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
local tuneSelected         -- part path picked with the screwdriver (outlined, its adjustments shown)
local photoStamp = ''      -- changes with the car's paint, so repainted cars get fresh catalog photos

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
  return v:getSpawnWorldOOBB():getCenter()
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

local function placeCar(along, facingIn)
  local v = veh()
  if not v or not site then return end
  local pos = sites.point(site, along, 0, 0.05)
  local dir = facingIn and site.dir or -site.dir
  spawn.safeTeleport(v, pos, quatFromDir(dir, vec3(0, 0, 1)), true, nil, false, true, false)
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
    garage = site and site.name or nil,
    car = carName(),
    money = parts.getMoney(),
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
    photos = settings.get('photoPreviews') and studio.isActive(),
    photoStamp = photoStamp,
    spinSpeed = settings.get('spinSpeed'),
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
  studio.refill()      -- the screen is dark: a good moment to load the next lot of catalog parts
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

local function buildDrivePath(startFront, endFront)
  local total = (endFront - startFront):length()
  local dir = (endFront - startFront) / total
  local path = {}
  local accelDist = FILM_SPEED * FILM_SPEED / (2 * FILM_ACCEL)
  local function timeAt(s)
    -- trapezoid speed profile: ease up to FILM_SPEED, ease down to a stop
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
  local step = 0.75
  local s = 0
  while s < total do
    local p = startFront + dir * s
    path[#path + 1] = { x = p.x, y = p.y, z = p.z, t = timeAt(s) }
    s = s + step
  end
  path[#path + 1] = { x = endFront.x, y = endFront.y, z = endFront.z, t = timeAt(total) }
  return path, timeAt(total)
end

local function sendPreview(partName, mesh)
  if mesh then
    guihooks.trigger('slrrGaragePreview', { part = partName, v = mesh.v, t = mesh.t, m = mesh.m, mats = mesh.mats })
  else
    guihooks.trigger('slrrGaragePreview', { part = partName, none = true })
  end
end

local function sendPhoto(key, info)
  guihooks.trigger('slrrGaragePhoto', info)
end

-- ask the studio for a shelf part's photographs. A part that came in on the car is photographed
-- where it sits on the studio car (livery, damage and all); anything else as a loose part.
local function photographItem(item)
  if not studio.isActive() then return end
  local key = 'item_' .. item.id
  if studio.hasPart(item.slotPath, item.part) then
    studio.request({ key = key, slotPath = item.slotPath }, true)
  else
    studio.request({ key = key, part = item.part }, true)
  end
end

-- the studio car sits on the garage roof, where nobody looks
local function startStudio()
  if not settings.get('previews') or not settings.get('photoPreviews') then return end
  local vd = core_vehicle_manager.getVehicleData(vehId)
  if not vd or not site then return end
  local above = sites.point(site, -0.5, 0, 16)
  local drop = castRayStatic(above, vec3(0, 0, -1), 40)
  local roofZ = above.z - drop
  if roofZ < site.spot.z + 2.5 then return end      -- no roof found over the garage
  local paint = (vd.config.paints or {})[1]
  local c = paint and paint.baseColor or {}
  photoStamp = string.format('%d_%d_%d', (c[1] or 0) * 99, (c[2] or 0) * 99, (c[3] or 0) * 99)
  -- the parts the catalog lists for this car, in the order of its chapters
  local background, seen = {}, {}
  local bySub = parts.buildCatalog()
  for _, section in ipairs(parts.getSections()) do
    for _, sub in ipairs(section.subs) do
      for _, entry in ipairs(bySub[section.id .. '/' .. sub.id] or {}) do
        if not seen[entry.part] then
          seen[entry.part] = true
          background[#background + 1] = { key = 'part_' .. entry.part .. '_' .. photoStamp, part = entry.part }
        end
      end
    end
  end
  local ok = studio.start(vehId, vd.config, damage.buildApply(parts.getShelfDamages()),
    vec3(above.x, above.y, roofZ + 0.4), quatFromDir(site.dir, vec3(0, 0, 1)), parts.resolvePart, sendPhoto, background)
  if ok then
    for _, item in ipairs(parts.getInventory()) do photographItem(item) end
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
  local startAlong = clamp(sites.toAxis(site, carCenter()), site.approachDist, site.doorDist - 7)

  captureDamage(job)                      -- note the dents before anything rebuilds the car
  parts.attach(vehId, false)
  meshes.setup(parts.getModel(), parts.resolvePart, sendPreview)
  if parts.countStageable() > 0 then
    -- parts left on the shelf last time: load them now so they can be fitted without a wait
    respawnWithDesired(job, false)
    job.sleep(0.2)
    parts.attach(vehId, true)
  end
  startStudio()
  job.sleep(0.1)

  v = veh()
  if not v then phase = 'idle' setFade(0) return end
  camera.setup(site, carCenter, length)
  mode, tool = 'mechanic', nil

  if settings.get('playFilm') then
    freezeCar(false)
    v:queueLuaCommand('input.event("parkingbrake", 0, FILTER_DIRECT)')
    placeCar(startAlong, true)
    job.sleep(0.3)
    camera.startFilm()
    core_camera.setByName(0, 'slrrGarage', false)
    playSound('entergarage.wav')
    local startFront = sites.point(site, startAlong + half, 0, 0.3)
    local endFront = sites.point(site, half, 0, 0.3)
    local path, duration = buildDrivePath(startFront, endFront)
    v:queueLuaCommand('ai.startFollowing(' .. serialize({ path = path }) .. ', 0, 1, "neverReset")')
    job.sleep(0.1)
    setFade(0)

    -- one unbroken shot: the camera trails the car through the door
    local clock = hptimer()
    local t = 0
    while t < math.min(FILM_TIMEOUT, duration + 4) do
      job.sleep(0.02)
      t = clock:stop() / 1000
      v = veh()
      if not v then break end
      local along = sites.toAxis(site, carCenter())
      if along > -0.5 or (t > duration and v:getVelocity():length() < 0.3) then break end
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
      placeCar(0, true)
      job.sleep(0.3)
      camera.startOrbit(false)
      setFade(0)
    end
    job.sleep(0.35)
    v:queueLuaCommand('input.event("brake", 0, FILTER_DIRECT)')
  else
    placeCar(0, true)
    job.sleep(0.35)
    camera.startOrbit(false)
    core_camera.setByName(0, 'slrrGarage', false)
    playSound('entergarage.wav')
    setFade(0)
  end

  freezeCar(true)
  picker.begin(vehId)
  phase = 'garage'
  sendState()
  sendHover()
end

local function startEnter(_site, id)
  if phase ~= 'idle' then return end
  site = _site
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
  meshes.release()
  studio.stop()
  parts.detach()
  damage.clear()
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
  setFade(1)
  job.sleep(FADE_TIME + 0.05)
  if camera.isLift() then
    camera.setLift(false)
    local v = veh()
    if v then v:queueLuaCommand('if slrrGarageVeh then slrrGarageVeh.onReset() end') end
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
  freezeCar(false)
  placeCar(site.exitDist, false)
  job.sleep(0.3)
  playSound('leavegarage.wav')
  parts.clearLoaderCache()
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
local function sendTunePart()
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
  photographItem(item)
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
  for _, other in ipairs(parts.getInventory()) do photographItem(other) end   -- a swapped-out part may have landed there
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

local function sendCatalog()
  local bySub = parts.buildCatalog()
  local out = {}
  for _, section in ipairs(parts.getSections()) do
    local s = { id = section.id, title = section.title, subs = {} }
    for _, sub in ipairs(section.subs) do
      local items = bySub[section.id .. '/' .. sub.id] or {}
      s.subs[#s.subs + 1] = { id = sub.id, title = sub.title, items = items }
    end
    out[#out + 1] = s
  end
  guihooks.trigger('slrrGarageCatalog', { sections = out, money = parts.getMoney() })
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

local function closeCatalog()
  if phase ~= 'catalog' then return end
  playSound('mnuback.wav')
  if parts.countStageable() > 0 then
    -- new parts on the shelf: load them now, behind the page turn, so fitting them is instant
    core_jobsystem.create(applyInGarage)
  else
    phase = 'garage'
    sendState()
  end
end

local function buy(slotPath, partName)
  if phase ~= 'catalog' then return end
  local ok, res = parts.buy(slotPath, partName)
  if not ok then
    playSound('warn.wav', 0.6)
    say(res)
    return
  end
  playSound('money.wav')
  sendState()
  sendCatalog()
end

-- the UI asks for the 3D models of the parts it is about to show
local function requestPreviews(names)
  if type(names) ~= 'table' or not settings.get('previews') then return end
  if phase ~= 'garage' and phase ~= 'catalog' and phase ~= 'busy' then return end
  meshes.request(names)
end

-- the UI asks for photographs: shelf items by id, catalog parts by name
local function requestPhotos(itemIds, partNames)
  if not studio.isActive() then return end
  studio.newPage()
  for _, id in ipairs(type(itemIds) == 'table' and itemIds or {}) do
    for _, item in ipairs(parts.getInventory()) do
      if item.id == id then photographItem(item) end
    end
  end
  for _, name in ipairs(type(partNames) == 'table' and partNames or {}) do
    if type(name) == 'string' then
      studio.request({ key = 'part_' .. name .. '_' .. photoStamp, part = name }, true)
    end
  end
end

-- tuning: the UI sends back the values the player set; they take effect with one rebuild
local function applyTuning(values)
  if phase ~= 'garage' then return end
  if parts.setTuning(values) and parts.varsDirty() then
    playSound('screw.wav')
    core_jobsystem.create(applyInGarage)
  else
    sendTuning()
  end
end

local function requestTuning()
  sendTuning()
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
  core_vehicle_manager.liveUpdateVehicleColors(vehId, v, index, clean)
  playSound('spray.wav')
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
local LIFT_HEIGHT = 1.35
local function setCarLift(on)
  local v = veh()
  if not v then return end
  v:queueLuaCommand('extensions.load("slrrGarageVeh") slrrGarageVeh.setLift(' .. (on and LIFT_HEIGHT or 0) .. ')')
end

local function toggleLift()
  if phase ~= 'garage' then return end
  camera.setLift(not camera.isLift())
  setCarLift(camera.isLift())
  playSound('mnuselect.wav', 0.7)
  sendState()
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
  if not settings.get('highlight') then parts.setHighlight(nil) end
  sendSettings()
  sendState()
  if phase == 'catalog' then sendCatalog() end
end

local function cameraDrag(dx, dy)
  camera.rotate(tonumber(dx) or 0, tonumber(dy) or 0)
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

-- enter by hand (console / key binding): uses the nearest garage on this map
local function enterNearest()
  if phase ~= 'idle' then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  local best, bestDist
  for _, s in ipairs(sites.getSites()) do
    local d = (v:getPosition() - s.spot):length()
    if not bestDist or d < bestDist then best, bestDist = s, d end
  end
  if best then startEnter(best, v:getID()) end
end

----------------------------------------------------------------------------------------------
-- frame update

-- a soft beacon in front of the door, like SLRR's garage marker, so the way in is obvious
local markerColor, markerTextColor, markerTextBg = ColorF(1, 0.4, 0, 0.28), ColorF(1, 1, 1, 1), ColorI(20, 20, 24, 200)
local function drawMarker(s, distance)
  local base = sites.point(s, (s.triggerNear + s.triggerFar) * 0.5, 0, 0)
  local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
  markerColor.a = 0.16 + 0.14 * pulse
  debugDrawer:drawCylinder(base, base + vec3(0, 0, 0.12), s.triggerHalfWidth * 0.8, markerColor)
  debugDrawer:drawCylinder(base, base + vec3(0, 0, 2.6 + 0.3 * pulse), 0.07, markerColor)
  if distance < 45 then
    local label = settings.get('autoEnter') and (s.name .. ' - drive in') or s.name
    debugDrawer:drawTextAdvanced(base + vec3(0, 0, 3.1), String(label), markerTextColor, true, false, markerTextBg)
  end
end

local function updateIdle()
  local v = getPlayerVehicle(0)
  if not v then return end
  local list = sites.getSites()
  if #list == 0 then return end
  local pos = v:getPosition()
  for _, s in ipairs(list) do
    local distSq = (pos - s.spot):squaredLength()
    if distSq < 90 * 90 then drawMarker(s, math.sqrt(distSq)) end
    if distSq < 60 * 60 then
      local along, side = sites.toAxis(s, v:getSpawnWorldOOBB():getCenter())
      local inBand = along < s.triggerNear and along > s.triggerFar and math.abs(side) < s.triggerHalfWidth
      if not armed then
        -- re-arm once the car is well clear of the doorway
        if along < s.triggerFar - 4 or math.abs(side) > s.triggerHalfWidth + 6 or along > s.backDist + 3 then armed = true end
      elseif inBand and settings.get('autoEnter') then
        local vel = v:getVelocity()
        local speed = vel:length()
        local heading = v:getDirectionVector():dot(s.dir)
        if speed < ENTER_MAX_SPEED and heading > 0.55 and vel:dot(s.dir) > 0.5 then
          startEnter(s, v:getID())
          return
        end
      end
    end
  end
end

local function updateGarage(dt)
  picker.update()
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
  if phase ~= 'idle' and phase ~= 'leaving' then studio.update(dtReal) end
  if phase == 'idle' then
    updateIdle()
  elseif phase == 'garage' then
    updateGarage(dtReal)
    if frame % 2 == 0 then meshes.update() end
  elseif phase == 'catalog' then
    if frame % 2 == 0 then meshes.update() end
  elseif phase == 'busy' or phase == 'film' then
    picker.update()
  end
end

----------------------------------------------------------------------------------------------
-- game hooks

local function onVehicleSpawned(id)
  studio.onVehicleSpawned(id)
  if id ~= vehId then return end
  if respawnWaiter then
    settleFrames = 3
  end
end

local function onPreRender()
  if settleFrames > 0 then
    settleFrames = settleFrames - 1
    if settleFrames == 0 and respawnWaiter then respawnWaiter() end
  end
end

-- something pulled the rug (vehicle switched or removed, mod reloaded): undo the visit so the
-- shelf and the car cannot disagree about where a part is
local function abort()
  if phase == 'idle' then return end
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
    meshes.release()
    studio.stop()
    parts.detach()
    damage.clear()
    phase, site, vehId, fade = 'idle', nil, nil, 0
  end
  armed = true
end

local function onExtensionLoaded()
  log('I', logTag, 'SLRR garage loaded')
end

local function onExtensionUnloaded()
  abort()
end

-- the UI app asks for the current state when it (re)loads
local function requestState()
  sendState()
  sendHover()
  if phase == 'catalog' then sendCatalog() end
  if mode == 'tune' and phase == 'garage' then
    sendTuning()
    sendTunePart()
  end
end

-- the game calls this while it assembles a vehicle from jbeam; the parts model uses it to add
-- hidden meshes for shelf parts. Other vehicles and our own off-screen loads are left alone.
M.onJbeamLoadingPhase2 = function(loadingProgress, objID, vehicle)
  parts.onJbeamLoadingPhase2(objID, vehicle)
  if not parts.isHeadlessLoad() then studio.onJbeamLoadingPhase2(objID, vehicle) end
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
M.setTool = setTool
M.setMode = setMode
M.repairAll = repairAll
M.toggleFilter = toggleFilter
M.openCatalog = openCatalog
M.closeCatalog = closeCatalog
M.buy = buy
M.requestPreviews = requestPreviews
M.requestPhotos = requestPhotos
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
