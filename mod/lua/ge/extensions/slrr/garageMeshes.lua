-- SLRR Garage: 3D models of parts, for the catalog and the shelf.
-- The game cannot draw a single car part inside a UI panel, so this module reads the part's
-- meshes straight out of the vehicle's Collada (.dae) files and hands them to the UI, which
-- renders and spins them itself. Each triangle keeps the name of its material so the UI can
-- colour paint, rubber, glass and metal differently.
--
-- Meshes are sent at close to full detail; only very heavy ones are thinned out. Reading is
-- done one part at a time from the garage's update loop and kept for the rest of the session.

local M = {}

local MAX_TRIS = 20000          -- above this a mesh is thinned out before it is sent
local MAX_OPEN_FILES = 3        -- .dae files kept in memory at once (they are tens of MB each)
local MAX_MESHES_PER_PART = 10

local model
local cache = {}                -- part name -> { v = {...}, t = {...}, m = {...}, mats = {...} } or false
local queue, queued = {}, {}
local resolvePart               -- function(partName) -> part table, source jbeam filename
local onReady                   -- function(partName, meshOrFalse)

local openFiles, openOrder = {}, {}   -- path -> { content, nodes, geomAt }
local dirListing = {}                  -- directory -> list of .dae paths

----------------------------------------------------------------------------------------------
-- reading .dae files

local function daeFilesIn(dir, recursive)
  local key = dir .. (recursive and '*' or '')
  local list = dirListing[key]
  if not list then
    list = FS:findFiles(dir, '*.dae', recursive and -1 or 0, false, false) or {}
    dirListing[key] = list
  end
  return list
end

