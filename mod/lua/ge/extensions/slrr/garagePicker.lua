-- SLRR Garage: which car part is under the mouse cursor?
-- The engine exposes no mesh raycast for vehicles, only the vertices of every flexmesh. So the
-- picker caches those vertices once (in the vehicle's own jbeam space, spread over a few frames)
-- and treats each one as a small sphere: the closest sphere the cursor ray passes through names
-- the mesh. The sphere size follows the vertex density of the mesh, so big sparse panels are as
-- easy to hit as dense little brackets.

local M = {}

local ffi = require('ffi')

local sqrt, min, max, huge = math.sqrt, math.min, math.max, math.huge

local BUILD_BUDGET_MS = 3.5   -- time per frame spent reading vertices while the cache builds
local MIN_RADIUS, MAX_RADIUS = 0.014, 0.16

local vehId
local entries = {}        -- array of {mesh, partPath, n, verts(float[n*3]), bounds, radius}
local buildQueue          -- flexbodies still waiting to be cached
local buildCursor
local ready = false

-- jbeam space <-> world: origin and orthonormal bases taken from the ref nodes
local refInit, refAbs = vec3(), vec3()
local ix, iy, iz = vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1)   -- jbeam basis from initial node positions
local wx, wy, wz = vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1)   -- same axes, as they sit in the world now

local function basisFrom(ref, back, left)
  local y = (back - ref):normalized()
  local xRaw = left - ref
  local z = xRaw:cross(y):normalized()
  local x = y:cross(z):normalized()
  return x, y, z
end

local function updateFrame()
  local veh = getObjectByID(vehId)
  local vd = core_vehicle_manager.getVehicleData(vehId)
  if not veh or not vd or not vd.vdata.refNodes or not vd.vdata.refNodes[0] then return false end
  local rn = vd.vdata.refNodes[0]
  local nodes = vd.vdata.nodes
  if not (nodes[rn.ref] and nodes[rn.back] and nodes[rn.left]) then return false end
  refInit = vec3(nodes[rn.ref].pos)
  ix, iy, iz = basisFrom(refInit, vec3(nodes[rn.back].pos), vec3(nodes[rn.left].pos))
  refAbs = veh:getNodeAbsPosition(rn.ref)
  wx, wy, wz = basisFrom(refAbs, veh:getNodeAbsPosition(rn.back), veh:getNodeAbsPosition(rn.left))
  return true
end

local function worldToLocal(p)
  local r = p - refAbs
  return refInit + ix * r:dot(wx) + iy * r:dot(wy) + iz * r:dot(wz)
end

local function dirToLocal(d)
  return ix * d:dot(wx) + iy * d:dot(wy) + iz * d:dot(wz)
end

local function localToWorld(p)
  local r = p - refInit
  return refAbs + wx * r:dot(ix) + wy * r:dot(iy) + wz * r:dot(iz)
end

local function cacheFlexbody(veh, fb)
  local fm = veh:getFlexmesh(fb.fid)
  if not fm then return end
  local n = fm:getVertexCount()
  if n <= 0 then return end
  local verts = ffi.new("float[?]", n * 3)
  local minx, miny, minz, maxx, maxy, maxz = huge, huge, huge, -huge, -huge, -huge
  for i = 0, n - 1 do
    local p = fm:getInitVertexPos(i)
    local x, y, z = p.x, p.y, p.z
    verts[i * 3], verts[i * 3 + 1], verts[i * 3 + 2] = x, y, z
    if x < minx then minx = x end
    if y < miny then miny = y end
    if z < minz then minz = z end
    if x > maxx then maxx = x end
    if y > maxy then maxy = y end
    if z > maxz then maxz = z end
  end
  local dx, dy, dz = maxx - minx, maxy - miny, maxz - minz
  local area = dx * dy + dy * dz + dx * dz
  local radius = clamp(1.15 * sqrt(area / n), MIN_RADIUS, MAX_RADIUS)
  entries[#entries + 1] = {
    mesh = fb.mesh, partPath = fb.partPath, n = n, verts = verts, radius = radius,
    minx = minx, miny = miny, minz = minz, maxx = maxx, maxy = maxy, maxz = maxz,
  }
end

