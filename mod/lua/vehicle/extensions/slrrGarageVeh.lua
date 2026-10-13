-- SLRR Garage, vehicle side: remembers how bent the car is, and bends it back that way.
-- Changing parts in BeamNG rebuilds the vehicle, which also repairs it. The garage does not
-- hand out free repairs, so before a rebuild it records every bent or broken beam (by the
-- names of the two nodes it joins, so the record survives a different set of parts) and
-- afterwards puts that damage back on whatever parts are still there.

local M = {}

local function frame()
  local rn = v.data.refNodes and v.data.refNodes[0]
  if not rn then return nil end
  local o = obj:getNodePosition(rn.ref)
  local y = (obj:getNodePosition(rn.back) - o):normalized()
  local z = (obj:getNodePosition(rn.left) - o):cross(y):normalized()
  local x = y:cross(z):normalized()
  return o, x, y, z
end

-- record the damage and send it to the garage
local function capture()
  local data = { nodes = {}, beams = {} }
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
        local broken = obj:beamIsBroken(cid)
        local deform = obj:getBeamDeformation(cid) or 0
        if broken or deform ~= 0 then
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
    for cid in pairs(touched) do
      local node = nodes[cid]
      local r = obj:getNodePosition(cid) - o
      data.nodes[#data.nodes + 1] = { n = node.name, p = node.partPath, x = r:dot(x), y = r:dot(y), z = r:dot(z) }
    end
  end
  obj:queueGameEngineLua(string.format("if slrr_garage then slrr_garage.onDamageCaptured(%d, %s) end", obj:getId(), serialize(data)))
end

-- bend the freshly built car the way the record says, wherever the same part is still fitted
local function apply(data)
  local o, x, y, z = frame()
  local nodes, beams = v.data.nodes, v.data.beams
  if not o or not nodes or not beams or type(data) ~= 'table' then return end
  local byName = {}
  for cid, node in pairs(nodes) do
    if node.name then byName[node.name] = cid end
  end
  local beamsOf = {}
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
    if cid then obj:setNodePosition(cid, o + x * rec.x + y * rec.y + z * rec.z) end
  end
  local applied = 0
  for _, rec in ipairs(data.beams or {}) do
    local ca, cb = nodeFor(rec.a, rec.pa), nodeFor(rec.b, rec.pb)
    if ca and cb then
      local list = beamsOf[math.min(ca, cb) * 65536 + math.max(ca, cb)]
      local cid = list and list[rec.i]
      if cid then
        obj:setBeamLength(cid, rec.l)
        if rec.k then obj:breakBeam(cid) end
        if rec.d and rec.d ~= 0 and beamstate.onBeamDeformed then beamstate.onBeamDeformed(cid, rec.d) end
        applied = applied + 1
      end
    end
  end
  if applied > 0 then obj:commitLoad() end
end

-- The lift. The garage has no lift model, so the car is simply held up: every node of the
-- chassis is steered towards a spot a set height above where it stood, with a force strong
-- enough to carry it. The wheels are left alone and hang on the suspension, as on a real lift.
local liftNodes        -- { cid, mass, x, y, z } world rest positions of the chassis nodes
local liftHeight, liftTarget, liftSpeed = 0, 0, 0.55
local liftCarry = 1     -- the chassis nodes also carry everything bolted to them

local function setLift(height)
  liftTarget = math.max(0, tonumber(height) or 0)
  if liftNodes or liftTarget <= 0 then return end
  local rn = v.data.refNodes and v.data.refNodes[0]
  local chassis = rn and v.data.nodes[rn.ref] and v.data.nodes[rn.ref].partPath
  local origin = obj:getPosition()
  liftNodes = {}
  for cid, node in pairs(v.data.nodes) do
    if node.partPath == chassis then
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

local function updateGFX(dt)
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

local function onReset()
  liftNodes, liftHeight, liftTarget = nil, 0, 0
end

M.capture = capture
M.apply = apply
M.setLift = setLift
M.updateGFX = updateGFX
M.onReset = onReset

return M
