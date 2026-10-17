-- Wrench Works: the parts on the car, the parts on the shelf, and the catalog.
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
local shapes = require('slrr/garageShapes')
local preview = require('slrr/garagePreview')
local picker = require('slrr/garagePicker')

local SAVE_FILE = '/settings/slrr_garage/save.json'

local vehId, model
local desired            -- desired parts tree (root node)
local slotIndex = {}     -- slot path -> desired node
local partIndex = {}     -- part path -> desired node
local loadedMeshes = {}  -- part path -> { meshName, ... }  (everything the spawned vehicle can show)
local loadedParts = {}   -- part path -> true for every part in the loaded tree
local loadedTree         -- the parts tree the game really spawned
local entryTree          -- the desired tree as it was when the car rolled in
local virtualParts = {}  -- part path -> true for parts shown as stand-in models (see loadStandins)
local loadStandins        -- defined further down
local headlessLoad = false
local entrySnapshot       -- shelf and money as they were on the way in, for undoing an interrupted visit
local meshAlpha = {}     -- mesh name -> alpha we last set
local chassisPath        -- part path that carries the ref nodes; never removable
local sectionFilter = {} -- section id -> true when hidden from view (SLRR's engine/body/running gear toggles)
local highlightPath, highlightPhase, highlightWait = nil, 0, 0
local desiredVars, entryVars       -- tuning variables the player wants / came in with
local desiredPaints, entryPaints   -- paint slots the player wants / came in with
local visitNet = 0                 -- money spent minus money earned during this visit (career refunds on undo)

local save = { inventory = {}, nextId = 1, orders = {} }
local cart = {}                    -- the shopping list: { slotPath, part } until the order is confirmed
local freightCache = {}
local yardStock                    -- at the used-parts yard: slotPath..part -> { discount, dent }
local deferStandins = false        -- several parts are being fitted in one go; work out the stand-ins once at the end
local partInfoCache = {}
local slotInfoCache = {}

----------------------------------------------------------------------------------------------
-- persistence

local function loadSave()
  -- with saving switched off every session starts from nothing
  if not settings.get('saveBetweenSessions') then return end
  local data = jsonReadFile(SAVE_FILE)
  if type(data) == 'table' then
    save.inventory = type(data.inventory) == 'table' and data.inventory or {}
    save.nextId = tonumber(data.nextId) or 1
    save.orders = type(data.orders) == 'table' and data.orders or {}
    save.wallet = tonumber(data.wallet)
    save.builds = type(data.builds) == 'table' and data.builds or nil
  end
end

local function writeSave()
  if not settings.get('saveBetweenSessions') then return end
  jsonWriteFile(SAVE_FILE, save, true)
end

-- saving was just switched on: what there is now is what is kept
function M.saveNow() writeSave() end

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
-- money: career money in career mode; elsewhere a wallet of its own that is spent and earned
-- like any other, unless the player has switched to unlimited money

-- Another mod can keep the money instead (Street Legal's career does):
-- { get = function() -> amount, add = function(amount, label) -> ok, walkIn = false to keep body shells off sale }
local provider

function M.setMoneyProvider(p) provider = type(p) == 'table' and type(p.get) == 'function' and type(p.add) == 'function' and p or nil end
function M.providerAllows(what) return not provider or provider[what] ~= false end
-- the car the provider's player walks into the garage with (car = function() -> vehicle or nil); second value: whether
-- a provider says anything at all
function M.providerCar()
  if not (provider and type(provider.car) == 'function') then return nil, false end
  return provider.car(), true
end

-- may this garage be used? A career's garage ladder says no to the ones above your level: true, or false and why
function M.providerGarage(siteId)
  if not (provider and type(provider.garageAccess) == 'function') then return true end
  return provider.garageAccess(siteId)
end
-- on foot in the doorway: the career shows its own garage panel (the cars: take out, store, despawn); true when it did
function M.providerPanel(siteId)
  return provider ~= nil and type(provider.panel) == 'function' and provider.panel(siteId) == true
end
-- on foot with the car stored: the career brings it out front (true when it has started to)
function M.providerFetch()
  return provider ~= nil and type(provider.fetch) == 'function' and provider.fetch() == true
end

local function inCareer()
  return career_career ~= nil and career_career.isActive ~= nil and career_career.isActive() and career_modules_playerAttributes ~= nil
end

function M.inCareer() return inCareer() end

local function unlimited()
  return not provider and not inCareer() and settings.get('unlimitedMoney')
end

function M.isUnlimited() return unlimited() end

local function wallet()
  if type(save.wallet) ~= 'number' then save.wallet = settings.get('freeroamMoney') end
  return save.wallet
end

function M.getMoney()
  if provider then return provider.get() or 0 end
  if inCareer() then return career_modules_playerAttributes.getAttributeValue('money') or 0 end
  if unlimited() then return 999999999 end
  return wallet()
end

-- put the freeroam wallet at a set amount (the "freeroam money" setting was changed)
function M.setWallet(amount)
  save.wallet = math.max(0, tonumber(amount) or 0)
  writeSave()
end

-- catalog price of something worth `value` in the game's own part data
local counterDiscount = 0    -- share taken off prices while buying over the counter in a shop

function M.setCounterDiscount(fraction) counterDiscount = clamp(tonumber(fraction) or 0, 0, 0.9) end

-- what this garage has (another mod's career sells these as upgrades; on their own everything is there):
-- lift (engine, gearbox, suspension, driveline, headers), workbench (repairs at the normal price), dyno, paint,
-- photo, shelfSize (parts per model), repairFactor
local ALL = { lift = true, workbench = true, dyno = true, paint = true, photo = true, shelfSize = math.huge, repairFactor = 1 }
local features = deepcopy(ALL)
local atShop = false            -- a shop fits anything: it has its own lift
function M.setFeatures(f)
  features = deepcopy(ALL)
  for k, v in pairs(type(f) == 'table' and f or {}) do if features[k] ~= nil then features[k] = v end end
end
function M.getFeatures() return features end
function M.setAtShop(on) atShop = on == true end

-- parts that need the car up: by the slot's own name (bolt-ons - intake, the exhaust from the cat back, ECU,
-- wheels, tyres, filters - go on from the floor)
local LIFT_WORDS = { 'internals', 'transmission', 'gearbox', 'clutch', 'flywheel', 'suspension', 'subframe', 'strut', 'swaybar',
  'differential', 'driveshaft', 'halfshaft', 'manifold', 'header', 'oilpan' }
function M.needsLift(slotPath)
  local seg = tostring(slotPath or ''):gsub('/$', ''):match('([^/]+)$') or ''
  seg = seg:lower()
  if seg:match('engine$') then return true end
  for _, w in ipairs(LIFT_WORDS) do if seg:find(w, 1, true) then return true end end
  return false
end

local function priced(value)
  return math.floor((value or 0) * settings.get('priceMultiplier') * (1 - counterDiscount) + 0.5)
end

local function spend(amount, label)
  if amount <= 0 then return true end
  if M.getMoney() < amount then return false end
  if provider then
    if not provider.add(-amount, label) then return false end
  elseif inCareer() then
    local ok = career_modules_payment.pay({ money = { amount = amount } }, { label = label, tags = { 'buying', 'slrrGarage' } })
    if not ok then return false end
  elseif not unlimited() then
    save.wallet = wallet() - amount
  end
  visitNet = visitNet + amount
  return true
end

local function earn(amount, label)
  if amount <= 0 then return end
  if provider then
    provider.add(amount, label)
  elseif inCareer() then
    career_modules_playerAttributes.addAttributes({ money = amount }, { label = label, tags = { 'selling', 'slrrGarage' } })
  elseif not unlimited() then
    save.wallet = wallet() + amount
  end
  visitNet = visitNet - amount
end

-- pay for something that is not a part (a body shell); counts towards this visit. Returns ok.
function M.pay(amount, label) return spend(amount, label) end

-- money won or lost outside the garage (street races): not part of a garage visit, saved at once.
-- amount > 0 is paid in, amount < 0 taken out; returns false if the player cannot cover a loss.
function M.changeMoney(amount, label)
  amount = math.floor(tonumber(amount) or 0)
  if amount == 0 or unlimited() then return true end
  if amount < 0 and M.getMoney() < -amount then return false end
  if provider then return provider.add(amount, label) ~= false end      -- the career keeps the money
  if inCareer() then
    if amount > 0 then
      career_modules_playerAttributes.addAttributes({ money = amount }, { label = label, tags = { 'gameplay', 'slrrRaces' } })
    else
      return career_modules_payment.pay({ money = { amount = -amount } }, { label = label, tags = { 'gameplay', 'slrrRaces' } })
    end
  else
    save.wallet = wallet() + amount
    writeSave()
  end
  return true
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
      -- some parts describe a slot with a table (translations); the id reads fine then
      if type(def.description) == 'string' and def.description ~= '' then res.description = def.description end
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
  if mesh:byte(1) == 64 then          -- "@...": a stand-in model, not a mesh of the vehicle
    preview.setStandinVisible(mesh, alpha > 0.01)
  else
    veh:setMeshAlpha(alpha, mesh, false)
  end
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
  highlightPhase, highlightWait = 0, 0
end

function M.updateHighlight(dt)
  if not highlightPath then return end
  local veh = vehId and getObjectByID(vehId)
  local node = partIndex[highlightPath]
  if not veh or not node then highlightPath = nil return end
  highlightPhase = highlightPhase + dt * 5
  -- the pulse is redrawn 30 times a second, not every frame: changing a mesh's alpha is not free,
  -- and a big part is a hundred meshes
  highlightWait = highlightWait - dt
  if highlightWait > 0 then return end
  highlightWait = 0.033
  local alpha = 0.78 + 0.14 * math.sin(highlightPhase)
  for _, p in ipairs(subtreePartPaths(node)) do
    for _, mesh in ipairs(loadedMeshes[p] or {}) do
      if meshAlpha[mesh] and meshAlpha[mesh] > 0.01 and mesh:byte(1) ~= 64 then
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
  -- whatever was standing in for a part is either really on the car now or gone
  virtualParts = {}
  preview.clearStandins()
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
  virtualParts, entrySnapshot = {}, nil
  preview.clearStandins()
  desiredVars, entryVars, desiredPaints, entryPaints = nil, nil, nil, nil
  slotIndex, partIndex, loadedMeshes, loadedParts, meshAlpha = {}, {}, {}, {}, {}
end

function M.getVehicleId() return vehId end

-- The car was bought as a bare body shell: everything that unbolts is gone - not to the shelf,
-- it was never paid for. What a slot cannot do without (its core parts) stays, and so does
-- whatever the shell itself hangs from. From here on this is how the car "came in".
function M.stripToShell()
  if not desired then return end
  local keep = {}
  local node = chassisPath and partIndex[chassisPath]
  while node do
    keep[node] = true
    node = parentOf[node]
  end
  local function strip(parent)
    for _, child in pairs(parent.children or {}) do
      if isChosen(child) then
        if keep[child] or slotInfo(child, parent).coreSlot then
          strip(child)          -- it stays, but what is bolted to it does not
        else
          child.chosenPartName, child.partPath, child.children, child.decisionMethod = '', nil, nil, 'user-empty'
        end
      end
    end
  end
  strip(desired)
  reindex()
  applyVisibility()
  entryTree = deepcopy(desired)
end

-- the livery the car wears (nil for plain paint)
function M.getSkin()
  local vd = vehData()
  for _, fb in pairs(vd and vd.vdata.flexbodies or {}) do
    if type(fb.globalSkin) == 'string' and fb.globalSkin ~= '' then return fb.globalSkin end
  end
  return nil
end
function M.getModel() return model end

----------------------------------------------------------------------------------------------
-- describing parts

function M.describe(partPath)
  local node = partIndex[partPath]
  if not node then return nil end
  local info = partInfo(node.chosenPartName)
  local sInfo = slotInfo(node, parentOf[node])
  local count = countParts(node)
  -- everything comes off except the shell the rest hangs on
  local removable = parentOf[node] ~= nil and partPath ~= chassisPath
  local reason
  if not removable then reason = "The body shell stays where it is." end
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

-- a car that isn't the player's (a customer's or a wreck lent by a career job): its parts aren't theirs to sell
local foreign = false
function M.setForeign(on) foreign = on == true end

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
    foreign = foreign or nil,
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
  -- no car attached: inventory() is then a throwaway table and the part would vanish from the car without reaching the shelf (B63)
  if not model then
    log('W', 'slrrGarageParts', 'removePart: no car is attached, nothing taken off')
    return nil, "Not now."
  end
  local node = partIndex[partPath]
  local item = newItem(node, d.slot)
  item.damage = damage.takePart(node.path)
  local shelf = inventory()
  local before = #shelf
  table.insert(shelf, item)
  if #shelf ~= before + 1 or shelf[#shelf] ~= item then      -- (cannot happen: if it ever does, the part stays on the car)
    log('E', 'slrrGarageParts', 'removePart: the part did not reach the shelf, left on the car')
    damage.addPart(item.damage)
    return nil, "The shelf would not take it."
  end
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

-- Engine swaps in a career (Street Legal's sl/core/engineswap, when it is there): the labour, and a quote shown on the shelf item. An engine of the
-- car's own model only: stock engine slot types are per model.
local function engineRules() local ok, r = pcall(require, 'sl/core/engineswap') return ok and r or nil end
local function isEngineSlotId(id) return tostring(id or ''):match('engine$') ~= nil end

function M.engineSwapQuote(item)
  local es = provider and engineRules()
  if not es or not item or not isEngineSlotId(item.slotId) then return nil end
  local slot = findTargetSlot(item)
  local oldName = slot and isChosen(slot) and partInfo(slot.chosenPartName).name or nil
  local carried = {}
  for id, child in pairs(item.tree and item.tree.children or {}) do if isChosen(child) then carried[id] = true end end
  local needs = {}
  for slotId, def in pairs(partInfo(item.part).slots) do
    if (def.coreSlot or slotId:find('transmission', 1, true) or slotId:find('ecu', 1, true)) and not carried[slotId] then needs[#needs + 1] = prettify(slotId) end
  end
  local q = es.quote({ name = item.name, value = item.value, oldName = oldName, needs = needs })
  q.short = '$' .. q.labour
  q.text = q.text .. '. ' .. es.NO_CROSS_MODEL
  return q
end

-- Bolt a shelf item onto the car. Returns ok, message, needsLoad
--   needsLoad: the game has not got these meshes in memory, the caller must respawn.
function M.installItem(itemId)
  local labourPaid
  local item, idx = findItem(itemId)
  if not item then return false, "That part is gone." end
  if item.foreign and not foreign then return false, "That part belongs to the customer's car." end   -- (back onto a job car: fine)
  local slot = findTargetSlot(item)
  if not slot then return false, "Nothing on the car to bolt the " .. item.name .. " to. Fit the part it attaches to first." end
  if not features.lift and not atShop and M.needsLift(slot.path) then
    return false, "The " .. item.name .. " needs the car up on a lift. Buy one for the garage, or have a shop fit it."
  end
  if isChosen(slot) then
    local d = M.describe(slot.partPath)
    if slot.partPath == chassisPath then return false, "The chassis cannot be swapped here." end
    local es = provider and isEngineSlotId(slot.id) and engineRules()
    if es then
      local labour = es.labour(item.value)
      if not spend(labour, 'Engine swap labour') then return false, string.format('The engine swap is $%d labour.', labour) end
      labourPaid = labour
    end
    -- swap: the old part goes to the shelf
    if not model then return false, "Not now." end            -- (no car attached: the old part would be lost)
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
  if M.needsLoad() and not deferStandins then loadStandins() end
  if labourPaid then item.name = item.name .. string.format(' (engine swap labour $%d)', labourPaid) end
  walk(slot, function(node, parent) slotInfo(node, parent or parentOf[node]) end)
  applyVisibility()
  writeSave()
  return true, item.name, M.needsLoad()
end

-- Fit every shelf part that was bought and has not been on the car yet. Goes round again while
-- anything went on, so a part is fitted before what bolts to it. Returns how many, needsLoad.
function M.installNew()
  local fitted, progress = 0, true
  while progress do
    progress = false
    local todo = {}
    for _, item in ipairs(inventory()) do
      if item.new or item.used then todo[#todo + 1] = item end
    end
    -- nearest the shell first: a new part must not be swapped out again with the part it sits on
    table.sort(todo, function(a, b)
      if #a.slotPath ~= #b.slotPath then return #a.slotPath < #b.slotPath end
      return a.id < b.id
    end)
    -- where the new parts go is worked out once per round, not once per part (it is an off-screen
    -- build of the whole car); a round makes room for the parts that bolt to what it fitted
    deferStandins = true
    for _, item in ipairs(todo) do
      local ok = pcall(M.installItem, item.id) and true
      if ok and not findItem(item.id) then fitted, progress = fitted + 1, true end
    end
    deferStandins = false
    if progress and M.needsLoad() then loadStandins() end
  end
  return fitted, M.needsLoad()
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
  for partPath in pairs(partIndex) do
    if not loadedParts[partPath] or virtualParts[partPath] then return true end
  end
  for partPath in pairs(loadedParts) do
    if not partIndex[partPath] and not virtualParts[partPath] then return true end
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

-- Parts fitted in the garage that the spawned car was not built with are shown as models placed
-- on the car, so nothing has to be loaded while you work. One off-screen build of the car's
-- jbeam (no vehicle is spawned) tells where the game would put each of their meshes, and which
-- sub-parts a freshly bought part comes with.
loadStandins = function()
  local vd = vehData()
  if not vd or not desired then return false end
  local cfg = deepcopy(vd.config)
  cfg.partsTree = deepcopy(desired)
  local dirs = vd.directoriesLoaded or { vd.vehicleDirectory, '/vehicles/common/' }
  headlessLoad = true
  local ok, bundle = pcall(jbeamLoader.loadJbeam, -1, nil, dirs, cfg)
  headlessLoad = false
  if not ok or type(bundle) ~= 'table' or not bundle.vdata then
    log('W', 'slrr_garage', 'could not work out where the new parts go: ' .. tostring(bundle))
    return false
  end

  -- a part that has never been on a car only knows itself; take its sub-parts from the build
  local resolved = {}
  walk(bundle.config and bundle.config.partsTree or {}, function(node) if node.path then resolved[node.path] = node end end)
  local grew = false
  walk(desired, function(node)
    local built = resolved[node.path]
    if isChosen(node) and built and built.chosenPartName == node.chosenPartName and built.children then
      if not node.children then
        node.children = deepcopy(built.children)
        grew = true
      else
        -- a part bought with some of its options chosen knows only those; the rest come as standard
        for slotId, child in pairs(built.children) do
          if node.children[slotId] == nil then
            node.children[slotId] = deepcopy(child)
            grew = true
          end
        end
      end
    end
  end)
  if grew then reindex() end

  local rowsOf = {}
  for _, fb in pairs(bundle.vdata.flexbodies or {}) do
    local path = fb.partPath
    if type(path) == 'string' and partIndex[path] and not loadedParts[path] and type(fb.mesh) == 'string' then
      local rows = rowsOf[path]
      if not rows then rows = {}; rowsOf[path] = rows end
      -- wheels and the like are written relative to their hub; the hub's place comes on top
      -- (mirrored for the left side), which the game only does when it really builds the car
      local pos, off = fb.pos or {}, fb.nodeOffset
      if type(off) == 'table' then
        local px = tonumber(pos.x) or 0
        pos = { x = px + (px < 0 and -1 or 1) * (tonumber(off.x) or 0), y = (tonumber(pos.y) or 0) + (tonumber(off.y) or 0), z = (tonumber(pos.z) or 0) + (tonumber(off.z) or 0) }
      end
      rows[#rows + 1] = { mesh = fb.originalMesh or fb.mesh, pos = pos, rot = fb.rot, scale = fb.scale, origin = fb.partOrigin or partIndex[path].chosenPartName }
    end
  end
  shapes.setup(M.resolvePart, M.getSkin())
  for path in pairs(partIndex) do
    if not loadedParts[path] then
      loadedParts[path] = true
      virtualParts[path] = true
      local rows = rowsOf[path]
      if rows then
        -- the same part sits elsewhere on a car with other suspension or body parts
        local where = {}
        for _, row in ipairs(rows) do
          local pos = row.pos or {}
          where[#where + 1] = string.format('%s:%.3f,%.3f,%.3f', row.mesh, tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0)
        end
        local shape = shapes.get(model, 'on' .. path .. '|' .. table.concat(where, ';'), rows, true)
        if shape then
          local key = '@' .. path
          preview.addStandin(key, shape.path)
          if shape.verts then picker.addStatic(key, path, shape.verts) end
          loadedMeshes[path] = { key }
          meshAlpha[key] = 1
        end
      end
    end
  end
  return true
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
end

-- Vehicle config for a respawn.
--   final = true : exactly what the player built (used when driving out)
--   final = false: the same car to look at; parts taken off stay loaded, hidden, so they
--                  can go straight back on
function M.buildConfig(final)
  local vd = vehData()
  if not vd or not desired then return nil end
  local config = deepcopy(vd.config)
  local tree = deepcopy(desired)
  if not final then keepLoadedParts(tree, loadedTree) end
  config.partsTree = tree
  if desiredVars then config.vars = deepcopy(desiredVars) end
  if desiredPaints and #desiredPaints > 0 then config.paints = deepcopy(desiredPaints) end
  return config
end

function M.isHeadlessLoad() return headlessLoad end

-- What is the car leaving without? Nothing stops you driving out stripped - this is only so
-- the garage can say so on the way out.
-- the job sheet: what this visit changed on the car, and what it cost so far
function M.visitSummary()
  local was, now = {}, {}
  local function collect(tree, into)
    walk(tree or {}, function(node)
      if isChosen(node) and node.partPath then into[node.partPath] = partInfo(node.chosenPartName).name end
    end)
  end
  collect(entryTree, was)
  collect(desired, now)
  local fitted, removed = {}, {}
  for path, name in pairs(now) do if not was[path] then fitted[#fitted + 1] = name end end
  for path, name in pairs(was) do if not now[path] then removed[#removed + 1] = name end end
  table.sort(fitted)
  table.sort(removed)
  return {
    fitted = fitted, removed = removed, net = visitNet, missing = M.missingEssentials(),
    tuned = M.varsDirty(), painted = M.paintsDirty(), money = M.getMoney(), unlimited = M.isUnlimited(),
  }
end

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
  if provider then
    if visitNet ~= 0 then provider.add(visitNet, 'Garage visit undone') end
  elseif not inCareer() and not unlimited() and visitNet ~= 0 then
    save.wallet = wallet() + visitNet
  end
  if not provider and inCareer() and visitNet ~= 0 then
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
  if item.foreign then return 0 end      -- (off someone else's car: nothing over the counter)
  -- a part bought second-hand from another mod's market is worth what was paid, whatever the price setting
  local value = (item.market and item.value or itemPrice(item)) * settings.get('sellFactor')
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
-- saved builds: the car as it stands, to go back to later

local function builds()
  save.builds = save.builds or {}
  local list = save.builds[model]
  if not list then list = {}; save.builds[model] = list end
  return list
end

-- Make the car match a build, slot by slot from the top. Where a slot differs, what is there
-- goes to the shelf and the build's part comes off the shelf if there is one, or is bought.
-- dry = true only adds up what would have to be bought.
local function reconcile(buildNode, dry, state)
  local cur = slotIndex[buildNode.path]
  if not cur then return end
  local want = isChosen(buildNode) and buildNode.chosenPartName or ''
  local have = isChosen(cur) and cur.chosenPartName or ''
  if want == have then
    for _, child in pairs(buildNode.children or {}) do reconcile(child, dry, state) end
    return
  end
  if cur.partPath and cur.partPath == chassisPath then return end
  local item
  if want ~= '' then
    for _, candidate in ipairs(inventory()) do
      if candidate.part == want and candidate.slotId == cur.id and not state.used[candidate.id] then item = candidate break end
    end
    if item then
      state.used[item.id] = true
    else
      state.cost = state.cost + priced(subtreeValue(buildNode))
      state.bought = state.bought + 1
    end
  end
  if dry then return end
  if have ~= '' then M.removePart(cur.partPath) end
  if want == '' then return end
  local fromShelf = item ~= nil
  if not item then
    item = newItem(deepcopy(buildNode), slotInfo(cur, parentOf[cur]).description)
    item.new = true
    table.insert(inventory(), item)
  end
  item.slotPath = buildNode.path
  M.installItem(item.id)
  if fromShelf then
    for _, child in pairs(buildNode.children or {}) do reconcile(child, dry, state) end
  end
end

function M.getBuilds()
  local out = {}
  if not desired then return out end
  for i, build in ipairs(builds()) do
    local state = { cost = 0, bought = 0, used = {} }
    reconcile(build.tree, true, state)
    out[i] = { name = build.name, cost = state.cost, toBuy = state.bought }
  end
  return out
end

function M.saveBuild(name)
  if not desired then return false end
  name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 40)
  if name == '' then name = 'Build ' .. (#builds() + 1) end
  local list = builds()
  for i, build in ipairs(list) do
    if build.name == name then table.remove(list, i) break end       -- saving under the same name replaces it
  end
  list[#list + 1] = { name = name, tree = deepcopy(desired), vars = deepcopy(desiredVars or {}) }
  writeSave()
  return true, name
end

function M.deleteBuild(index)
  if builds()[index] then
    table.remove(builds(), index)
    writeSave()
  end
end

-- returns ok, message
function M.loadBuild(index)
  local build = builds()[index]
  if not build or not desired then return false, "That build is gone." end
  local plan = { cost = 0, bought = 0, used = {} }
  reconcile(build.tree, true, plan)
  if not spend(plan.cost, 'Parts for ' .. build.name) then
    return false, string.format("That build needs $%d of parts you do not have.", plan.cost)
  end
  deferStandins = true
  local ok, err = pcall(reconcile, build.tree, false, { cost = 0, bought = 0, used = {} })
  deferStandins = false
  if not ok then log('E', 'slrr_garage', 'loading a build failed: ' .. tostring(err)) end
  desiredVars = deepcopy(build.vars or desiredVars)
  if M.needsLoad() then loadStandins() end
  applyVisibility()
  writeSave()
  return true, plan.bought > 0 and string.format('%s is on the car. %d parts were bought for $%d.', build.name, plan.bought, plan.cost) or (build.name .. ' is on the car.')
end

-- sell everything on the shelf; returns how many parts and for how much
function M.sellAll()
  local inv = inventory()
  local count, total = #inv, 0
  for _, item in ipairs(inv) do total = total + M.sellValue(item) end
  if count == 0 then return 0, 0 end
  earn(total, 'Sold ' .. count .. ' parts')
  for i = #inv, 1, -1 do inv[i] = nil end
  writeSave()
  return count, total
end

-- what the whole shelf would fetch
function M.shelfValue()
  local total = 0
  for _, item in ipairs(inventory()) do total = total + M.sellValue(item) end
  return total
end

----------------------------------------------------------------------------------------------
-- repairs

local function repairPriceOf(value)
  if features.repairFactor ~= 1 then return math.floor(priced(value) * settings.get('repairFactor') * features.repairFactor + 0.5) end
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
        more = next(info.slots) ~= nil,       -- it has slots of its own: there may be options to choose
      }
    end
  end)
  if yardStock then
    -- The yard has whatever came in this week: a pick of the catalog that changes from day to
    -- day, well under list price, and none of it straight.
    yardStock = {}
    local day = tostring(os.date('%Y%j'))
    local total = 0
    for _, list in pairs(bySub) do total = total + #list end
    for key, list in pairs(bySub) do
      local kept = {}
      for _, entry in ipairs(list) do
        local h = stringHash(entry.part .. entry.slotPath .. day)
        if entry.price > 0 and h % 1000 < 1000 * math.min(1, 48 / math.max(1, total)) then
          local discount = 0.35 + (math.floor(h / 1000) % 31) / 100
          local dent = 0.012 + (math.floor(h / 31000) % 30) / 1000
          yardStock[entry.slotPath .. entry.part] = { discount = discount, dent = dent, seed = h % 100000 }
          entry.listPrice = entry.price
          entry.price = math.floor(entry.price * (1 - discount) + 0.5)
          entry.used = math.floor(discount * 100 + 0.5)
          kept[#kept + 1] = entry
        end
      end
      bySub[key] = kept
    end
  end
  for _, list in pairs(bySub) do
    table.sort(list, function(a, b)
      if a.slot ~= b.slot then return a.slot < b.slot end
      if a.price ~= b.price then return a.price < b.price end
      return a.name < b.name
    end)
  end
  return bySub
end

-- a brand new part for a slot of this car, as a shelf item (not paid for, not on the shelf yet)
local function newPart(slotPath, partName)
  local slot = slotIndex[slotPath]
  if not slot or not fits(slot, partName) then return nil end
  local info = partInfo(partName)
  local sInfo = slotInfo(slot, parentOf[slot])
  local node = {
    id = slot.id, path = slot.path, chosenPartName = partName, partPath = slot.path .. partName,
    decisionMethod = 'user', suitablePartNames = slot.suitablePartNames, unsuitablePartNames = slot.unsuitablePartNames,
  }
  local item = newItem(node, sInfo.description)
  item.value = info.value
  item.new = true
  return item
end

----------------------------------------------------------------------------------------------
-- ordering: shopping list, delivery, parts on their way

-- How heavy and how bulky is a part? Read from its own jbeam nodes; parts without any (wheels,
-- electronics) get a sensible guess. Returns weight in kg and longest dimension in metres.
local function freight(partName)
  local hit = freightCache[partName]
  if hit then return hit.weight, hit.size end
  local part = getPart(partName)
  local weight, count = 0, 0
  local lo, hi = vec3(math.huge, math.huge, math.huge), vec3(-math.huge, -math.huge, -math.huge)
  local nodeWeight = 25
  for _, row in ipairs(part and type(part.nodes) == 'table' and part.nodes or {}) do
    if type(row) == 'table' then
      if tonumber(row.nodeWeight) then nodeWeight = tonumber(row.nodeWeight) end
      local x, y, z = tonumber(row[2]), tonumber(row[3]), tonumber(row[4])
      if type(row[1]) == 'string' and x and y and z then
        local w = type(row[5]) == 'table' and tonumber(row[5].nodeWeight) or nodeWeight
        weight, count = weight + w, count + 1
        local p = vec3(x, y, z)
        lo:setMin(p); hi:setMax(p)
      end
    end
  end
  local size = count > 1 and (hi - lo):length() or 0
  if count == 0 then
    local n = partName:lower()
    if n:find('tire') or n:find('tyre') then weight, size = 11, 0.68
    elseif n:find('wheel') or n:find('rim') then weight, size = 9, 0.5
    elseif n:find('engine') then weight, size = 120, 0.8
    else weight, size = 2, 0.3 end
  end
  size = math.max(size, 0.2)
  freightCache[partName] = { weight = weight, size = size }
  return weight, size
end

function M.partWeight(partName)
  return (freight(partName))
end

-- ways to get an order: collect (only in a shop, you carry it out yourself), standard, express
local function shippingOptions(inShop)
  if inShop then return { { id = 'collect', title = 'Take it with you', factor = 0, seconds = 0 } } end
  local standard = settings.get('deliveryMinutes') * 60
  return {
    { id = 'standard', title = 'Standard delivery', factor = 1, seconds = standard },
    { id = 'express', title = 'Express delivery', factor = settings.get('expressMultiplier'), seconds = settings.get('expressMinutes') * 60 },
  }
end

-- what it costs to deliver one part by standard delivery: a base, by the kilo, and for bulk
local function deliveryFee(partName)
  local weight, size = freight(partName)
  return (6 + weight * 0.9 + size * size * 14) * settings.get('deliveryFactor')
end

-- ... and a cart entry: the part and the options that were chosen for it
local function entryFee(entry)
  local fee = deliveryFee(entry.part)
  for _, name in ipairs(entry.extraParts or {}) do fee = fee + deliveryFee(name) end
  return fee
end

-- A part's own slots and what can go in each, so they can be chosen before it is bought:
-- { { id, path, title, default, core, options = { { part, name, price, more } } } }.
-- A slot with nothing to choose is left out. What a slot comes with as standard costs nothing extra.
local function slotChoices(slotDef)
  local vd = vehData()
  local ok, names = pcall(jbeamIO.getCompatiblePartNamesForSlot, vd.ioCtx, slotDef)
  names = ok and type(names) == 'table' and names or {}
  local default = type(slotDef.default) == 'string' and slotDef.default or ''
  local found = false
  for _, name in ipairs(names) do
    if name == default then found = true end
  end
  return names, found and default or ''
end

function M.partSlots(slotPath, partName)
  local out = {}
  local part = getPart(partName)
  if not vehData() or not part or yardStock then return out end
  for _, slotDef in ipairs(type(part.slots2) == 'table' and part.slots2 or {}) do
    local id = type(slotDef) == 'table' and slotDef.name
    if type(id) == 'string' then
      local names, default = slotChoices(slotDef)
      if #names > 1 or (#names == 1 and default == '') then
        local options = {}
        for _, name in ipairs(names) do
          local info = partInfo(name)
          options[#options + 1] = { part = name, name = info.name, price = name == default and 0 or priced(info.value), more = next(info.slots) ~= nil }
        end
        table.sort(options, function(a, b)
          if a.price ~= b.price then return a.price < b.price end
          return a.name < b.name
        end)
        out[#out + 1] = {
          id = id, path = slotPath .. id .. '/', default = default, core = slotDef.coreSlot == true, options = options,
          title = (type(slotDef.description) == 'string' and slotDef.description ~= '') and slotDef.description or prettify(id),
        }
      end
    end
  end
  table.sort(out, function(a, b) return a.title < b.title end)
  return out
end

-- The options chosen for a part ({ [slotId] = { part = name or '', sub = {...} } }) as tree
-- nodes, checked against what really fits. acc collects what they add: value and part names.
local function chosenChildren(parentPath, partName, sub, acc, depth)
  if type(sub) ~= 'table' or (depth or 0) > 12 then return nil end
  local part = getPart(partName)
  local children
  for _, slotDef in ipairs(part and type(part.slots2) == 'table' and part.slots2 or {}) do
    local id = type(slotDef) == 'table' and slotDef.name
    local choice = type(id) == 'string' and sub[id] or nil
    if type(choice) == 'table' and type(choice.part) == 'string' then
      local names, default = slotChoices(slotDef)
      local path = parentPath .. id .. '/'
      local node
      if choice.part == '' then
        if slotDef.coreSlot ~= true then
          node = { id = id, path = path, chosenPartName = '', decisionMethod = 'user-empty', suitablePartNames = names }
        end
      elseif tableContains(names, choice.part) then
        node = { id = id, path = path, chosenPartName = choice.part, partPath = path .. choice.part, decisionMethod = 'user', suitablePartNames = names }
        if choice.part ~= default then
          acc.value = acc.value + partInfo(choice.part).value
          acc.parts[#acc.parts + 1] = choice.part
        end
        node.children = chosenChildren(path, choice.part, choice.sub, acc, (depth or 0) + 1)
      end
      if node then
        children = children or {}
        children[id] = node
      end
    end
  end
  return children
end

-- sub: the options chosen for the part's own slots (see chosenChildren), or nil
function M.cartAdd(slotPath, partName, sub)
  local slot = slotIndex[slotPath]
  if not slot or not fits(slot, partName) then return false, "That part does not fit this car." end
  local used = yardStock and yardStock[slotPath .. partName]
  if yardStock and not used then return false, "The yard has not got one of those." end
  if used then
    for _, entry in ipairs(cart) do
      if entry.slotPath == slotPath and entry.part == partName then return false, "There is only the one." end
    end
  end
  local acc = { value = 0, parts = {} }
  local children = not used and chosenChildren(slotPath, partName, sub, acc) or nil
  cart[#cart + 1] = { slotPath = slotPath, part = partName, used = used, children = children, extraValue = acc.value, extraParts = acc.parts }
  return true
end

-- the used-parts yard is open (or shut again)
function M.setYard(open)
  yardStock = open and {} or nil
end

-- what a cart entry costs: list price, or what the yard asks for its second-hand one
local function cartPrice(entry)
  local price = priced(partInfo(entry.part).value + (entry.extraValue or 0))
  if entry.used then price = math.floor(price * (1 - entry.used.discount) + 0.5) end
  return price
end

function M.cartRemove(index)
  if cart[index] then table.remove(cart, index) end
end

function M.cartClear() cart = {} end

-- the shopping list with prices, for the UI
function M.cartSummary(inShop)
  local out = { items = {}, subtotal = 0, shipping = {}, orders = {} }
  local base = 0
  for i, entry in ipairs(cart) do
    local info = partInfo(entry.part)
    local weight, size = freight(entry.part)
    for _, name in ipairs(entry.extraParts or {}) do weight = weight + freight(name) end
    local fee = entryFee(entry)
    local price = cartPrice(entry)
    local options = #(entry.extraParts or {})
    out.items[i] = { name = info.name .. (entry.used and ' (used)' or '') .. (options > 0 and string.format(' (+%d option%s)', options, options == 1 and '' or 's') or ''), part = entry.part, price = price, weight = math.floor(weight * 10 + 0.5) / 10, size = math.floor(size * 100 + 0.5) / 100, fee = math.floor(fee + 0.5) }
    out.subtotal = out.subtotal + price
    base = base + fee
  end
  for _, option in ipairs(shippingOptions(inShop)) do
    local fee = math.floor(base * option.factor + 0.5)
    out.shipping[#out.shipping + 1] = { id = option.id, title = option.title, fee = fee, seconds = math.floor(option.seconds + 0.5), total = out.subtotal + fee }
  end
  local now = os.time()
  for _, order in ipairs(save.orders) do
    if order.model == model then
      out.orders[#out.orders + 1] = { name = order.item.name, seconds = math.max(0, (order.due or 0) - now) }
    end
  end
  out.money = M.getMoney()
  return out
end

-- pay for the shopping list and send it on its way. Returns ok, message.
function M.checkout(shippingId, inShop)
  if #cart == 0 then return false, "The shopping list is empty." end
  if #inventory() + #cart > features.shelfSize then return false, "No room on the shelves: fit or sell some parts first, or put more shelving in." end
  local option
  for _, o in ipairs(shippingOptions(inShop)) do
    if o.id == shippingId then option = o end
  end
  option = option or shippingOptions(inShop)[1]
  local subtotal, base, items, bought = 0, 0, {}, {}
  for _, entry in ipairs(cart) do
    local item = newPart(entry.slotPath, entry.part)
    if item then
      items[#items + 1] = item
      bought[#bought + 1] = { slotPath = entry.slotPath, part = entry.part, price = cartPrice(entry) }
      subtotal = subtotal + cartPrice(entry)
      base = base + entryFee(entry)
      if entry.children then
        -- it arrives built the way it was ordered
        item.tree.children = deepcopy(entry.children)
        item.value = item.value + (entry.extraValue or 0)
        item.count = countParts(item.tree)
      end
      if entry.used then
        -- second-hand: worth what was paid for it, and bent - the dent is put on the part when
        -- the car is next built with it, and can be repaired like any other damage
        local path = entry.slotPath .. entry.part
        item.value = item.value * (1 - entry.used.discount)
        item.used, item.new = true, nil
        item.damage = { nodes = {}, beams = { { dent = entry.used.dent, seed = entry.used.seed, pa = path, pb = path } } }
      end
    end
  end
  local total = subtotal + math.floor(base * option.factor + 0.5)
  if not spend(total, #items == 1 and ('Bought ' .. items[1].name) or ('Bought ' .. #items .. ' parts')) then return false, "Not enough money." end
  local due = os.time() + math.floor(option.seconds + 0.5)
  for _, item in ipairs(items) do
    if option.seconds <= 0 then
      table.insert(inventory(), item)
    else
      save.orders[#save.orders + 1] = { item = item, due = due, model = model }
    end
  end
  cart = {}
  writeSave()
  if option.seconds <= 0 then return true, #items == 1 and (items[1].name .. ' is on your shelf at the garage.') or (#items .. ' parts are on your shelf at the garage.'), bought end
  local minutes = option.seconds / 60
  return true, string.format('Ordered. Delivery to the garage in %s.', minutes >= 1 and string.format('%.0f min', minutes) or string.format('%.0f s', option.seconds)), bought
end

-- orders (for any car) that have arrived and have not been announced yet; each counts once
function M.announceArrivals()
  local now, arrived = os.time(), 0
  for _, order in ipairs(save.orders) do
    if not order.told and (order.due or 0) <= now then
      order.told = true
      arrived = arrived + 1
    end
  end
  if arrived > 0 then writeSave() end
  return arrived
end

-- put orders that have arrived on the shelf; returns how many
function M.collectDeliveries()
  local now, arrived, keep = os.time(), 0, {}
  for _, order in ipairs(save.orders) do
    if order.model == model and (order.due or 0) <= now then
      table.insert(inventory(), order.item)
      arrived = arrived + 1
    else
      keep[#keep + 1] = order
    end
  end
  if arrived > 0 then
    save.orders = keep
    writeSave()
  end
  return arrived
end

----------------------------------------------------------------------------------------------
-- state for the UI

function M.getInventory() return inventory() end

-- a part bought elsewhere (a career's used-parts market) onto the shelf for a model, with no car on the lift:
-- p = { part, name, slotId (the slot type it fits), value (what was paid), wear 0..1 }. Fitted like any other
-- shelf part (by slot type); sells back for half of what was paid
function M.addShelfPart(modelName, p)
  if type(modelName) ~= 'string' or type(p) ~= 'table' or type(p.part) ~= 'string' then return nil end
  local section, sub = catalogDef.classify(p.slotId or '', p.part)
  local item = { id = save.nextId, part = p.part, name = p.name or prettify(p.part), slotId = p.slotId, slot = prettify(p.slotId or p.part),
    section = section, sub = sub, value = tonumber(p.value) or 0, count = 1, used = true, market = true,
    wear = tonumber(p.wear), tree = { id = p.slotId, chosenPartName = p.part, decisionMethod = 'user' } }
  save.nextId = save.nextId + 1
  save.inventory[modelName] = save.inventory[modelName] or {}
  table.insert(save.inventory[modelName], item)
  writeSave()
  return item.id
end

-- a model's shelf for other mods (a career's market selling your parts): plain copies, no trees
function M.shelfItems(modelName)
  local out = {}
  for _, item in ipairs(save.inventory[modelName] or {}) do
    -- price: what the shop charges for it now (the price setting applied; a market part, what was paid), so another
    -- mod's market never pays more for it than it cost here
    out[#out + 1] = { id = item.id, part = item.part, name = item.name, slotId = item.slotId, value = item.value, wear = item.wear,
      price = item.market and item.value or itemPrice(item),
      count = item.count or 1, foreign = item.foreign == true, damaged = damage.count(item.damage) > 0, market = item.market == true }
  end
  return out
end

-- take a shelf item off a model's shelf (listed for sale elsewhere) and put it back (the listing withdrawn)
function M.takeShelfItem(modelName, itemId)
  local inv = save.inventory[modelName] or {}
  for i, item in ipairs(inv) do
    if item.id == itemId then
      table.remove(inv, i)
      writeSave()
      return item
    end
  end
end
function M.putShelfItem(modelName, item)
  if type(modelName) ~= 'string' or type(item) ~= 'table' or not item.part then return false end
  save.inventory[modelName] = save.inventory[modelName] or {}
  table.insert(save.inventory[modelName], item)
  writeSave()
  return true
end

-- names of everything bolted to a shelf part (what "+3 parts" stands for)
function M.itemContents(item)
  local names = {}
  walk(item.tree, function(node, parent)
    if parent and isChosen(node) then names[#names + 1] = partInfo(node.chosenPartName).name end
  end)
  table.sort(names)
  return names
end
function M.itemPrice(item) return itemPrice(item) end
function M.itemDamaged(item) return damage.count(item.damage) > 0 end
function M.itemRepairCost(item) return damage.count(item.damage) > 0 and repairPriceOf(item.value) or 0 end
function M.getSections() return catalogDef.sections end

function M.onExtensionLoaded() end

loadSave()

return M
