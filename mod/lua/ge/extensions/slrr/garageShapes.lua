-- Wrench Works: stand-alone 3D models of single parts.
-- A vehicle's meshes all live together in a few big Collada (.dae) files, and the game can only
-- show them as part of a whole vehicle. To show one part on its own - turning in the catalog,
-- lying on the shelf - this module cuts the part's geometry out of those files and writes it to
-- a small .dae of its own, which the game then loads like any other static object. The
-- materials keep their names, so the part wears the same textures it does on the car.
--
-- Files are written once to /temp/slrr_garage/shapes/ and reused afterwards.

local M = {}

local SHAPE_DIR = '/temp/slrr_garage/shapes/'
local VERSION = 1               -- bump when the written files change, so old ones are not reused
local MAX_OPEN_FILES = 3        -- .dae files kept in memory at once (they are tens of MB each)
local MAX_MESHES_PER_PART = 16
local MAX_PICK_VERTS = 2500     -- vertices kept per mesh for picking with the mouse

local resolvePart               -- function(partName) -> part table, source jbeam filename
local skin                      -- the car's livery, if it wears one
local cache = {}                -- model|key -> { path, verts } or false
local openFiles, openOrder = {}, {}   -- path -> { content, nodes, geomAt }
local dirListing = {}                  -- directory -> list of .dae paths
local indexes = {}                     -- path -> { nodes, geomAt, asset }: kept when the file itself is dropped
local meshFile = {}                    -- mesh name -> path of the .dae it was found in (false = nowhere)

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
  local index = indexes[path]
  if index then
    -- read before: only the text was dropped, what is where in it is still known
    file = { content = content, nodes = index.nodes, geomAt = index.geomAt, asset = index.asset }
    openFiles[path] = file
    openOrder[#openOrder + 1] = path
    while #openOrder > MAX_OPEN_FILES do
      local old = table.remove(openOrder, 1)
      if openFiles[old] then openFiles[old].content = nil; openFiles[old] = nil end
    end
    return file
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
  file.asset = content:match('<asset>.-</asset>')
  indexes[path] = { nodes = file.nodes, geomAt = file.geomAt, asset = file.asset }
  openFiles[path] = file
  openOrder[#openOrder + 1] = path
  while #openOrder > MAX_OPEN_FILES do
    local old = table.remove(openOrder, 1)
    if openFiles[old] then openFiles[old].content = nil; openFiles[old] = nil end
  end
  return file
end

-- the meshes a part is drawn with and where its jbeam puts them, read from the part as written
-- (good for looking at the part on its own; on the car the game may shift things further)
function M.rowsOfPart(partName)
  local part = resolvePart(partName)
  local rows = {}
  if not part then return rows end
  for _, section in ipairs({ 'flexbodies', 'props' }) do
    local list = part[section]
    if type(list) == 'table' then
      local meshColumn = section == 'props' and 2 or 1
      for _, row in ipairs(list) do
        if type(row) == 'table' then
          local mesh = row[meshColumn]
          if type(mesh) == 'string' and mesh ~= 'mesh' and mesh ~= 'func' and mesh ~= 'SPOTLIGHT' and mesh ~= 'POINTLIGHT' and mesh ~= '' and mesh:sub(1, 1) ~= '$' then
            local entry = { mesh = mesh, origin = partName }
            if section == 'flexbodies' then
              for _, cell in ipairs(row) do
                if type(cell) == 'table' and (cell.pos or cell.rot or cell.scale) then
                  entry.pos, entry.rot, entry.scale = cell.pos, cell.rot, cell.scale
                end
              end
            end
            rows[#rows + 1] = entry
            if #rows >= MAX_MESHES_PER_PART then return rows end
          end
        end
      end
    end
    if #rows > 0 then return rows end   -- props only stand in when a part has no flexbodies
  end
  return rows
end

-- which .dae holds this mesh? look next to the part's jbeam first, then further up the tree
local searchMesh

local function findMesh(meshName, sourceFile)
  local known = meshFile[meshName]
  if known == false then return nil end
  if known then
    local file = openFile(known)
    if file.nodes[meshName] then return file, file.nodes[meshName] end
  end
  local file, node, path = searchMesh(meshName, sourceFile)
  meshFile[meshName] = path or false
  return file, node
end

searchMesh = function(meshName, sourceFile)
  local dir = sourceFile and sourceFile:match('^(.*/)') or nil
  local tried = {}
  local depth = 0
  while dir and depth < 4 and select(2, dir:gsub('/', '')) >= 3 do
    for _, path in ipairs(daeFilesIn(dir, false)) do
      if not tried[path] then
        tried[path] = true
        local file = openFile(path)
        if file.nodes[meshName] then return file, file.nodes[meshName], path end
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
        if file.nodes[meshName] then return file, file.nodes[meshName], path end
      end
    end
  elseif root then
    -- Shared parts (wheels above all) keep their models in sibling folders, hundreds of files
    -- in all. Opening every one is out of the question, so try the few whose file names have
    -- the most words in common with the mesh name.
    local words = {}
    for word in meshName:lower():gmatch('[^_]+') do
      if #word > 1 and word ~= 'wheel' and word ~= 'tire' and not word:match('^%d+x[%d%.]+$') then words[word] = true end
    end
    local ranked = {}
    for _, path in ipairs(daeFilesIn(root, true)) do
      if not tried[path] then
        local score = 0
        local base = (path:match('([^/]+)%.[dD][aA][eE]$') or ''):lower()
        for word in base:gmatch('[^_]+') do
          if words[word] then score = score + 2 end
        end
        for word in pairs(words) do
          if #word >= 5 and base:find(word, 1, true) then score = score + 1 end
        end
        -- the catch-all files come last
        if score == 0 and (base:find('generic', 1, true) or base:find('misc', 1, true) or base:find('commonparts', 1, true) or base:find('steelies', 1, true)) then score = 0.5 end
        if score > 0 then ranked[#ranked + 1] = { path = path, score = score } end
      end
    end
    table.sort(ranked, function(x, y) if x.score ~= y.score then return x.score > y.score end return x.path < y.path end)
    for i = 1, math.min(8, #ranked) do
      local file = openFile(ranked[i].path)
      if file.nodes[meshName] then return file, file.nodes[meshName], ranked[i].path end
    end
  end
  return nil
end

----------------------------------------------------------------------------------------------
-- placing a mesh: the same pos / rot / scale the game applies to a flexbody

local function num(v, fallback)
  v = tonumber(v)
  return v or fallback
end

-- 3x4 matrices as flat arrays, row by row
local function mul(a, b)
  local m = {}
  for r = 0, 2 do
    for c = 0, 3 do
      local v = a[r * 4 + 1] * b[c + 1] + a[r * 4 + 2] * b[4 + c + 1] + a[r * 4 + 3] * b[8 + c + 1]
      if c == 3 then v = v + a[r * 4 + 4] end
      m[r * 4 + c + 1] = v
    end
  end
  return m
end

local function placement(row)
  local pos, rot, scale = row.pos or {}, row.rot or {}, row.scale or {}
  local rx, ry, rz = math.rad(num(rot.x, 0)), math.rad(num(rot.y, 0)), math.rad(num(rot.z, 0))
  local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
  local Rz = { cz, -sz, 0, 0, sz, cz, 0, 0, 0, 0, 1, 0 }
  local Rx = { 1, 0, 0, 0, 0, cx, -sx, 0, 0, sx, cx, 0 }
  local Ry = { cy, 0, sy, 0, 0, 1, 0, 0, -sy, 0, cy, 0 }
  local m = mul(mul(Rz, Rx), Ry)                 -- the game turns about Z, then X, then Y
  local kx, ky, kz = num(scale.x, 1), num(scale.y, 1), num(scale.z, 1)
  m[1], m[5], m[9] = m[1] * kx, m[5] * kx, m[9] * kx
  m[2], m[6], m[10] = m[2] * ky, m[6] * ky, m[10] * ky
  m[3], m[7], m[11] = m[3] * kz, m[7] * kz, m[11] * kz
  m[4], m[8], m[12] = num(pos.x, 0), num(pos.y, 0), num(pos.z, 0)
  return m
end

local function parseMatrix(text)
  if not text then return nil end
  local m = {}
  for value in text:gmatch('%S+') do m[#m + 1] = tonumber(value) end
  if #m ~= 16 then return nil end
  return m
end

-- positions of a geometry (a sample of them), moved by m, appended to out as x, y, z, ...
local function readVertices(block, m, out)
  local _, fa = block:find('<float_array[^>]*>')
  if not fa then return end
  local faEnd = block:find('</float_array>', fa, true)
  if not faEnd then return end
  local count = tonumber(block:sub(1, fa):match('<float_array[^>]-count="(%d+)"')) or 0
  local step = math.max(1, math.floor(count / 3 / MAX_PICK_VERTS))
  local n, x, y, v = 0, 0, 0, 0
  for value in block:sub(fa + 1, faEnd - 1):gmatch('%S+') do
    n = n + 1
    local k = n % 3
    if k == 1 then x = tonumber(value) or 0
    elseif k == 2 then y = tonumber(value) or 0
    else
      if v % step == 0 then
        local z = tonumber(value) or 0
        local i = #out
        out[i + 1] = m[1] * x + m[2] * y + m[3] * z + m[4]
        out[i + 2] = m[5] * x + m[6] * y + m[7] * z + m[8]
        out[i + 3] = m[9] * x + m[10] * y + m[11] * z + m[12]
      end
      v = v + 1
    end
  end
end

----------------------------------------------------------------------------------------------
-- writing a part's own .dae

local function safeName(text)
  return (tostring(text):gsub('[^%w_%-]', '_'))
end

local function shapePath(model, key)
  -- long keys (whole slot paths) are shortened; the hash keeps them apart
  local name = safeName(key)
  if #name > 80 then name = name:sub(-80) end
  return SHAPE_DIR .. safeName(model) .. '/v' .. VERSION .. '_' .. (skin and (safeName(skin) .. '_') or '') .. name .. '_' .. (tostring(stringHash(key)):gsub('[^%w]', '')) .. '.dae'
end

-- rows: { { mesh, pos, rot, scale, origin = part name the mesh comes from }, ... }
-- Returns { path = ..., verts = { x, y, z, ... } } (verts only when wantVerts) or false.
local function build(model, key, rows, wantVerts)
  local path = shapePath(model, key)
  local have = FS:fileExists(path)
  if have and not wantVerts then return { path = path } end
  if #rows == 0 then return false end

  local geometries, nodes, materials, seenGeom, seenMat = {}, {}, {}, {}, {}
  local verts = wantVerts and {} or nil
  local asset
  for i, row in ipairs(rows) do
    local _, sourceFile = resolvePart(row.origin)
    local file, node = findMesh(row.mesh, sourceFile)
    local start = file and file.content and file.geomAt[node.geom]
    if start then
      local _, stop = file.content:find('</geometry>', start, true)
      if stop then
        local block = file.content:sub(start, stop)
        asset = asset or file.asset
        local m = placement(row)
        local own = parseMatrix(node.matrix)
        if own then m = mul(m, own) end
        if verts then readVertices(block, m, verts) end
        if not have then
          if not seenGeom[node.geom] then
            seenGeom[node.geom] = true
            geometries[#geometries + 1] = block
          end
          local binds = {}
          for symbol in block:gmatch('material="([^"]+)"') do
            if not binds[symbol] then
              binds[symbol] = true
              binds[#binds + 1] = string.format('<instance_material symbol="%s" target="#%s"/>', symbol, symbol)
              if not seenMat[symbol] then
                seenMat[symbol] = true
                materials[#materials + 1] = symbol
              end
            end
          end
          -- node names are our own: the game reads a number at the end of a name as a detail level
          local id = 'slrrpart_' .. string.char(96 + ((i - 1) % 26) + 1) .. string.char(97 + math.floor((i - 1) / 26))
          nodes[#nodes + 1] = string.format(
            '<node id="%s" name="%s" type="NODE"><matrix>%s 0 0 0 1</matrix>' ..
            '<instance_geometry url="#%s" name="%s"><bind_material><technique_common>%s</technique_common></bind_material></instance_geometry></node>',
            id, id, table.concat(m, ' '), node.geom, id, table.concat(binds))
        end
      end
    end
  end
  if have then return { path = path, verts = verts } end
  if #nodes == 0 then return false end

  local effects, mats = {}, {}
  for _, symbol in ipairs(materials) do
    local name = symbol:gsub('%-material$', '')
    -- a car in a livery uses that livery's version of the material, where there is one
    if skin and scenetree.findObject(name .. '.skin.' .. skin) then name = name .. '.skin.' .. skin end
    effects[#effects + 1] = string.format('<effect id="%s-fx"><profile_COMMON><technique sid="common"><phong><diffuse><color>1 1 1 1</color></diffuse></phong></technique></profile_COMMON></effect>', symbol)
    mats[#mats + 1] = string.format('<material id="%s" name="%s"><instance_effect url="#%s-fx"/></material>', symbol, name, symbol)
  end
  local text = table.concat({
    '<?xml version="1.0" encoding="utf-8"?>',
    '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">',
    asset or '<asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>',
    '<library_effects>', table.concat(effects, '\n'), '</library_effects>',
    '<library_materials>', table.concat(mats, '\n'), '</library_materials>',
    '<library_geometries>', table.concat(geometries, '\n'), '</library_geometries>',
    '<library_visual_scenes><visual_scene id="Scene" name="Scene">', table.concat(nodes, '\n'), '</visual_scene></library_visual_scenes>',
    '<scene><instance_visual_scene url="#Scene"/></scene>',
    '</COLLADA>',
  }, '\n')
  if not writeFile(path, text) then return false end
  return { path = path, verts = verts }
end

----------------------------------------------------------------------------------------------
-- public

function M.setup(resolver, _skin)
  resolvePart = resolver
  if _skin ~= skin then cache = {} end
  skin = _skin
end

-- A part's own model: { path, verts } or false when there is nothing to show.
--   key   names the result (a part name, or a slot path + part for a part placed on the car)
--   rows  the meshes and where they go, see rowsOfPart
--   wantVerts  also return a sample of the vertex positions, for picking with the mouse
function M.get(model, key, rows, wantVerts)
  local id = model .. '|' .. key
  local hit = cache[id]
  if hit ~= nil and (hit == false or not wantVerts or hit.verts) then return hit end
  local ok, res = pcall(build, model, key, rows, wantVerts)
  if not ok then
    log('W', 'slrr_garage', 'model for ' .. tostring(key) .. ' failed: ' .. tostring(res))
    res = false
  end
  cache[id] = res
  return res
end

-- a part on its own, as the catalog and the shelf show it
function M.ofPart(model, partName)
  local id = model .. '|' .. partName
  if cache[id] ~= nil then return cache[id] end
  return M.get(model, partName, M.rowsOfPart(partName), false)
end

-- drop the big files from memory (the garage closed)
function M.release()
  for _, file in pairs(openFiles) do file.content = nil end
  openFiles, openOrder = {}, {}
end

return M
