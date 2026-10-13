-- SLRR Garage: the photo studio.
-- Part pictures in the catalog and on the shelf are real photographs, so they carry the car's
-- textures, paint and livery. A second copy of the car - the studio car - is parked out of
-- sight on the garage roof. To photograph a part, everything else on the studio car is made
-- invisible and an off-screen view that sees only that car circles the part, saving one picture
-- per step of the turntable. The UI plays the pictures back as a spinning part.
--
-- Catalog parts are added to the studio car as extra meshes when it is parked, behind the fade
-- that covers the drive-in - as many as one vehicle can carry - and photographed in the
-- background. The pictures stay on disk, so a part is only ever photographed once per paint job
-- and the catalog has less and less left to load each visit.

local M = {}

local jbeamLoader = require('jbeam/loader')

local PHOTO_DIR = '/temp/slrr_garage/photos/'
local FRAMES = 24               -- pictures per full turn
local SIZE = 208                -- picture size in pixels
local TILT = math.rad(22)       -- how far the camera looks down on the part
local SETTLE_TIME = 1.2         -- seconds a freshly built studio car is left to settle
local VIEW_NAME = 'slrrGarageStudio'
local MAX_MESHES = 1000         -- the engine stops at 1024 meshes per vehicle
local STEP_WAIT = 1              -- frames between moving the camera and saving the picture

local studioId
local playerId
local model
local settle            -- seconds left before the studio car may be photographed (nil = ready)
local rebuilding = false
local spawning = false  -- the studio car is being parked right now (its id is not known yet)
local queue = {}        -- requests waiting: { key, slotPath | part }
local queued = {}
local urgentCount = 0   -- urgent requests of the current page sit at the front of the queue
local done = {}         -- key -> true (photographed this session or found on disk)
local job               -- request being photographed
local rv
local extras = {}       -- part name -> true: loaded on the studio car as extra meshes
local wantExtras        -- part names to add at the next rebuild
local resolvePart       -- function(partName) -> part, filename
local onPhoto           -- function(key, info)
local entryConfig       -- config the studio car is built from
local entryDamage       -- damage record to put on it
local spawnPos, spawnRot

----------------------------------------------------------------------------------------------
-- files

local function safeName(text)
  return (tostring(text):gsub('[^%w_%-]', '_'))
end

local function basePath(key)
  return PHOTO_DIR .. safeName(model) .. '/' .. safeName(key)
end

local function photoInfo(key)
  return { key = key, base = basePath(key), frames = FRAMES, size = SIZE }
end

local function onDisk(key)
  return FS:fileExists(basePath(key) .. '_' .. (FRAMES - 1) .. '.png')
end

----------------------------------------------------------------------------------------------
-- the studio car

local function studio()
  return studioId and getObjectByID(studioId)
end

local function vdata()
  local vd = studioId and core_vehicle_manager.getVehicleData(studioId)
  return vd and vd.vdata
end

local function basisFrom(ref, back, left)
  local y = (back - ref):normalized()
  local z = (left - ref):cross(y):normalized()
  local x = y:cross(z):normalized()
  return x, y, z
end

-- jbeam space -> world for the studio car, from its ref nodes
local function frame()
  local veh, data = studio(), vdata()
  local rn = data and data.refNodes and data.refNodes[0]
  if not veh or not rn then return nil end
  local nodes = data.nodes
  local refInit = vec3(nodes[rn.ref].pos)
  local ix, iy, iz = basisFrom(refInit, vec3(nodes[rn.back].pos), vec3(nodes[rn.left].pos))
  local refAbs = veh:getNodeAbsPosition(rn.ref)
  local wx, wy, wz = basisFrom(refAbs, veh:getNodeAbsPosition(rn.back), veh:getNodeAbsPosition(rn.left))
  return function(p)
    local r = p - refInit
    return refAbs + wx * r:dot(ix) + wy * r:dot(iy) + wz * r:dot(iz)
  end, wx, wy, wz
end