-- load a .dae and index which scene node (= mesh name) uses which geometry
local function openFile(path)
  local file = openFiles[path]
  if file then return file end
  local content = readFile(path)
  if not content then
    openFiles[path] = { nodes = {}, geomAt = {} }
    return openFiles[path]
  end
  file = { content = content, nodes = {}, geomAt = {} }
  local pos = content:find('<library_visual_scenes', 1, true) or 1
  while true do
    local s, e = content:find('<instance_geometry url="#', pos, true)
    if not s then break end
    local geom, name = content:match('^([^"]+)"%s+name="([^"]+)"', e + 1)
    if geom and name then
      local before = content:sub(math.max(1, s - 420), s - 1)
      local matrix = before:match('<matrix[^>]*>([^<]*)</matrix>%s*$')
      file.nodes[name] = { geom = geom, matrix = matrix }
    end
    pos = e + 1
  end
  pos = 1
  while true do
    local s, e = content:find('<geometry id="', pos, true)
    if not s then break end
    local id = content:match('^([^"]+)', e + 1)
    if id then file.geomAt[id] = s end
    pos = e + 1
  end
  openFiles[path] = file
  openOrder[#openOrder + 1] = path
  while #openOrder > MAX_OPEN_FILES do
    local old = table.remove(openOrder, 1)
    if openFiles[old] then openFiles[old].content = nil; openFiles[old] = nil end
  end
  return file
end

local function parseMatrix(text)
  if not text then return nil end
  local m = {}
  for num in text:gmatch('%S+') do m[#m + 1] = tonumber(num) end
  if #m ~= 16 then return nil end
  local identity = true
  for i = 1, 16 do
    local want = ((i - 1) % 5 == 0) and 1 or 0
    if math.abs(m[i] - want) > 1e-6 then identity = false break end
  end
  return (not identity) and m or nil
end

-- append one geometry's triangles to the mesh being assembled
local function readGeometry(file, node, offset, mesh)
  local content = file.content
  local start = file.geomAt[node.geom]
  if not content or not start then return false end
  local stop = content:find('</geometry>', start, true) or #content

  local _, fa = content:find('<float_array[^>]*>', start)
  if not fa or fa > stop then return false end
  local faEnd = content:find('</float_array>', fa, true)
  if not faEnd then return false end
  local xs, ys, zs, tris, triMat = mesh.xs, mesh.ys, mesh.zs, mesh.tris, mesh.triMat
  local base = #xs
  local m = parseMatrix(node.matrix)
  local ox, oy, oz = offset and tonumber(offset.x) or 0, offset and tonumber(offset.y) or 0, offset and tonumber(offset.z) or 0
  local n, x, y = 0, 0, 0
  for num in content:sub(fa + 1, faEnd - 1):gmatch('%S+') do
    n = n + 1
    local value = tonumber(num) or 0
    local k = n % 3
    if k == 1 then x = value
    elseif k == 2 then y = value
    else
      local z = value
      if m then
        x, y, z = m[1] * x + m[2] * y + m[3] * z + m[4], m[5] * x + m[6] * y + m[7] * z + m[8], m[9] * x + m[10] * y + m[11] * z + m[12]
      end
      local i = #xs + 1
      xs[i], ys[i], zs[i] = x + ox, y + oy, z + oz
    end
  end

  local pos = faEnd
  while true do
    local ts, te = content:find('<triangles', pos, true)
    if not ts or ts > stop then break end
    local blockEnd = content:find('</triangles>', te, true)
    if not blockEnd then break end
    local ps, pe = content:find('<p>', te, true)
    if ps and ps < blockEnd then
      local header = content:sub(te, ps)
      local matName = (header:match('material="([^"]*)"') or ''):gsub('%-material$', '')
      local matId = mesh.matIndex[matName]
      if not matId then
        mesh.mats[#mesh.mats + 1] = matName
        matId = #mesh.mats - 1
        mesh.matIndex[matName] = matId
      end
      local stride, vertexOffset = 1, 0
      for semantic, off in header:gmatch('<input semantic="([^"]+)"[^>]-offset="(%d+)"') do
        off = tonumber(off)
        if off + 1 > stride then stride = off + 1 end
        if semantic == 'VERTEX' then vertexOffset = off end
      end
      local pClose = content:find('</p>', pe, true) or blockEnd
      local k, corner, a, b = 0, 0, 0, 0
      for num in content:sub(pe + 1, pClose - 1):gmatch('%d+') do
        if k % stride == vertexOffset then
          corner = corner + 1
          local index = base + tonumber(num) + 1
          if corner == 1 then a = index
          elseif corner == 2 then b = index
          else
            tris[#tris + 1] = a; tris[#tris + 1] = b; tris[#tris + 1] = index
            triMat[#triMat + 1] = matId
            corner = 0
          end
        end
        k = k + 1
      end
    end
    pos = blockEnd
  end
  return true
end

----------------------------------------------------------------------------------------------
-- packing for the UI

-- Positions are sent as integers on a fine grid. Vertices that share a grid cell are merged,
-- which also welds the seams Collada leaves between faces. A mesh over the triangle budget is
-- redone on a coarser grid until it fits.
local function pack(mesh)
  local xs, ys, zs, tris, triMat = mesh.xs, mesh.ys, mesh.zs, mesh.tris, mesh.triMat
  local n = #xs
  if n == 0 or #tris == 0 then return nil end
  local minx, miny, minz, maxx, maxy, maxz = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
  for i = 1, n do
    local x, y, z = xs[i], ys[i], zs[i]
    if x < minx then minx = x end
    if y < miny then miny = y end
    if z < minz then minz = z end
    if x > maxx then maxx = x end
    if y > maxy then maxy = y end
    if z > maxz then maxz = z end
  end
  local size = math.max(maxx - minx, maxy - miny, maxz - minz, 1e-4)
  local res = 1000
  for _ = 1, 12 do
    local cell = size / res
    local cellOf, sumX, sumY, sumZ, count, remap = {}, {}, {}, {}, {}, {}
    local nv = 0
    for i = 1, n do
      local key = math.floor((xs[i] - minx) / cell) + math.floor((ys[i] - miny) / cell) * 1024 + math.floor((zs[i] - minz) / cell) * 1048576
      local id = cellOf[key]
      if not id then
        nv = nv + 1
        id = nv
        cellOf[key] = id
        sumX[id], sumY[id], sumZ[id], count[id] = 0, 0, 0, 0
      end
      sumX[id], sumY[id], sumZ[id], count[id] = sumX[id] + xs[i], sumY[id] + ys[i], sumZ[id] + zs[i], count[id] + 1
      remap[i] = id
    end
    local t, tm = {}, {}
    for i = 1, #tris, 3 do
      local a, b, c = remap[tris[i]], remap[tris[i + 1]], remap[tris[i + 2]]
      if a and b and c and a ~= b and b ~= c and a ~= c then
        t[#t + 1] = a - 1; t[#t + 1] = b - 1; t[#t + 1] = c - 1
        tm[#tm + 1] = triMat[(i + 2) / 3]
      end
    end
    if #tm <= MAX_TRIS or res <= 12 then
      if #tm == 0 then return nil end
      local v = {}
      for id = 1, nv do
        local c = count[id]
        v[#v + 1] = math.floor((sumX[id] / c - minx) / size * 4000 + 0.5)
        v[#v + 1] = math.floor((sumY[id] / c - miny) / size * 4000 + 0.5)
        v[#v + 1] = math.floor((sumZ[id] / c - minz) / size * 4000 + 0.5)
      end
      return { v = v, t = t, m = tm, mats = mesh.mats }
    end
    -- too heavy: coarser grid, sized from how far over budget this pass was
    res = math.max(12, math.floor(res * math.min(0.8, math.sqrt(MAX_TRIS / #tm))))
  end
  return nil
end

----------------------------------------------------------------------------------------------
-- building one part's preview

local function meshNamesOf(part)
  local names = {}
  for _, section in ipairs({ 'flexbodies', 'props' }) do
    local rows = part[section]
    if type(rows) == 'table' then
      local meshColumn = section == 'props' and 2 or 1
      for _, row in ipairs(rows) do
        if type(row) == 'table' then
          local mesh = row[meshColumn]
          if type(mesh) == 'string' and mesh ~= 'mesh' and mesh ~= 'func' and mesh ~= 'SPOTLIGHT' and mesh ~= 'POINTLIGHT' and mesh ~= '' then
            local offset
            for _, cell in ipairs(row) do
              if type(cell) == 'table' and type(cell.pos) == 'table' and tonumber(cell.pos.x) then offset = cell.pos end
            end
            names[#names + 1] = { mesh = mesh, offset = section == 'flexbodies' and offset or nil }
            if #names >= MAX_MESHES_PER_PART then return names end
          end
        end
      end
    end
    if #names > 0 then return names end   -- props only stand in when a part has no flexbodies
  end
  return names
end

-- which .dae holds this mesh? look next to the part's jbeam first, then further up the tree
local function findMesh(meshName, sourceFile)
  local dir = sourceFile and sourceFile:match('^(.*/)') or nil
  local tried = {}
  local depth = 0
  while dir and depth < 4 and select(2, dir:gsub('/', '')) >= 3 do
    for _, path in ipairs(daeFilesIn(dir, false)) do
      if not tried[path] then
        tried[path] = true
        local file = openFile(path)
        if file.nodes[meshName] then return file, file.nodes[meshName] end
      end
    end
    dir = dir:match('^(.*/)[^/]+/$')
    depth = depth + 1
  end
  local root = sourceFile and sourceFile:match('^(/vehicles/[^/]+/)')
  if root and root ~= '/vehicles/common/' then
    for _, path in ipairs(daeFilesIn(root, true)) do
      if not tried[path] then
        tried[path] = true
        local file = openFile(path)
        if file.nodes[meshName] then return file, file.nodes[meshName] end
      end
    end
  end
  return nil
end

local function build(partName)
  local part, sourceFile = resolvePart(partName)
  if not part then return false end
  local names = meshNamesOf(part)
  if #names == 0 then return false end
  local mesh = { xs = {}, ys = {}, zs = {}, tris = {}, triMat = {}, mats = {}, matIndex = {} }
  for _, entry in ipairs(names) do
    local file, node = findMesh(entry.mesh, sourceFile)
    if file then readGeometry(file, node, entry.offset, mesh) end
  end
  return pack(mesh) or false
end

----------------------------------------------------------------------------------------------
-- public

function M.setup(_model, resolver, callback)
  if _model ~= model then
    model = _model
    cache = {}
  end
  resolvePart, onReady = resolver, callback
end

-- ask for previews; ready ones are answered straight away, the rest as they are worked out
function M.request(partNames)
  for _, partName in ipairs(partNames) do
    local hit = cache[partName]
    if hit ~= nil then
      if onReady then onReady(partName, hit) end
    elseif not queued[partName] then
      queued[partName] = true
      queue[#queue + 1] = partName
    end
  end
end

-- call every frame; works on at most one part per call
function M.update()
  if #queue == 0 then return end
  local partName = table.remove(queue, 1)
  queued[partName] = nil
  local ok, mesh = pcall(build, partName)
  if not ok then
    log('W', 'slrr_garage', 'preview for ' .. tostring(partName) .. ' failed: ' .. tostring(mesh))
    mesh = false
  end
  cache[partName] = mesh
  if onReady then onReady(partName, mesh) end
end

function M.pending() return #queue end

-- drop the big files from memory (the garage closed)
function M.release()
  queue, queued = {}, {}
  for _, file in pairs(openFiles) do file.content = nil end
  openFiles, openOrder = {}, {}
end

return M
