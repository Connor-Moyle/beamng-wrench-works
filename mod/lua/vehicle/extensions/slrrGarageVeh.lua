-- Wrench Works, vehicle side: remembers how bent the car is, and bends it back that way.
-- Changing parts in BeamNG rebuilds the vehicle, which also repairs it. The garage does not
-- hand out free repairs, so before a rebuild it records every bent or broken beam (by the
-- names of the two nodes it joins, so the record survives a different set of parts) and
-- afterwards puts that damage back on whatever parts are still there.

local M = {}

-- Damage this car was given by apply(). The physics core only reports deformation it caused
-- itself, so on the next visit these records are handed back along with any new damage.
local carried

-- Latches (doors, hood, boot) that were shut when the damage was recorded. Moving bent panels
-- back into their bent shape pops them; they are pushed shut again a moment later.
local relatch, relatchTimer

local function latchStates()
  local states = {}
  for name, c in pairs(controller.getAllControllers and controller.getAllControllers() or {}) do
    if type(c) == 'table' and c.tryAttachGroupImpulse and c.getGroupState then states[name] = c.getGroupState() end
  end
  return states
end

-- A broken beam of a latch group (the doors', hood's and boot's "..._latch" and support beams) must never be
-- broken again on a rebuild: breaking it detaches the latch for good, and the door can never shut again.
-- A door torn off is still torn off: its hinge beams are kept.
local function isLatchBeam(beam)
  local g = beam and beam.breakGroup
  if type(g) == 'string' then g = { g } end
  for _, name in ipairs(type(g) == 'table' and g or {}) do
    local n = tostring(name):lower()
    if n:find('latch', 1, true) or n:find('support', 1, true) then return true end
  end
  return false
end

-- Some beams report a deformation on a car straight from the factory (they are built under
-- tension). What an undamaged car reports is noted here, so that only real bends count.
local baseline

local function takeBaseline()
  baseline = {}
  for cid = 0, tableSizeC(v.data.beams) - 1 do
    local d = obj:getBeamDeformation(cid) or 0
    if d ~= 0 then baseline[cid] = d end
  end
end

local function frame()
  local rn = v.data.refNodes and v.data.refNodes[0]
  if not rn then return nil end
  local o = obj:getNodePosition(rn.ref)
  local y = (obj:getNodePosition(rn.back) - o):normalized()
  local z = (obj:getNodePosition(rn.left) - o):cross(y):normalized()
  local x = y:cross(z):normalized()
  return o, x, y, z
end

-- Parts that fell off (A13): a part whose break groups are all broken is gone from the car; the garage must not keep it in the saved setup.
-- Returns the parts' paths (the partPath of its beams, as the setup's parts tree names them).
local function lostParts()
  local groups, lost = {}, {}
  local broken = beamstate and beamstate.brokenBreakGroups or {}
  for _, beam in pairs(v.data.beams or {}) do
    if beam.partPath and beam.breakGroup and beam.breakGroup ~= '' then
      local e = groups[beam.partPath]
      if not e then e = { n = 0, b = 0 } groups[beam.partPath] = e end
      for _, name in ipairs(type(beam.breakGroup) == 'table' and beam.breakGroup or { beam.breakGroup }) do
        if not e[name] then
          e[name] = true
          e.n = e.n + 1
          if broken[name] then e.b = e.b + 1 end
        end
      end
    end
  end
  for path, e in pairs(groups) do if e.n > 0 and e.b == e.n then lost[#lost + 1] = path end end
  table.sort(lost)
  return lost
end

-- record the damage and send it to the garage
local function capture()
  local data = { nodes = {}, beams = {}, latches = latchStates(), lost = lostParts() }
  local o, x, y, z = frame()
  local nodes, beams = v.data.nodes, v.data.beams
  if o and nodes and beams then
    local touched, pairCount = {}, {}
    for cid = 0, tableSizeC(beams) - 1 do
      local beam = beams[cid]
      if beam and beam.id1 and beam.id2 then
        local lo, hi = math.min(beam.id1, beam.id2), math.max(beam.id1, beam.id2)
        local key = lo * 65536 + hi
        local index = (pairCount[key] or 0) + 1
        pairCount[key] = index
        local broken = obj:beamIsBroken(cid) and not isLatchBeam(beam)
        local deform = obj:getBeamDeformation(cid) or 0
        local bent = math.abs(deform - (baseline and baseline[cid] or 0)) > 1e-5
        if broken or bent then
          local a, b = nodes[lo], nodes[hi]
          if a and b and a.name and b.name then
            data.beams[#data.beams + 1] = {
              a = a.name, b = b.name, i = index, l = obj:getBeamRestLength(cid), k = broken or nil, d = deform,
              pa = a.partPath, pb = b.partPath,
            }
            touched[lo], touched[hi] = true, true
          end
        end
      end
    end
    -- damage put back on this car earlier is still on it
    if carried then
      local seen = {}
      for _, rec in ipairs(data.beams) do seen[rec.a .. '|' .. rec.b .. '|' .. rec.i] = true end
      local byName = {}
      for cid, node in pairs(nodes) do
        if node.name then byName[node.name] = cid end
      end
      for _, rec in ipairs(carried.beams or {}) do
        local ca, cb = byName[rec.a], byName[rec.b]
        if rec.a and ca and cb and nodes[ca].partPath == rec.pa and nodes[cb].partPath == rec.pb and not seen[rec.a .. '|' .. rec.b .. '|' .. rec.i] then
          data.beams[#data.beams + 1] = rec
          touched[ca], touched[cb] = true, true
        end
      end
    end
    for cid in pairs(touched) do
      local node = nodes[cid]
      local r = obj:getNodePosition(cid) - o
      data.nodes[#data.nodes + 1] = { n = node.name, p = node.partPath, x = r:dot(x), y = r:dot(y), z = r:dot(z) }
    end
  end
  obj:queueGameEngineLua(string.format("if slrr_garage then slrr_garage.onDamageCaptured(%d, %s) end", obj:getId(), serialize(data)))
end

-- The latches are let go cleanly before the nodes move: a coupler torn apart by the nodes moving under it
-- reports a break, the controller marks that latch "broken" and never closes it again (tryAttachGroupImpulse
-- only closes "detached" ones), so every door and lid the garage had touched hung open for good.
local function releaseLatches()
  for _, c in pairs(controller.getAllControllers and controller.getAllControllers() or {}) do
    if type(c) == 'table' and c.detachGroup and c.getGroupState then c.detachGroup() end
  end
end

-- bend the freshly built car the way the record says, wherever the same part is still fitted.
-- options.keepLatches (a car on show, not the garage's own): the latches are not released and not pushed shut again
-- afterwards; the doors and lids stay as the build left them (shut), and the panels bend only as far as they allow.
local function applyNow(data, options)
  local keepLatches = type(options) == 'table' and options.keepLatches == true
  -- options.done: a line of game-engine Lua run when the damage is on (or could not be put on), so the caller can wait for it
  local function finish() if type(options) == 'table' and type(options.done) == 'string' then obj:queueGameEngineLua(options.done) end end
  if not baseline then takeBaseline() end     -- called on a freshly built car
  local o, x, y, z = frame()
  local nodes, beams = v.data.nodes, v.data.beams
  if not o or not nodes or not beams or type(data) ~= 'table' then finish() return end
  if not keepLatches then releaseLatches() end
  local byName = {}
  for cid, node in pairs(nodes) do
    if node.name then byName[node.name] = cid end
  end
  local beamsOf = {}
  -- A crash in the game's physics thread, 0.3 s after a car was built with damage (0x140386), came from this recorded branch moving or re-measuring
  -- special beams and the nodes of special beams. Only plain beams (type 0) are re-measured or broken here, and a node moves only if none of the beams
  -- on it is anisotropic (1), bounded (2), pressured (3), an L-beam (4) or a hydro (6); a record whose beam is gone or of another type is skipped.
  local specialNode = {}
  for cid = 0, tableSizeC(beams) - 1 do
    local beam = beams[cid]
    if beam and beam.id1 and beam.id2 then
      local bt = beam.beamType or 0
      if bt == 1 or bt == 2 or bt == 3 or bt == 4 or bt == 6 then specialNode[beam.id1], specialNode[beam.id2] = true, true end
    end
  end
  for cid = 0, tableSizeC(beams) - 1 do
    local beam = beams[cid]
    if beam and beam.id1 and beam.id2 then
      local key = math.min(beam.id1, beam.id2) * 65536 + math.max(beam.id1, beam.id2)
      local list = beamsOf[key]
      if not list then list = {}; beamsOf[key] = list end
      list[#list + 1] = cid
    end
  end
  local function nodeFor(name, partPath)
    local cid = byName[name]
    if cid and nodes[cid].partPath == partPath then return cid end
  end

  for _, rec in ipairs(data.nodes or {}) do
    local cid = nodeFor(rec.n, rec.p)
    if cid and not nodes[cid].wheelID and not nodes[cid].fixed and not specialNode[cid] then obj:setNodePosition(cid, o + x * rec.x + y * rec.y + z * rec.z) end
  end
  local applied = 0
  -- A second-hand part arrives bent: its nodes are nudged out of place and the beams between
  -- them take that shape. From then on it is ordinary damage.
  for _, rec in ipairs(data.beams or {}) do
    if rec.dent then
      -- Only a plain body panel is dented, and only where nothing special hangs on it (a lot's dents crashed the game's heap, 0x140386: nodes of other
      -- parts, pressure, hydro, bounded, support, L-beams and latch beams were moved or re-measured). A node moves only if EVERY beam on it is a plain
      -- beam (type 0, no break group, not broken) of the dented part; the move is capped; and only those beams are re-measured.
      local part = tostring(rec.pa or '')
      if not part:lower():find('rad') and not part:lower():find('fuel') and not part:lower():find('tank') and not part:lower():find('engine')
          and not part:lower():find('trans') and not part:lower():find('axle') and not part:lower():find('susp') and not part:lower():find('wheel')
          and not part:lower():find('brake') and not part:lower():find('steer') and not part:lower():find('exhaust') then
        local plain, blocked = {}, {}
        for cid = 0, tableSizeC(beams) - 1 do
          local beam = beams[cid]
          if beam and beam.id1 and beam.id2 then
            local ok = beam.partPath == rec.pa and (beam.beamType or 0) == 0 and not isLatchBeam(beam) and not obj:beamIsBroken(cid)
              and (beam.breakGroup == nil or beam.breakGroup == '') and (beam.beamPrecompression or 1) == 1 and not beam.deformLimit
            if ok then plain[cid] = true
            else blocked[beam.id1], blocked[beam.id2] = true, true end
          end
        end
        local moved, seed = {}, rec.seed or 1
        local function rnd()
          seed = (seed * 1103515245 + 12345) % 2147483648
          return seed / 2147483648 * 2 - 1
        end
        local amount = math.min(tonumber(rec.dent) or 0, 0.1)
        for cid, node in pairs(nodes) do
          if node.partPath == rec.pa and not node.wheelID and not node.fixed and not blocked[cid] then
            local p = obj:getNodePosition(cid) + vec3(rnd(), rnd(), rnd()) * amount
            obj:setNodePosition(cid, p)
            moved[cid] = true
          end
        end
        for cid in pairs(plain) do
          local beam = beams[cid]
          if moved[beam.id1] or moved[beam.id2] then
            local length = (obj:getNodePosition(beam.id1) - obj:getNodePosition(beam.id2)):length()
            if length > 0.001 then
              obj:setBeamLength(cid, length)
              applied = applied + 1
            end
          end
        end
      end
    end
  end
  for _, rec in ipairs(data.beams or {}) do
    local ca, cb = nodeFor(rec.a, rec.pa), nodeFor(rec.b, rec.pb)
    if ca and cb then
      local list = beamsOf[math.min(ca, cb) * 65536 + math.max(ca, cb)]
      local cid = list and list[rec.i]
      local beam = cid and beams[cid]
      if beam and (beam.beamType or 0) == 0 and (beam.breakGroup == nil or beam.breakGroup == '') and not isLatchBeam(beam) and type(rec.l) == 'number' and rec.l > 0.001 then
        obj:setBeamLength(cid, rec.l)
        if rec.k and not isLatchBeam(beams[cid]) then obj:breakBeam(cid) end   -- (older records may still hold a latch beam)
        if rec.d and rec.d ~= 0 and beamstate.onBeamDeformed then beamstate.onBeamDeformed(cid, rec.d) end
        applied = applied + 1
      end
    end
  end
  if applied > 0 then obj:commitLoad() end
  carried = data
  -- every door and lid is shut again, whatever it was when the damage was noted (one sprung in the crash
  -- would otherwise hang open for ever); a door without its hinges just has nothing to latch to
  if keepLatches then finish() return end
  relatch, relatchTimer = {}, 0.6
  for name in pairs(latchStates()) do relatch[name] = 'attached' end
  finish()
end

local function updateLatches(dt)
  relatchTimer = relatchTimer - dt
  if relatchTimer > 0 then return end
  -- a frozen car cannot latch (A5: doors and hoods stayed open after a reload, the retries spent while the car stood frozen): wait, spending none
  if controller.isFrozen then relatchTimer = 0.5 return end
  local pending = false
  for name, state in pairs(relatch) do
    local c = controller.getControllerSafe(name)
    if state == 'attached' and c and c.getGroupState and c.getGroupState() ~= 'attached' then
      c.tryAttachGroupImpulse()
      pending = true
    end
  end
  relatch.tries = (relatch.tries or 0) + 1
  if pending and relatch.tries < 24 then relatchTimer = 0.5 else relatch = nil end   -- (the open force of the release has to die down first)
end

-- push every door and lid shut (the car is about to drive out through a doorway)
local function shutLatches()
  relatch, relatchTimer = {}, 0
  for name in pairs(latchStates()) do relatch[name] = 'attached' end
end

-- The lift. The car is held up by forces: every node that is not part of a wheel is steered towards a spot a set height above where it stood, with a force strong
-- enough to carry it. The wheels are left alone and hang on the suspension, as on a real lift.
local liftNodes        -- { cid, mass, x, y, z } world rest positions of the chassis nodes
local liftHeight, liftTarget, liftSpeed = 0, 0, 0.55
local liftCarry = 1     -- the chassis nodes also carry everything bolted to them

local function setLift(height)
  liftTarget = math.max(0, tonumber(height) or 0)
  if liftNodes or liftTarget <= 0 then return end
  -- Everything but the wheels is carried. (Carrying the body shell alone tips a car whose
  -- engine hangs off a subframe behind it.)
  local origin = obj:getPosition()
  liftNodes = {}
  for cid, node in pairs(v.data.nodes) do
    if not node.wheelID then
      local p = origin + obj:getNodePosition(cid)
      liftNodes[#liftNodes + 1] = { cid = cid, mass = obj:getNodeMass(cid), x = p.x, y = p.y, z = p.z }
    end
  end
  local chassisMass, totalMass = 0, 0
  for i = 1, #liftNodes do chassisMass = chassisMass + liftNodes[i].mass end
  for cid in pairs(v.data.nodes) do totalMass = totalMass + obj:getNodeMass(cid) end
  liftCarry = chassisMass > 0 and totalMass / chassisMass or 1
  liftHeight = 0
end

local SETTLE_FRAMES, SETTLE_SECONDS = 30, 1.0
local settleFrames, settleTime, pendingApply = 0, 0, nil

local function updateGFX(dt)
  settleFrames, settleTime = settleFrames + 1, settleTime + dt
  if pendingApply and settleFrames >= SETTLE_FRAMES and settleTime >= SETTLE_SECONDS then
    local p = pendingApply
    pendingApply = nil
    applyNow(p.data, p.options)
  end
  if relatch then updateLatches(dt) end
  if not liftNodes then return end
  dt = math.min(dt, 0.05)
  if liftHeight < liftTarget then liftHeight = math.min(liftTarget, liftHeight + liftSpeed * dt)
  elseif liftHeight > liftTarget then liftHeight = math.max(liftTarget, liftHeight - liftSpeed * dt) end
  if liftTarget <= 0 and liftHeight <= 0 then
    liftNodes = nil   -- back on the floor: let go
    return
  end
  local origin = obj:getPosition()
  local gravity = -obj:getGravity() * liftCarry
  local kp, kd = 70, 17
  local force = vec3()
  for i = 1, #liftNodes do
    local n = liftNodes[i]
    local p = origin + obj:getNodePosition(n.cid)
    local vel = obj:getNodeVelocityVector(n.cid)
    force:set(
      n.mass * (kp * (n.x - p.x) - kd * vel.x),
      n.mass * (kp * (n.y - p.y) - kd * vel.y),
      n.mass * (kp * (n.z + liftHeight - p.z) - kd * vel.z + gravity))
    obj:applyForceVectorTime(n.cid, force, dt)
  end
end

local function releaseLift()
  liftNodes, liftHeight, liftTarget = nil, 0, 0
end

-- the player reset the car: it is as new again
local function onReset()
  releaseLift()
  carried, relatch = nil, nil
  takeBaseline()
end

-- loaded when the car is spawned: if nothing has happened to it yet, this is what "undamaged" reads as
local function onExtensionLoaded()
  if not baseline and (beamstate.damage or 0) < 1 then takeBaseline() end
end

-- The engine's power curve, as the game itself computes it for this car, thinned to a point
-- every 250 rpm, sent to the garage for its car info sheet.
local function dyno()
  local out
  for _, dev in pairs(powertrain.getDevices()) do
    local ok, td = pcall(function() return dev.getTorqueData and dev:getTorqueData() or dev.torqueData end)
    if ok and type(td) == 'table' and type(td.curves) == 'table' and (not out or (td.maxPower or 0) > out.maxPower) then
      local curve = td.curves[td.finalCurveName] or select(2, next(td.curves))
      if curve and curve.torque and curve.power then
        local maxRPM = math.floor(td.maxRPM or #curve.torque)
        out = { name = dev.name, maxRPM = maxRPM, maxTorque = td.maxTorque or 0, maxPower = td.maxPower or 0,
          maxTorqueRPM = td.maxTorqueRPM, maxPowerRPM = td.maxPowerRPM, step = 250, torque = {}, power = {} }
        for rpm = 0, maxRPM, 250 do
          out.torque[#out.torque + 1] = math.floor((curve.torque[rpm] or curve.torque[rpm + 1] or 0) + 0.5)
          out.power[#out.power + 1] = math.floor((curve.power[rpm] or curve.power[rpm + 1] or 0) + 0.5)
        end
      end
    end
  end
  obj:queueGameEngineLua(string.format("if slrr_garage then slrr_garage.onDyno(%d, %s) end", obj:getId(), serialize(out or {})))
end

M.dyno = dyno
M.capture = capture
-- A car just built is not ready for its beams to be changed: the physics thread is still starting it. The damage waits here for a settled car (a
-- number of graphics frames and a second of time since this extension started; a car that never settles is not touched), unless options.settle == false.
local function apply(data, options)
  if type(options) == 'table' and options.settle == false or (settleFrames >= SETTLE_FRAMES and settleTime >= SETTLE_SECONDS) then
    pendingApply = nil
    return applyNow(data, options)
  end
  pendingApply = { data = data, options = options }
end
M.apply = apply
M.applyNow = applyNow
M.shutLatches = shutLatches
M.setLift = setLift
M.releaseLift = releaseLift
M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionLoaded = onExtensionLoaded

return M