-- meshes (name + flexmesh id) that make up a request
local function meshesOf(request)
  local data = vdata()
  local list = {}
  if not data then return list end
  local prefix = request.slotPath or ('/slrrStudio/' .. request.part .. '/')
  for _, fb in pairs(data.flexbodies or {}) do
    if fb.meshLoaded and fb.fid and type(fb.partPath) == 'string' and fb.partPath:sub(1, #prefix) == prefix then
      list[#list + 1] = fb
    end
  end
  return list
end

-- world centre and radius of a set of flexmeshes (a sample of their vertices is enough)
local function boundsOf(meshes, toWorld)
  local veh = studio()
  local minv, maxv = vec3(math.huge, math.huge, math.huge), vec3(-math.huge, -math.huge, -math.huge)
  local found = false
  for _, fb in ipairs(meshes) do
    local fm = veh:getFlexmesh(fb.fid)
    local n = fm and fm:getVertexCount() or 0
    local step = math.max(1, math.floor(n / 300))
    for i = 0, n - 1, step do
      local p = fm:getInitVertexPos(i)
      minv:setMin(p); maxv:setMax(p)
      found = true
    end
  end
  if not found then return nil end
  return toWorld((minv + maxv) * 0.5), math.max(0.05, (maxv - minv):length() * 0.5)
end

----------------------------------------------------------------------------------------------
-- photographing

local function closeView()
  if rv then
    RenderViewManagerInstance:destroyView(rv)
    rv = nil
  end
end

local function openView()
  if rv then return rv end
  rv = RenderViewManagerInstance:getOrCreateView(VIEW_NAME)
  rv.luaOwned = true
  rv.namedTexTargetColor = VIEW_NAME
  rv.renderCubemap = false
  rv.renderEditorIcons = false
  rv.clearColor = ColorI(255, 0, 255, 255)   -- a colour no car part has; the UI cuts it out
  rv.fov = math.rad(90)
  rv.resolution = Point2I(SIZE, SIZE)
  rv.viewPort = RectI(0, 0, SIZE, SIZE)
  rv:enterFocusObjectsMode()
  rv:addFocusObject(studio())
  rv:maskSet(1)
  return rv
end

local function aim(index)
  local a = -index * 2 * math.pi / FRAMES       -- clockwise seen from above
  local flat = job.wy * math.cos(a) + job.wx * math.sin(a)
  local pos = job.center + (flat * math.cos(TILT) + job.wz * math.sin(TILT)) * job.dist
  local m = MatrixF()
  m:createOrientFromDirUp((job.center - pos):normalized(), job.wz)
  m:setPosition(pos)
  rv.cameraMatrix = m
end

local function beginJob(request)
  local veh = studio()
  local toWorld, wx, wy, wz = frame()
  local meshes = meshesOf(request)
  if not veh or not toWorld or #meshes == 0 then return false end
  local center, radius = boundsOf(meshes, toWorld)
  if not center then return false end
  veh:setMeshAlpha(0, '', false)
  for _, fb in ipairs(meshes) do veh:setMeshAlpha(1, fb.mesh, false) end
  openView()
  local r = radius * 0.96
  rv.frustum = Frustum.constructOrtho(-r, r, r, -r, 0.05, radius * 2 + 8)
  job = { request = request, center = center, wx = wx, wy = wy, wz = wz, dist = radius + 4, index = 0, wait = 3 }
  aim(0)
  return true
end

local function stepJob()
  -- the view needs a couple of frames to catch up with a moved camera before it is saved
  job.wait = job.wait - 1
  if job.wait > 0 then return end
  rv:saveToDisk(basePath(job.request.key) .. '_' .. job.index .. '.png')
  job.index = job.index + 1
  local request = job.request
  if job.index == 1 and request.urgent and not request.stilled then
    -- a part the player is looking at: hand over one still straight away and come back for the
    -- full turn once everything else on the page has its still too
    request.stilled = true
    job = nil
    local info = photoInfo(request.key)
    info.frames = 1
    if onPhoto then onPhoto(info.key, info) end
    urgentCount = math.min(urgentCount, #queue) + 1
    table.insert(queue, urgentCount, request)
    queued[request.key] = true
    return
  end
  if job.index >= FRAMES then
    local key, tell = job.request.key, job.request.urgent
    job = nil
    done[key] = true
    if tell and onPhoto then onPhoto(key, photoInfo(key)) end
    return
  end
  aim(job.index)
  job.wait = STEP_WAIT
end

----------------------------------------------------------------------------------------------
-- (re)building the studio car

local function rebuild()
  local veh = studio()
  if not veh or not entryConfig then return end
  rebuilding = true
  closeView()
  jbeamLoader.onFileChanged()   -- the game must not hand back a cached build without our extras
  -- a rebuilt vehicle normally pulls the player into it; this one must not
  veh:setDynDataFieldbyName("autoEnterVehicle", 0, "false")
  veh:respawn(serialize(entryConfig))
end

-- jbeam loading hook: add the wanted catalog parts to the studio car as extra meshes
function M.onJbeamLoadingPhase2(objID, vehicle)
  if not wantExtras or not resolvePart then return end
  if spawning then if objID == playerId then return end elseif objID ~= studioId then return end
  local names = wantExtras
  wantExtras = nil
  extras = {}
  local ok, err = pcall(function()
    local template
    local nextKey, count = 0, 0
    for key, fb in pairs(vehicle.flexbodies or {}) do
      count = count + 1
      if type(key) == 'number' then
        if key >= nextKey then nextKey = key + 1 end
        if not template or key < template.key then template = { key = key, fb = fb } end
      end
    end
    local group = {}
    local refPart = vehicle.refNodes and vehicle.refNodes[0] and vehicle.refNodes[0].partPath
    for _, node in pairs(vehicle.nodes or {}) do
      if node.cid and node.partPath == refPart and #group < 80 then group[#group + 1] = node.cid end
    end
    if not template or #group < 3 then
      for _, partName in ipairs(names) do extras[partName] = true end   -- answered with "no picture"
      return
    end
    vehicle.flexbodies = vehicle.flexbodies or {}
    for _, partName in ipairs(names) do
      local part = resolvePart(partName)
      local rows = part and type(part.flexbodies) == 'table' and part.flexbodies or {}
      if count + math.min(12, #rows) > MAX_MESHES then break end     -- the rest waits for the next rebuild
      extras[partName] = true
      local added = 0
      for i, row in ipairs(rows) do
        if i > 1 and type(row) == 'table' and type(row[1]) == 'string' and row[1] ~= '' and row[1]:sub(1, 1) ~= '$' and added < 12 then
          -- start from one of the car's own entries so paint and livery settings carry over
          local entry = deepcopy(template.fb)
          entry.mesh, entry.originalMesh, entry.fid, entry.meshLoaded = row[1], nil, nil, nil
          entry.pos, entry.rot, entry.scale = nil, nil, nil
          for _, cell in ipairs(row) do
            if type(cell) == 'table' and (cell.pos or cell.rot or cell.scale) then
              entry.pos, entry.rot, entry.scale = cell.pos, cell.rot, cell.scale
            end
          end
          entry._group_nodes = group
          entry.partPath = '/slrrStudio/' .. partName .. '/'
          entry.partOrigin = partName
          entry.cid = nextKey
          vehicle.flexbodies[nextKey] = entry
          nextKey = nextKey + 1
          added = added + 1
          count = count + 1
        end
      end
    end
  end)
  if not ok then log('W', 'slrr_garage', 'studio: adding catalog parts failed: ' .. tostring(err)) end
end

function M.onVehicleSpawned(id)
  if id ~= studioId then return end
  rebuilding = false
  settle = SETTLE_TIME
  local veh = studio()
  if not veh then return end
  veh:setMeshAlpha(0, '', false)
  veh:queueLuaCommand('controller.setFreeze(1) if electrics.setIgnitionLevel then electrics.setIgnitionLevel(0) end input.event("parkingbrake", 1, FILTER_DIRECT)')
  if entryDamage and #(entryDamage.beams or {}) > 0 then
    veh:queueLuaCommand('extensions.load("slrrGarageVeh") slrrGarageVeh.apply(' .. serialize(entryDamage) .. ')')
  end
end

----------------------------------------------------------------------------------------------
-- public

-- Park a studio copy of the player's car at pos/rot. config is the car as it came in.
function M.start(_playerId, config, damage, pos, rot, resolver, callback, background)
  M.stop()
  local player = getObjectByID(_playerId)
  if not player or not RenderViewManagerInstance then return false end
  playerId, model = _playerId, player:getJBeamFilename()
  entryConfig, entryDamage = deepcopy(config), damage
  resolvePart, onPhoto = resolver, callback
  spawnPos, spawnRot = pos, rot
  queue, queued, done, extras, job, urgentCount = {}, {}, {}, {}, nil, 0
  -- background = requests for every catalog part; the ones without pictures yet ride along
  wantExtras = nil
  for _, request in ipairs(background or {}) do
    if onDisk(request.key) then
      done[request.key] = true
    else
      wantExtras = wantExtras or {}
      wantExtras[#wantExtras + 1] = request.part
      queued[request.key] = true
      queue[#queue + 1] = request
    end
  end
  rebuilding, spawning = true, true
  jbeamLoader.onFileChanged()   -- the game must not hand back a cached build without our extras
  local ok, veh = pcall(spawn.spawnVehicle, model, serialize(entryConfig), pos, rot, { autoEnterVehicle = false, vehicleName = 'slrrGarageStudioCar' })
  if not ok or not veh then
    log('W', 'slrr_garage', 'studio: could not park the studio car: ' .. tostring(veh))
    rebuilding, spawning, wantExtras = false, false, nil
    return false
  end
  studioId = veh:getID()
  rebuilding, spawning = false, false
  settle = SETTLE_TIME
  M.onVehicleSpawned(studioId)
  return true
end

function M.stop()
  closeView()
  local veh = studio()
  if veh then veh:delete() end
  studioId, playerId, settle, job, wantExtras = nil, nil, nil, nil, nil
  queue, queued, extras = {}, {}, {}
  rebuilding, spawning = false, false
end

function M.isActive() return studioId ~= nil end

-- is this exact part fitted to the studio car at this slot?
function M.hasPart(slotPath, partName)
  local data = vdata()
  local wanted = tostring(slotPath) .. tostring(partName)
  for _, fb in pairs(data and data.flexbodies or {}) do
    if fb.partPath == wanted then return true end
  end
  return false
end
function M.getStudioId() return studioId end

-- Ask for a part's photographs.
--   { key = ..., slotPath = "/a/b/" }  a part that is on the car as it came in
--   { key = ..., part = "name" }       any part of this model (catalog)
-- Ready ones are answered straight away through the callback. urgent = the player is looking
-- at it now, so it goes ahead of the parts being photographed in the background.
function M.request(request, urgent)
  if not studioId or not request or not request.key then return end
  local key = request.key
  if done[key] or onDisk(key) then
    done[key] = true
    if urgent and onPhoto then onPhoto(key, photoInfo(key)) end
    return
  end
  request.urgent = urgent
  if job and job.request.key == key then
    job.request.urgent = job.request.urgent or urgent
    return
  end
  if queued[key] then
    if not urgent then return end
    for i, other in ipairs(queue) do
      if other.key == key then
        table.remove(queue, i)
        if i <= urgentCount then urgentCount = urgentCount - 1 end
        other.urgent = true
        request = other
        break
      end
    end
  end
  queued[key] = true
  if urgent then
    urgentCount = math.min(urgentCount, #queue) + 1
    table.insert(queue, urgentCount, request)
  else
    queue[#queue + 1] = request
  end
end

-- the next urgent requests start again from the front of the queue
function M.newPage() urgentCount = 0 end

function M.update(dt)
  if not studioId then return end
  if not studio() then studioId = nil return end
  if rebuilding then return end
  if settle then
    settle = settle - dt
    if settle > 0 then return end
    settle = nil
  end
  if job then
    stepJob()
    return
  end
  if #queue == 0 then
    closeView()
    return
  end
  -- photograph the first request whose meshes are on the studio car
  local waiting = false       -- is something the player is looking at not loaded?
  for i, request in ipairs(queue) do
    if i > urgentCount and waiting then break end
    if not (request.slotPath or extras[request.part]) then
      waiting = waiting or i <= urgentCount
    else
      table.remove(queue, i)
      if i <= urgentCount then urgentCount = urgentCount - 1 end
      queued[request.key] = nil
      if not beginJob(request) then
        done[request.key] = true
        if request.urgent and onPhoto then onPhoto(request.key, { key = request.key, none = true }) end
      end
      return
    end
  end
  -- Only a part the player is looking at is worth the pause of a rebuild; what is left of the
  -- background work waits for refill(), which the garage calls while the screen is dark anyway.
  closeView()
  if waiting then M.refill(true) end
end

-- Rebuild the studio car with the parts still waiting for their pictures, in queue order.
function M.refill(force)
  if not studioId or rebuilding or settle or job then return end
  local names, seen = {}, {}
  for _, request in ipairs(queue) do
    if request.slotPath or extras[request.part] then
      if not force then return end       -- still busy with what is loaded
    elseif not seen[request.part] then
      seen[request.part] = true
      names[#names + 1] = request.part
    end
  end
  if #names > 0 then
    wantExtras = names
    rebuild()
  end
end

return M
