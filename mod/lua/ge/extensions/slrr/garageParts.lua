-- SLRR Garage: the parts on the car, the parts on the shelf, and the catalog.
--
-- Two part trees are kept apart on purpose:
--   * the LOADED tree is what the game really spawned (physics, meshes) - changing it costs a
--     full vehicle respawn, the usual one-second BeamNG hitch.
--   * the DESIRED tree is what the player sees in the garage.
-- Taking a part off or bolting it back on only edits the desired tree and flips mesh visibility,
-- which is instant. The loaded tree catches up in one go at moments the player cannot see.

local M = {}

local jbeamIO = require('jbeam/io')
local jbeamLoader = require('jbeam/loader')
local catalogDef = require('slrr/garageCatalog')
local settings = require('slrr/garageSettings')
local damage = require('slrr/garageDamage')

local SAVE_FILE = '/settings/slrr_garage/save.json'

local vehId, model
local desired            -- desired parts tree (root node)
local slotIndex = {}     -- slot path -> desired node
local partIndex = {}     -- part path -> desired node
local loadedMeshes = {}  -- part path -> { meshName, ... }  (everything the spawned vehicle can show)
local loadedParts = {}   -- part path -> true for every part in the loaded tree
local loadedTree         -- the parts tree the game really spawned
local entryTree          -- the desired tree as it was when the car rolled in
local pendingExtras      -- hidden extra meshes to add to the next spawn of our vehicle (see collectExtras)
local injectedPaths = {} -- part path -> true for parts that are loaded only as hidden extra meshes
local headlessLoad = false
local entrySnapshot       -- shelf and money as they were on the way in, for undoing an interrupted visit
local meshAlpha = {}     -- mesh name -> alpha we last set
local chassisPath        -- part path that carries the ref nodes; never removable
local sectionFilter = {} -- section id -> true when hidden from view (SLRR's engine/body/running gear toggles)
local highlightPath, highlightPhase = nil, 0
local desiredVars, entryVars       -- tuning variables the player wants / came in with
local desiredPaints, entryPaints   -- paint slots the player wants / came in with
local visitNet = 0                 -- money spent minus money earned during this visit (career refunds on undo)

local save = { inventory = {}, nextId = 1 }
local partInfoCache = {}
local slotInfoCache = {}

----------------------------------------------------------------------------------------------
-- persistence

local function loadSave()
  local data = jsonReadFile(SAVE_FILE)
  if type(data) == 'table' then
    save.inventory = type(data.inventory) == 'table' and data.inventory or {}
    save.nextId = tonumber(data.nextId) or 1
  end
end

local function writeSave()
  jsonWriteFile(SAVE_FILE, save, true)
end

local function inventory()
  if not model then return {} end
  local inv = save.inventory[model]
  if type(inv) ~= 'table' then
    inv = {}
    save.inventory[model] = inv
  end
  return inv
end

----------------------------------------------------------------------------------------------
-- money: career money in career mode, a fixed budget everywhere else

local function inCareer()
  return career_career ~= nil and career_career.isActive ~= nil and career_career.isActive() and career_modules_playerAttributes ~= nil
end

function M.inCareer() return inCareer() end

function M.getMoney()
  if inCareer() then return career_modules_playerAttributes.getAttributeValue('money') or 0 end
  return settings.get('freeroamMoney')
end

-- catalog price of something worth `value` in the game's own part data
local function priced(value)
  return math.floor((value or 0) * settings.get('priceMultiplier') + 0.5)
end

local function spend(amount, label)
  if amount <= 0 then return true end
  if M.getMoney() < amount then return false end
  if inCareer() then
    local ok = career_modules_payment.pay({ money = { amount = amount } }, { label = label, tags = { 'buying', 'slrrGarage' } })
    if not ok then return false end
  end
  visitNet = visitNet + amount
  return true
end

local function earn(amount, label)
  if amount <= 0 then return end
  if inCareer() then
    career_modules_playerAttributes.addAttributes({ money = amount }, { label = label, tags = { 'selling', 'slrrGarage' } })
  end
  visitNet = visitNet - amount
end

----------------------------------------------------------------------------------------------
-- jbeam lookups

local function vehData()
  return vehId and core_vehicle_manager.getVehicleData(vehId)
end

local function getPart(partName)
  local vd = vehData()
  if not vd or not partName or partName == '' then return nil end
  local ok, part = pcall(jbeamIO.getPart, vd.ioCtx, partName)
  if not ok or not part then
    -- the io context drops its caches after a spawn; listing the parts refills them
    pcall(jbeamIO.getAvailableParts, vd.ioCtx)
    ok, part = pcall(jbeamIO.getPart, vd.ioCtx, partName)
  end
  return ok and part or nil
end

-- part table and the jbeam file it comes from (the 3D previews look for meshes next to it)
function M.resolvePart(partName)
  local vd = vehData()
  if not vd or not partName or partName == '' then return nil end
  local ok, part, filename = pcall(jbeamIO.getPart, vd.ioCtx, partName)
  if not ok or not part then
    pcall(jbeamIO.getAvailableParts, vd.ioCtx)
    ok, part, filename = pcall(jbeamIO.getPart, vd.ioCtx, partName)
  end
  if ok and part then return part, filename end
end

local function prettify(id)
  local s = tostring(id):gsub('_', ' ')
  return (s:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

local function partInfo(partName)
  local info = partInfoCache[partName]
  if info then return info end
  local part = getPart(partName)
  local raw = part and part.information or {}
  info = {
    name = type(raw.name) == 'string' and raw.name or prettify(partName),
    value = tonumber(raw.value) or 0,
    slots = {},
  }
  if part and type(part.slots2) == 'table' then
    for _, slot in ipairs(part.slots2) do
      if type(slot) == 'table' and slot.name then
        info.slots[slot.name] = { description = slot.description, coreSlot = slot.coreSlot == true }
      end
    end
  end
  partInfoCache[partName] = info
  return info
end

-- description / coreSlot flag of the slot a desired node sits in (defined by the parent part)
local function slotInfo(node, parentNode)
  local key = node.path
  local cached = slotInfoCache[key]
  if cached and cached.parentPart == (parentNode and parentNode.chosenPartName) then return cached end
  local res = { description = prettify(node.id), coreSlot = false, parentPart = parentNode and parentNode.chosenPartName }
  if parentNode and parentNode.chosenPartName and parentNode.chosenPartName ~= '' then
    local def = partInfo(parentNode.chosenPartName).slots[node.id]
    if def then
      res.description = def.description or res.description
      res.coreSlot = def.coreSlot
    end
  end
  slotInfoCache[key] = res
  return res
end

----------------------------------------------------------------------------------------------
-- tree helpers

local function isChosen(node)
  return node.chosenPartName ~= nil and node.chosenPartName ~= ''
end

local function walk(node, fn, parent)
  fn(node, parent)
  if node.children and isChosen(node) then
    for _, child in pairs(node.children) do walk(child, fn, node) end
  end
end

local parentOf = {}

local function reindex()
  slotIndex, partIndex, parentOf = {}, {}, {}
  if not desired then return end
  walk(desired, function(node, parent)
    if node.path then slotIndex[node.path] = node end
    parentOf[node] = parent
    if isChosen(node) then
      node.partPath = (node.path or '/') .. node.chosenPartName
      partIndex[node.partPath] = node
    end
  end)
end

local function subtreePartPaths(node, out)
  out = out or {}
  walk(node, function(n) if isChosen(n) then out[#out + 1] = (n.path or '/') .. n.chosenPartName end end)
  return out
end

local function countParts(node)
  local n = 0
  walk(node, function(x) if isChosen(x) then n = n + 1 end end)
  return n
end

local function subtreeValue(node)
  local v = 0
  walk(node, function(x) if isChosen(x) then v = v + partInfo(x.chosenPartName).value end end)
  return v
end

local function sectionOf(node)
  local desc = slotInfoCache[node.path] and slotInfoCache[node.path].description
  return catalogDef.classify(node.id or '', node.chosenPartName, desc)
end

----------------------------------------------------------------------------------------------
-- mesh visibility

local function setAlpha(veh, mesh, alpha)
  if meshAlpha[mesh] == alpha then return end
  meshAlpha[mesh] = alpha
  veh:setMeshAlpha(alpha, mesh, false)
end

-- make the car look like the desired tree
local function applyVisibility()
  local veh = vehId and getObjectByID(vehId)
  if not veh then return end
  for partPath, meshes in pairs(loadedMeshes) do
    local node = partIndex[partPath]
    local alpha = 0
    if node then
      alpha = 1
      if next(sectionFilter) and sectionFilter[(sectionOf(node))] then alpha = 0 end
    end
    for i = 1, #meshes do setAlpha(veh, meshes[i], alpha) end
  end
end

function M.isMeshHidden(mesh)
  local a = meshAlpha[mesh]
  return a ~= nil and a <= 0.01
end

-- pulse the part under the cursor so it is obvious what a click would take off
function M.setHighlight(partPath)
  if partPath == highlightPath then return end
  local veh = vehId and getObjectByID(vehId)
  if veh and highlightPath then
    local node = partIndex[highlightPath]
    if node then
      for _, p in ipairs(subtreePartPaths(node)) do
        for _, mesh in ipairs(loadedMeshes[p] or {}) do
          if meshAlpha[mesh] and meshAlpha[mesh] > 0.01 then setAlpha(veh, mesh, 1) end
        end
      end
    end
  end
  highlightPath = partPath
  highlightPhase = 0
end

function M.updateHighlight(dt)
  if not highlightPath then return end
  local veh = vehId and getObjectByID(vehId)
  local node = partIndex[highlightPath]
  if not veh or not node then highlightPath = nil return end
  highlightPhase = highlightPhase + dt * 5
  local alpha = 0.78 + 0.14 * math.sin(highlightPhase)
  for _, p in ipairs(subtreePartPaths(node)) do
    for _, mesh in ipairs(loadedMeshes[p] or {}) do
      if meshAlpha[mesh] and meshAlpha[mesh] > 0.01 then
        meshAlpha[mesh] = alpha
        veh:setMeshAlpha(alpha, mesh, false)
      end
    end
  end
end

----------------------------------------------------------------------------------------------
-- attaching to a spawned vehicle

local function readLoaded()
  loadedMeshes, loadedParts, meshAlpha = {}, {}, {}
  local vd = vehData()
  if not vd then return end
  local function add(partPath, mesh)
    if not partPath or not mesh or mesh == '' or mesh == 'SPOTLIGHT' or mesh == 'POINTLIGHT' then return end
    local list = loadedMeshes[partPath]
    if not list then list = {}; loadedMeshes[partPath] = list end
    list[#list + 1] = mesh
  end
  for _, fb in pairs(vd.vdata.flexbodies or {}) do
    if fb.meshLoaded then add(fb.partPath, fb.mesh) end
  end
  for _, prop in pairs(vd.vdata.props or {}) do
    if prop.pid then add(prop.partPath, prop.mesh) end
  end
  loadedTree = deepcopy(vd.config.partsTree or {})
  walk(loadedTree, function(node)
    if isChosen(node) then loadedParts[(node.path or '/') .. node.chosenPartName] = true end
  end)
  for partPath in pairs(injectedPaths) do loadedParts[partPath] = true end
  local rn = vd.vdata.refNodes and vd.vdata.refNodes[0]
  chassisPath = rn and rn.partPath or nil
end

-- Take over a vehicle. keepDesired: the vehicle was respawned by us, the desired tree stays.
function M.attach(id, keepDesired)
  vehId = id
  local veh = getObjectByID(id)
  local vd = vehData()
  if not veh or not vd then return false end
  local newModel = veh:getJBeamFilename()
  if newModel ~= model then
    partInfoCache, slotInfoCache = {}, {}
    keepDesired = false
  end
  model = newModel
  readLoaded()
  if not keepDesired or not desired then
    desired = deepcopy(vd.config.partsTree or {})
    entryTree = deepcopy(desired)
    entrySnapshot = { inventory = deepcopy(inventory()), nextId = save.nextId }
    sectionFilter = {}
    desiredVars = deepcopy(vd.config.vars or {})
    entryVars = deepcopy(desiredVars)
    desiredPaints = deepcopy(vd.config.paints or {})
    entryPaints = deepcopy(desiredPaints)
    visitNet = 0
  end
  highlightPath = nil
  reindex()
  walk(desired, function(node, parent) slotInfo(node, parent) end)
  -- a freshly bought part does not know which sub-parts it comes with until the game has
  -- loaded it once; copy that from the spawned tree so fitting it shows all of them
  for _, item in ipairs(inventory()) do
    if not item.tree.children then
      local node
      walk(loadedTree, function(n) if n.path == item.slotPath and n.chosenPartName == item.part then node = n end end)
      if node and node.children then
        item.tree = deepcopy(node)
        item.count = countParts(node)
      end
    end
  end
  applyVisibility()
  return true
end

function M.detach()
  local veh = vehId and getObjectByID(vehId)
  if veh then veh:setMeshAlpha(1, '', false) end
  vehId, desired, highlightPath, loadedTree, entryTree = nil, nil, nil, nil, nil
  pendingExtras, injectedPaths, entrySnapshot = nil, {}, nil
  desiredVars, entryVars, desiredPaints, entryPaints = nil, nil, nil, nil
  slotIndex, partIndex, loadedMeshes, loadedParts, meshAlpha = {}, {}, {}, {}, {}
end

function M.getVehicleId() return vehId end
function M.getModel() return model end

----------------------------------------------------------------------------------------------
-- describing parts

function M.describe(partPath)
  local node = partIndex[partPath]
  if not node then return nil end
  local info = partInfo(node.chosenPartName)
  local sInfo = slotInfo(node, parentOf[node])
  local count = countParts(node)
  local removable = parentOf[node] ~= nil and partPath ~= chassisPath and not sInfo.coreSlot
  local reason
  if not parentOf[node] or partPath == chassisPath then reason = "The chassis stays on the lift."
  elseif sInfo.coreSlot then reason = "This part can only be swapped, not removed." end
  local value = priced(subtreeValue(node))
  local damaged = damage.countPart(node.path) > 0
  return {
    partPath = partPath, partName = node.chosenPartName, name = info.name, slot = sInfo.description,
    value = value, complex = count > 1, count = count, removable = removable, reason = reason,
    section = (sectionOf(node)), damaged = damaged,
    repairCost = damaged and math.floor(value * settings.get('repairFactor') + 0.5) or 0,
  }
end

-- the part path of whatever is fitted in a slot (nil when the slot is empty or gone)
function M.partPathAtSlot(slotPath)
  local node = slotIndex[slotPath]
  return node and isChosen(node) and node.partPath or nil
end

function M.getSlotPath(partPath)
  local node = partIndex[partPath]
  return node and node.path or nil
end

-- climb from a picked part to the nearest ancestor that can actually be taken off
function M.removableAncestor(partPath)
  local node = partIndex[partPath]
  while node do
    local d = M.describe(node.partPath)
    if d and d.removable then return node.partPath end
    node = parentOf[node]
  end
  return nil
end

function M.getPartMeshes(partPath)
  local set = {}
  local node = partIndex[partPath]
  if not node then return set end
  for _, p in ipairs(subtreePartPaths(node)) do
    for _, mesh in ipairs(loadedMeshes[p] or {}) do set[mesh] = true end
  end
  return set
end

----------------------------------------------------------------------------------------------
-- inventory

local function newItem(node, slotDescription)
  local info = partInfo(node.chosenPartName)
  local section, sub = catalogDef.classify(node.id or '', node.chosenPartName, slotDescription)
  local item = {
    id = save.nextId,
    part = node.chosenPartName,
    name = info.name,
    slotId = node.id,
    slotPath = node.path,
    slot = slotDescription or prettify(node.id),
    section = section, sub = sub,
    value = subtreeValue(node),
    count = countParts(node),
    tree = deepcopy(node),
  }
  save.nextId = save.nextId + 1
  return item
end

local function findItem(itemId)
  local inv = inventory()
  for i, item in ipairs(inv) do
    if item.id == itemId then return item, i end
  end
end

-- take a part (and everything bolted to it) off the car and put it on the shelf
function M.removePart(partPath)
  local d = M.describe(partPath)
  if not d then return nil, "Nothing there." end
  if not d.removable then return nil, d.reason end
  local node = partIndex[partPath]
  local item = newItem(node, d.slot)
  item.damage = damage.takePart(node.path)
  table.insert(inventory(), item)
  node.chosenPartName = ''
  node.partPath = nil
  node.children = nil
  node.decisionMethod = 'user-empty'
  if highlightPath then M.setHighlight(nil) end
  reindex()
  applyVisibility()
  writeSave()
  return item
end

local function fits(slotNode, partName)
  for _, name in ipairs(slotNode.suitablePartNames or {}) do
    if name == partName then return true end
  end
  return false
end

-- where would this shelf item go? its old slot if that is free, else any free slot that takes it,
-- else its old slot (the part sitting there gets swapped out)
local function findTargetSlot(item)
  local home = slotIndex[item.slotPath]
  if home and not isChosen(home) and fits(home, item.part) then return home end
  local best
  for path, node in pairs(slotIndex) do
    if not isChosen(node) and node.id == item.slotId and fits(node, item.part) then
      if not best or path < best.path then best = node end
    end
  end
  if best then return best end
  if home and fits(home, item.part) then return home end
  for path, node in pairs(slotIndex) do
    if node.id == item.slotId and fits(node, item.part) then
      if not best or path < best.path then best = node end
    end
  end
  return best
end

-- retarget a saved subtree to live under another slot path
local function rebase(node, newPath)
  node.path = newPath
  if isChosen(node) then node.partPath = newPath .. node.chosenPartName end
  for _, child in pairs(node.children or {}) do
    rebase(child, newPath .. (child.id or '') .. '/')
  end
end

-- Bolt a shelf item onto the car. Returns ok, message, needsLoad
--   needsLoad: the game has not got these meshes in memory, the caller must respawn.
function M.installItem(itemId)
  local item, idx = findItem(itemId)
  if not item then return false, "That part is gone." end
  local slot = findTargetSlot(item)
  if not slot then return false, "Nothing on the car to bolt the " .. item.name .. " to. Fit the part it attaches to first." end
  if isChosen(slot) then
    local d = M.describe(slot.partPath)
    if slot.partPath == chassisPath then return false, "The chassis cannot be swapped here." end
    -- swap: the old part goes to the shelf
    local old = newItem(slot, d and d.slot)
    old.damage = damage.takePart(slot.path)
    table.insert(inventory(), old)
  end
  -- its dents come back with it (only where it sat before; the records are tied to that spot)
  if item.damage and slot.path == item.slotPath then damage.addPart(item.damage) end
  local tree = deepcopy(item.tree)
  rebase(tree, slot.path)
  slot.chosenPartName = tree.chosenPartName
  slot.partPath = tree.partPath
  slot.children = tree.children
  slot.decisionMethod = 'user'
  table.remove(inventory(), idx)
  reindex()
  walk(slot, function(node, parent) slotInfo(node, parent or parentOf[node]) end)
  applyVisibility()
  writeSave()
  return true, item.name, M.needsLoad()
end

-- true when the desired tree shows parts the spawned vehicle has no meshes for
function M.needsLoad()
  for partPath in pairs(partIndex) do
    if not loadedParts[partPath] then return true end
  end
  return false
end

-- true when the spawned vehicle differs from the desired tree in any way
function M.isDirty()
  if M.needsLoad() then return true end
  for partPath in pairs(loadedParts) do
    if not partIndex[partPath] then return true end
  end
  return M.varsDirty()
end

local function sameValues(a, b)
  for k, v in pairs(a or {}) do if (b or {})[k] ~= v then return false end end
  for k, v in pairs(b or {}) do if (a or {})[k] ~= v then return false end end
  return true
end

-- tuning changes only take effect when the car is rebuilt
function M.varsDirty()
  local vd = vehData()
  if not vd or not desiredVars then return false end
  -- the spawned config also lists every variable at its default; only ours matter here
  local loaded = vd.config.vars or {}
  for name, value in pairs(desiredVars) do
    local now = loaded[name]
    if type(now) ~= 'number' or type(value) ~= 'number' then
      if now ~= value then return true end
    elseif math.abs(now - value) > 1e-9 then
      return true
    end
  end
  return false
end

-- Put back, into a copy of the desired tree, every part that is loaded right now but that the
-- player has taken off. They stay invisible, but the game keeps their meshes (so refitting is
-- instant) and the car keeps a sane physical shape while it sits in the garage.
local function keepLoadedParts(dNode, lNode)
  if not lNode or not isChosen(lNode) or dNode.chosenPartName ~= lNode.chosenPartName then return end
  for slotId, lChild in pairs(lNode.children or {}) do
    local dChild = dNode.children and dNode.children[slotId]
    if dChild then
      if not isChosen(dChild) then
        if isChosen(lChild) then dNode.children[slotId] = deepcopy(lChild) end
      else
        keepLoadedParts(dChild, lChild)
      end
    end
  end
end

local function findSlot(tree, slotPath)
  local found
  walk(tree, function(node) if node.path == slotPath then found = node end end)
  return found
end

-- Also park shelf parts in their (empty) slots, hidden, so they can be fitted with no loading.
-- Returns the number of shelf parts newly staged this way.
local function stageShelfParts(tree)
  local staged = 0
  for _, item in ipairs(inventory()) do
    local slot = findSlot(tree, item.slotPath)
    if slot and not isChosen(slot) and fits(slot, item.part) then
      local sub = deepcopy(item.tree)
      rebase(sub, slot.path)
      slot.chosenPartName, slot.partPath, slot.children, slot.decisionMethod = sub.chosenPartName, sub.partPath, sub.children, 'user'
      if not loadedParts[sub.partPath] then staged = staged + 1 end
    end
  end
  return staged
end

-- Shelf parts whose slot is taken by another part cannot be staged in the real tree - a slot
-- holds one part. For those, load the car's jbeam once more off-screen with the shelf part
-- swapped in, lift the mesh definitions of that part out of the result, and hand them to the
-- real spawn as extra, hidden flexmeshes (bound to nodes the real car has). The part can then
-- be swapped in by flipping visibility, with no loading at all.
local function collectExtras(tree)
  local vd = vehData()
  if not vd then return nil end
  local wanted, taken = {}, {}
  for _, item in ipairs(inventory()) do
    local slot = findSlot(tree, item.slotPath)
    if slot and isChosen(slot) and slot.chosenPartName ~= item.part and fits(slot, item.part) and not taken[item.slotPath] then
      -- skip slots nested inside another slot we are already swapping
      local nested = false
      for other in pairs(taken) do
        if item.slotPath:sub(1, #other) == other or other:sub(1, #item.slotPath) == item.slotPath then nested = true end
      end
      if not nested then
        taken[item.slotPath] = true
        wanted[#wanted + 1] = item
      end
    end
  end
  if #wanted == 0 then return nil end

  local cfg = deepcopy(vd.config)
  cfg.partsTree = deepcopy(tree)
  for _, item in ipairs(wanted) do
    local slot = findSlot(cfg.partsTree, item.slotPath)
    local sub = deepcopy(item.tree)
    rebase(sub, slot.path)
    slot.chosenPartName, slot.partPath, slot.children, slot.decisionMethod = sub.chosenPartName, sub.partPath, sub.children, 'user'
  end

  local dirs = vd.directoriesLoaded or { vd.vehicleDirectory, '/vehicles/common/' }
  headlessLoad = true
  local ok, bundle = pcall(jbeamLoader.loadJbeam, -1, nil, dirs, cfg)
  headlessLoad = false
  if not ok or type(bundle) ~= 'table' or not bundle.vdata then
    log('W', 'slrr_garage', 'could not pre-load shelf parts: ' .. tostring(bundle))
    return nil
  end

  local extras = { flex = {}, paths = {}, keys = {} }
  local nodes = bundle.vdata.nodes or {}
  for _, item in ipairs(wanted) do
    local prefix = item.slotPath
    for _, fb in pairs(bundle.vdata.flexbodies or {}) do
      if type(fb.partPath) == 'string' and fb.partPath:sub(1, #prefix) == prefix and fb.mesh and fb._group_nodes then
        local names = {}
        for _, cid in ipairs(fb._group_nodes) do
          local node = nodes[cid]
          if node and node.name then names[#names + 1] = node.name end
        end
        local entry = deepcopy(fb)
        entry._group_nodes, entry.fid, entry.meshLoaded, entry.cid = nil, nil, nil, nil
        extras.flex[#extras.flex + 1] = { entry = entry, nodeNames = names, slotPath = prefix }
      end
    end
    local resolved = findSlot(bundle.config.partsTree or {}, item.slotPath)
    if resolved and resolved.chosenPartName == item.part then
      for _, partPath in ipairs(subtreePartPaths(resolved)) do extras.paths[partPath] = true end
      if not item.tree.children and resolved.children then
        item.tree = deepcopy(resolved)
        item.count = countParts(resolved)
      end
    end
    extras.keys[#extras.keys + 1] = item.slotPath .. item.part
  end
  table.sort(extras.keys)
  return extras
end

-- The game's electronic driver aids (ABS, traction and stability control) assume four wheels
-- and throw an error - "Error loading vehicle" - when a car is built without them. A car that
-- leaves the garage on its brake discs has no use for them anyway, so they are left out.
local function dropDriverAidsWithoutWheels(vehicle)
  local wheelCount = 0
  for _ in pairs(vehicle.wheels or {}) do wheelCount = wheelCount + 1 end
  if wheelCount >= 4 or type(vehicle.controller) ~= 'table' then return end
  local keys, hasAids = {}, false
  for key, ctrl in pairs(vehicle.controller) do
    if type(key) == 'number' then
      keys[#keys + 1] = key
      if type(ctrl) == 'table' and type(ctrl.fileName) == 'string' and ctrl.fileName:find('^drivingDynamics/') then hasAids = true end
    end
  end
  if not hasAids then return end
  table.sort(keys)
  local kept = {}
  for _, key in ipairs(keys) do
    local ctrl = vehicle.controller[key]
    if not (type(ctrl) == 'table' and type(ctrl.fileName) == 'string' and ctrl.fileName:find('^drivingDynamics/')) then
      kept[#kept + 1] = ctrl
    end
    vehicle.controller[key] = nil
  end
  local base = keys[1] or 0
  for i, ctrl in ipairs(kept) do vehicle.controller[base + i - 1] = ctrl end
  log('I', 'slrr_garage', string.format('vehicle has %d wheels: built without electronic driver aids', wheelCount))
end

-- jbeam loading hook (called by the game while it builds a vehicle): add the hidden extras
function M.onJbeamLoadingPhase2(objID, vehicle)
  if headlessLoad then return end
  local okAids, errAids = pcall(dropDriverAidsWithoutWheels, vehicle)
  if not okAids then log('W', 'slrr_garage', 'driver-aid check failed: ' .. tostring(errAids)) end
  if not pendingExtras or objID ~= vehId then return end
  local extras = pendingExtras
  pendingExtras = nil
  injectedPaths = {}
  local ok, err = pcall(function()
    local byName, bySlot = {}, {}
    for _, node in pairs(vehicle.nodes or {}) do
      if node.name and node.cid then byName[node.name] = node.cid end
    end
    local chassisNodes = {}
    local refPart = vehicle.refNodes and vehicle.refNodes[0] and vehicle.refNodes[0].partPath
    for _, node in pairs(vehicle.nodes or {}) do
      if node.cid and node.partPath == refPart and #chassisNodes < 160 then chassisNodes[#chassisNodes + 1] = node.cid end
    end
    local nextKey = 0
    for key in pairs(vehicle.flexbodies or {}) do
      if type(key) == 'number' and key >= nextKey then nextKey = key + 1 end
    end
    vehicle.flexbodies = vehicle.flexbodies or {}
    local added = 0
    for _, extra in ipairs(extras.flex) do
      -- bind the mesh to nodes this car really has: its own where they exist by name,
      -- otherwise those of the part sitting in its slot, otherwise the chassis
      local group = {}
      for _, name in ipairs(extra.nodeNames) do
        if byName[name] then group[#group + 1] = byName[name] end
      end
      if #group < 4 then
        local sub = bySlot[extra.slotPath]
        if not sub then
          sub = {}
          for _, node in pairs(vehicle.nodes or {}) do
            if node.cid and type(node.partPath) == 'string' and node.partPath:sub(1, #extra.slotPath) == extra.slotPath and #sub < 160 then
              sub[#sub + 1] = node.cid
            end
          end
          bySlot[extra.slotPath] = sub
        end
        group = #sub >= 4 and sub or chassisNodes
      end
      if #group >= 3 then
        local entry = deepcopy(extra.entry)
        entry._group_nodes = group
        entry.cid = nextKey
        entry.slrrExtra = true
        vehicle.flexbodies[nextKey] = entry
        nextKey = nextKey + 1
        added = added + 1
      end
    end
    if added > 0 then injectedPaths = extras.paths end
    log('I', 'slrr_garage', string.format('pre-loaded %d hidden meshes for %d shelf parts', added, #extras.keys))
  end)
  if not ok then log('E', 'slrr_garage', 'adding hidden shelf meshes failed: ' .. tostring(err)) end
end

-- Vehicle config for a respawn.
--   final = true : exactly what the player built (used when driving out)
--   final = false: the same car to look at, plus hidden extras (removed and shelf parts)
function M.buildConfig(final)
  local vd = vehData()
  if not vd or not desired then return nil end
  local config = deepcopy(vd.config)
  local tree = deepcopy(desired)
  pendingExtras = nil
  if not final then
    keepLoadedParts(tree, loadedTree)
    stageShelfParts(tree)
    pendingExtras = collectExtras(tree)
  end
  -- the game caches built vehicles per config; ours differ by the hidden extras, so start clean
  jbeamLoader.onFileChanged()
  config.partsTree = tree
  if desiredVars then config.vars = deepcopy(desiredVars) end
  if desiredPaints and #desiredPaints > 0 then config.paints = deepcopy(desiredPaints) end
  return config
end

function M.isHeadlessLoad() return headlessLoad end

-- forget cached vehicle builds that contain our hidden extras
function M.clearLoaderCache()
  jbeamLoader.onFileChanged()
end

-- how many shelf parts could be pre-loaded right now to make fitting them instant
function M.countStageable()
  if not desired then return 0 end
  local tree = deepcopy(desired)
  keepLoadedParts(tree, loadedTree)
  local n = stageShelfParts(tree)
  for _, item in ipairs(inventory()) do
    local slot = findSlot(tree, item.slotPath)
    if slot and isChosen(slot) and slot.chosenPartName ~= item.part and fits(slot, item.part) and not loadedParts[item.slotPath .. item.part] then
      n = n + 1
    end
  end
  return n
end

-- What is the car leaving without? Nothing stops you driving out stripped - this is only so
-- the garage can say so on the way out.
function M.missingEssentials()
  if not entryTree or not desired then return nil end
  local missing = {}
  walk(entryTree, function(node)
    if not isChosen(node) or not node.path then return end
    local section, sub = catalogDef.classify(node.id or '', node.chosenPartName)
    local kind
    if section == 'running' and (sub:find('^rims') or sub:find('^tyres')) then
      kind = 'wheels'
    elseif section == 'engine' and sub == 'blocks' and (node.id or ''):match('engine$') then
      kind = 'an engine'
    elseif section == 'engine' and sub == 'cooling' and (node.id or ''):find('radiator') then
      kind = 'a radiator'
    end
    if kind then
      local now = slotIndex[node.path]
      if now and not isChosen(now) then missing[kind] = true end
    end
  end)
  local list = tableKeysSorted(missing)
  if #list == 0 then return nil end
  return table.concat(list, ', ')
end

-- Undo the whole visit: shelf and money go back to how they were on the way in. Returns the
-- vehicle config to respawn with when the spawned car no longer matches how it came in.
function M.revertVisit()
  if not entrySnapshot or not model then return nil end
  if inCareer() and visitNet ~= 0 then
    career_modules_playerAttributes.addAttributes({ money = visitNet }, { label = 'Garage visit undone', tags = { 'slrrGarage' } })
  end
  visitNet = 0
  save.inventory[model] = deepcopy(entrySnapshot.inventory)
  save.nextId = math.max(save.nextId, entrySnapshot.nextId)
  writeSave()
  local vd = vehData()
  local changed = false
  if vd and entryTree and loadedTree then
    local was, now = {}, {}
    walk(entryTree, function(n) if isChosen(n) then was[(n.path or '/') .. n.chosenPartName] = true end end)
    walk(loadedTree, function(n) if isChosen(n) then now[(n.path or '/') .. n.chosenPartName] = true end end)
    for k in pairs(was) do if not now[k] then changed = true end end
    for k in pairs(now) do if not was[k] then changed = true end end
  end
  if not changed then return nil end
  pendingExtras = nil
  jbeamLoader.onFileChanged()
  local config = deepcopy(vd.config)
  config.partsTree = deepcopy(entryTree)
  if entryVars then config.vars = deepcopy(entryVars) end
  if entryPaints and #entryPaints > 0 then config.paints = deepcopy(entryPaints) end
  return config
end

local function itemPrice(item)
  return priced(item.value)
end

function M.sellValue(item)
  local value = itemPrice(item) * settings.get('sellFactor')
  if damage.count(item.damage) > 0 then value = value * 0.5 end   -- bent parts fetch half
  return math.floor(value + 0.5)
end

function M.sellItem(itemId)
  local item, idx = findItem(itemId)
  if not item then return false end
  local value = M.sellValue(item)
  earn(value, 'Sold ' .. item.name)
  table.remove(inventory(), idx)
  writeSave()
  return true, item, value
end

----------------------------------------------------------------------------------------------
-- repairs

local function repairPriceOf(value)
  return math.floor(priced(value) * settings.get('repairFactor') + 0.5)
end

-- repair a part that is on the car (and everything bolted to it)
function M.repairPart(partPath)
  local node = partIndex[partPath]
  if not node then return false, "Nothing there." end
  if damage.countPart(node.path) == 0 then return false, "That part is not damaged." end
  local cost = repairPriceOf(subtreeValue(node))
  if not spend(cost, 'Repaired ' .. partInfo(node.chosenPartName).name) then return false, "Not enough money for that repair." end
  damage.repairPart(node.path)
  return true, cost
end

function M.repairItem(itemId)
  local item = findItem(itemId)
  if not item then return false, "That part is gone." end
  if damage.count(item.damage) == 0 then return false, "That part is not damaged." end
  local cost = repairPriceOf(item.value)
  if not spend(cost, 'Repaired ' .. item.name) then return false, "Not enough money for that repair." end
  item.damage = nil
  writeSave()
  return true, cost
end

-- price of putting right everything that is on the car
function M.repairAllCost()
  local total = 0
  walk(desired or {}, function(node)
    if isChosen(node) and node.path and damage.countOwn(node.partPath) > 0 then
      total = total + repairPriceOf(partInfo(node.chosenPartName).value)
    end
  end)
  return total
end

function M.repairAll()
  if damage.countAll() == 0 then return false, "There is nothing to repair." end
  local cost = M.repairAllCost()
  if not spend(cost, 'Repaired the car') then return false, "Not enough money to repair the car." end
  damage.repairAll()
  return true, cost
end

-- damage of the shelf parts, for re-applying after a rebuild (they may be loaded, hidden)
function M.getShelfDamages()
  local list = {}
  for _, item in ipairs(inventory()) do
    if item.damage then list[#list + 1] = item.damage end
  end
  return list
end

----------------------------------------------------------------------------------------------
-- tuning (the screwdriver)

-- every adjustable setting the car has right now, grouped the way the game groups them
function M.getTuning()
  local vd = vehData()
  local list = {}
  if not vd then return list end
  for name, var in pairs(vd.vdata.variables or {}) do
    if type(var) == 'table' and var.type == 'range' and not var.hideInUI then
      local value = desiredVars and desiredVars[name]
      if value == nil then value = var.val end
      list[#list + 1] = {
        name = name, title = var.title or name, category = var.category or 'Other', subCategory = var.subCategory,
        description = var.description, unit = var.unit or '',
        min = var.min, max = var.max, step = var.step, value = value, default = var.default,
        minDis = var.minDis or var.min, maxDis = var.maxDis or var.max, stepDis = var.stepDis or var.step,
      }
    end
  end
  table.sort(list, function(a, b)
    if a.category ~= b.category then return a.category < b.category end
    if (a.subCategory or '') ~= (b.subCategory or '') then return (a.subCategory or '') < (b.subCategory or '') end
    return a.title < b.title
  end)
  return list
end

function M.setTuning(values)
  local vd = vehData()
  if not vd or not desiredVars or type(values) ~= 'table' then return false end
  local changed = false
  for name, value in pairs(values) do
    local var = (vd.vdata.variables or {})[name]
    value = tonumber(value)
    if var and value then
      value = clamp(value, math.min(var.min, var.max), math.max(var.min, var.max))
      if desiredVars[name] ~= value then
        desiredVars[name] = value
        changed = true
      end
    end
  end
  return changed
end

-- names of the tuning variables a part declares in its own jbeam
local function varsOfPart(partName)
  local names = {}
  local part = M.resolvePart(partName)
  for i, row in ipairs(part and type(part.variables) == 'table' and part.variables or {}) do
    if i > 1 and type(row) == 'table' and type(row[1]) == 'string' and row[1]:sub(1, 1) == '$' then names[row[1]] = true end
  end
  return names
end

-- The adjustments that belong to one part of the car: its own and those of what is bolted to
-- it. A part with none of its own (a rim, say) falls back to the part it is mounted on.
function M.getPartTuning(partPath)
  local node = partIndex[partPath]
  if not node then return nil end
  local all = {}
  for _, var in ipairs(M.getTuning()) do all[var.name] = var end
  local function collect(names)
    local list = {}
    for name in pairs(names) do
      if all[name] then list[#list + 1] = all[name] end
    end
    table.sort(list, function(a, b)
      if (a.subCategory or '') ~= (b.subCategory or '') then return (a.subCategory or '') < (b.subCategory or '') end
      return a.title < b.title
    end)
    return list
  end
  local names = {}
  walk(node, function(n)
    if isChosen(n) then
      for name in pairs(varsOfPart(n.chosenPartName)) do names[name] = true end
    end
  end)
  local list = collect(names)
  if #list > 0 then return { vars = list } end
  local cur, steps = parentOf[node], 0
  while cur and parentOf[cur] and steps < 2 do
    list = collect(varsOfPart(cur.chosenPartName))
    if #list > 0 then return { vars = list, owner = partInfo(cur.chosenPartName).name } end
    cur, steps = parentOf[cur], steps + 1
  end
  return { vars = {} }
end

-- which tuning group goes with a part of the car (clicking a part in tune mode jumps there)
function M.tuningCategoryFor(partPath)
  local node = partIndex[partPath]
  if not node then return nil end
  local section, sub = sectionOf(node)
  local text = ((node.id or '') .. ' ' .. (node.chosenPartName or '')):lower()
  local wanted = {}
  if text:find('wheel') or text:find('tire') or text:find('hub') then wanted = { 'wheel alignment', 'wheels', 'tires' }
  elseif sub:find('^shocks') or sub:find('^suspension') or sub == 'bars' then wanted = { 'suspension', 'wheel alignment' }
  elseif sub:find('^brakes') then wanted = { 'brakes' }
  elseif sub == 'transmission' or sub == 'clutch' then wanted = { 'transmission' }
  elseif sub == 'driveline' or sub == 'differentials' then wanted = { 'differentials', 'differential', 'transfer case' }
  elseif text:find('n2o') or text:find('nitrous') then wanted = { 'nitrous oxide' }
  elseif section == 'engine' then wanted = { 'engine', 'turbocharger', 'supercharger', 'nitrous oxide' }
  elseif sub:find('^lights') then wanted = { 'headlights' }
  elseif sub == 'aero' or sub == 'wings' then wanted = { 'aerodynamics', 'chassis' }
  else wanted = { 'chassis' } end
  local have = {}
  for _, var in ipairs(M.getTuning()) do have[var.category:lower()] = var.category end
  for _, name in ipairs(wanted) do
    if have[name] then return have[name] end
  end
  return nil
end

----------------------------------------------------------------------------------------------
-- paint

function M.getPaints()
  return desiredPaints or {}
end

-- respray one of the car's colour slots; returns ok, message
function M.setPaint(index, paint)
  if not desiredPaints or type(paint) ~= 'table' or type(paint.baseColor) ~= 'table' then return false, "No such paint." end
  index = tonumber(index)
  if not index or index < 1 or index > 3 then return false, "No such paint slot." end
  if not spend(settings.get('paintPrice'), 'Respray') then return false, "Not enough money for a respray." end
  for i = 1, index do
    if not desiredPaints[i] then
      desiredPaints[i] = deepcopy(desiredPaints[1] or paint)
    end
  end
  desiredPaints[index] = deepcopy(paint)
  return true
end

function M.paintsDirty()
  local vd = vehData()
  if not vd or not desiredPaints then return false end
  return serialize(desiredPaints) ~= serialize(vd.config.paints or {})
end

----------------------------------------------------------------------------------------------
-- car info

function M.getCarInfo()
  local info = { parts = 0, value = 0, damagedParts = 0, shelfParts = #inventory(), shelfValue = 0 }
  walk(desired or {}, function(node)
    if isChosen(node) then
      info.parts = info.parts + 1
      info.value = info.value + priced(partInfo(node.chosenPartName).value)
      if node.partPath and damage.countOwn(node.partPath) > 0 then info.damagedParts = info.damagedParts + 1 end
    end
  end)
  for _, item in ipairs(inventory()) do info.shelfValue = info.shelfValue + itemPrice(item) end
  info.repairCost = M.repairAllCost()
  info.missing = M.missingEssentials()
  return info
end

----------------------------------------------------------------------------------------------
-- section filters (hide whole groups to reach what is behind them)

function M.toggleSectionFilter(section)
  sectionFilter[section] = not sectionFilter[section] or nil
  applyVisibility()
  return sectionFilter[section] == true
end

function M.getSectionFilter() return sectionFilter end

----------------------------------------------------------------------------------------------
-- catalog

-- every part that fits a slot currently on the car, sorted into SLRR's sections
function M.buildCatalog()
  local bySub = {}
  if not desired then return bySub end
  local owned = {}
  for _, item in ipairs(inventory()) do owned[item.part] = (owned[item.part] or 0) + 1 end
  walk(desired, function(node, parent)
    if not parent then return end
    local sInfo = slotInfo(node, parent)
    for _, partName in ipairs(node.suitablePartNames or {}) do
      local info = partInfo(partName)
      local section, sub = catalogDef.classify(node.id or '', partName, sInfo.description)
      local key = section .. '/' .. sub
      local list = bySub[key]
      if not list then list = {}; bySub[key] = list end
      list[#list + 1] = {
        part = partName, name = info.name, price = priced(info.value),
        slotPath = node.path, slot = sInfo.description,
        fitted = node.chosenPartName == partName, owned = owned[partName] or 0,
      }
    end
  end)
  for _, list in pairs(bySub) do
    table.sort(list, function(a, b)
      if a.slot ~= b.slot then return a.slot < b.slot end
      if a.price ~= b.price then return a.price < b.price end
      return a.name < b.name
    end)
  end
  return bySub
end

function M.buy(slotPath, partName)
  local slot = slotIndex[slotPath]
  if not slot or not fits(slot, partName) then return false, "That part does not fit this car." end
  local info = partInfo(partName)
  if not spend(priced(info.value), 'Bought ' .. info.name) then return false, "Not enough money." end
  local sInfo = slotInfo(slot, parentOf[slot])
  local node = {
    id = slot.id, path = slot.path, chosenPartName = partName, partPath = slot.path .. partName,
    decisionMethod = 'user', suitablePartNames = slot.suitablePartNames, unsuitablePartNames = slot.unsuitablePartNames,
  }
  local item = newItem(node, sInfo.description)
  item.value = info.value
  item.new = true
  table.insert(inventory(), item)
  writeSave()
  return true, item
end

----------------------------------------------------------------------------------------------
-- state for the UI

function M.getInventory() return inventory() end
function M.itemPrice(item) return itemPrice(item) end
function M.itemDamaged(item) return damage.count(item.damage) > 0 end
function M.itemRepairCost(item) return damage.count(item.damage) > 0 and repairPriceOf(item.value) or 0 end
function M.getSections() return catalogDef.sections end

function M.onExtensionLoaded() end

loadSave()

return M