-- start (re)building the cache for a vehicle
function M.begin(id)
  vehId = id
  entries = {}
  ready = false
  buildQueue = {}
  buildCursor = 1
  local vd = core_vehicle_manager.getVehicleData(id)
  if not vd or not vd.vdata.flexbodies then return end
  for _, fb in pairs(vd.vdata.flexbodies) do
    if fb.fid and fb.meshLoaded and fb.mesh and fb.partPath then
      buildQueue[#buildQueue + 1] = fb
    end
  end
end

-- call every frame; returns true once every mesh is cached
function M.update()
  if ready or not buildQueue then return ready end
  local veh = getObjectByID(vehId)
  if not veh then return false end
  local timer = hptimer()
  while buildCursor <= #buildQueue do
    cacheFlexbody(veh, buildQueue[buildCursor])
    buildCursor = buildCursor + 1
    if timer:stop() > BUILD_BUDGET_MS then return false end
  end
  buildQueue = nil
  ready = true
  return true
end

function M.isReady() return ready end

function M.clear()
  entries = {}
  buildQueue = nil
  ready = false
  vehId = nil
end

-- ray/box slab test, returns entry distance (or nil)
local function rayBox(ox, oy, oz, dx, dy, dz, e, pad)
  local tmin, tmax = 0, huge
  local inv, t1, t2
  if dx ~= 0 then
    inv = 1 / dx; t1 = (e.minx - pad - ox) * inv; t2 = (e.maxx + pad - ox) * inv
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > tmin then tmin = t1 end
    if t2 < tmax then tmax = t2 end
  elseif ox < e.minx - pad or ox > e.maxx + pad then return nil end
  if dy ~= 0 then
    inv = 1 / dy; t1 = (e.miny - pad - oy) * inv; t2 = (e.maxy + pad - oy) * inv
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > tmin then tmin = t1 end
    if t2 < tmax then tmax = t2 end
  elseif oy < e.miny - pad or oy > e.maxy + pad then return nil end
  if dz ~= 0 then
    inv = 1 / dz; t1 = (e.minz - pad - oz) * inv; t2 = (e.maxz + pad - oz) * inv
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > tmin then tmin = t1 end
    if t2 < tmax then tmax = t2 end
  elseif oz < e.minz - pad or oz > e.maxz + pad then return nil end
  if tmax < tmin then return nil end
  return tmin
end

-- Pick with a world-space ray. `isHidden(meshName)` lets the caller skip meshes that are not
-- shown right now. Returns partPath, meshName, worldHitPos (or nil).
function M.pick(rayPos, rayDir, isHidden)
  if not ready or not updateFrame() then return nil end
  local o = worldToLocal(rayPos)
  local d = dirToLocal(rayDir):normalized()
  local ox, oy, oz, dx, dy, dz = o.x, o.y, o.z, d.x, d.y, d.z

  local bestScore, bestEntry, bestT = huge, nil, nil
  for i = 1, #entries do
    local e = entries[i]
    if not (isHidden and isHidden(e.mesh)) then
      local r = e.radius
      local tBox = rayBox(ox, oy, oz, dx, dy, dz, e, r)
      -- a mesh whose box starts behind the best hit so far cannot win
      if tBox and tBox < bestScore then
        local r2 = r * r
        local verts = e.verts
        for j = 0, e.n * 3 - 3, 3 do
          local vx, vy, vz = verts[j] - ox, verts[j + 1] - oy, verts[j + 2] - oz
          local t = vx * dx + vy * dy + vz * dz
          if t > 0 and t < bestScore + r then
            local off2 = vx * vx + vy * vy + vz * vz - t * t
            if off2 < r2 then
              -- rays that pass nearer the vertex count as slightly closer hits
              local score = t + (off2 > 0 and sqrt(off2) or 0) * 0.5
              if score < bestScore then bestScore, bestEntry, bestT = score, e, t end
            end
          end
        end
      end
    end
  end

  if not bestEntry then return nil end
  return bestEntry.partPath, bestEntry.mesh, localToWorld(o + d * bestT)
end

-- the eight world-space corners of the box around the given set of meshes (for outlining a part)
function M.getMeshesCorners(meshSet)
  if not ready or not updateFrame() then return nil end
  local minx, miny, minz, maxx, maxy, maxz = huge, huge, huge, -huge, -huge, -huge
  local found = false
  for i = 1, #entries do
    local e = entries[i]
    if meshSet[e.mesh] then
      found = true
      minx, miny, minz = min(minx, e.minx), min(miny, e.miny), min(minz, e.minz)
      maxx, maxy, maxz = max(maxx, e.maxx), max(maxy, e.maxy), max(maxz, e.maxz)
    end
  end
  if not found then return nil end
  local pad = 0.02
  minx, miny, minz, maxx, maxy, maxz = minx - pad, miny - pad, minz - pad, maxx + pad, maxy + pad, maxz + pad
  local corners = {}
  for i = 0, 7 do
    corners[i + 1] = localToWorld(vec3(i % 2 == 0 and minx or maxx, math.floor(i / 2) % 2 == 0 and miny or maxy, i < 4 and minz or maxz))
  end
  return corners
end

-- world-space centre and radius of everything belonging to the given set of meshes
function M.getMeshesBounds(meshSet)
  if not ready or not updateFrame() then return nil end
  local minx, miny, minz, maxx, maxy, maxz = huge, huge, huge, -huge, -huge, -huge
  local found = false
  for i = 1, #entries do
    local e = entries[i]
    if meshSet[e.mesh] then
      found = true
      minx, miny, minz = min(minx, e.minx), min(miny, e.miny), min(minz, e.minz)
      maxx, maxy, maxz = max(maxx, e.maxx), max(maxy, e.maxy), max(maxz, e.maxz)
    end
  end
  if not found then return nil end
  local c = vec3((minx + maxx) * 0.5, (miny + maxy) * 0.5, (minz + maxz) * 0.5)
  local radius = vec3(maxx - minx, maxy - miny, maxz - minz):length() * 0.5
  return localToWorld(c), radius
end

return M
