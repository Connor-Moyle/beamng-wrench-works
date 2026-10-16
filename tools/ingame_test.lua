-- Drives Wrench Works through its features in the game and writes what happened to
-- settings/slrr_garage/test_results.json in the BeamNG user folder. Not part of the mod.
--
-- To run it: copy this file to  <user folder>/lua/ge/extensions/wwtest.lua , load West Coast USA
-- with any car, open the console (~), pick "GE - Lua" and enter  extensions.load('wwtest')
-- Then leave the game alone for about five minutes. It takes the car into the garage twice,
-- visits a shop, and walks in to buy a Covet shell.
--
-- It spends from your freeroam money and leaves parts on your shelf. Copy
-- settings/slrr_garage/save.json somewhere first if you want those back as they were.

local M = {}

local OUT = '/settings/slrr_garage/test_results.json'
local R = { steps = {}, finished = false }

local function save() jsonWriteFile(OUT, R, true) end

local function step(name, ok, info)
  R.steps[#R.steps + 1] = { name = name, ok = ok and true or false, info = info ~= nil and tostring(info) or nil }
  log('I', 'wwtest', string.format('%s  %s  %s', ok and 'PASS' or 'FAIL', name, tostring(info)))
  save()
end

local function waitFor(job, fn, timeout)
  local t = 0
  while t < timeout do
    local v = fn()
    if v then return v, t end
    job.sleep(0.25)
    t = t + 0.25
  end
  return nil, t
end

local function try(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then step(name .. ' (crashed)', false, err) end
end

local function phase() return slrr_garage and slrr_garage.getPhase() end

local function findNode(tree, path)
  local found
  local function walk(node)
    if node.path == path then found = node end
    for _, child in pairs(node.children or {}) do walk(child) end
  end
  walk(tree or {})
  return found
end

local function run(job)
  local parts, settings, sites, music = require('slrr/garageParts'), require('slrr/garageSettings'), require('slrr/garageSites'), require('slrr/garageMusic')

  ---------------------------------------------------------------- load the map
  local ready = getPlayerVehicle(0) and worldReadyState == 2 and getCurrentLevelIdentifier() == 'west_coast_usa'
  step('West Coast USA is loaded, with a vehicle', ready, tostring(getCurrentLevelIdentifier and getCurrentLevelIdentifier()))
  if not ready then return end
  local v = getPlayerVehicle(0)
  R.model = v:getJBeamFilename()
  local vehId = v:getID()

  ---------------------------------------------------------------- the mod is there
  step('extension loaded', slrr_garage ~= nil)
  if not slrr_garage then return end
  step('garages and shops on the map', #sites.getSites() >= 3 and #sites.getShops() >= 7, string.format('%d garages, %d shops', #sites.getSites(), #sites.getShops()))
  local expressMinutes = settings.get('expressMinutes')
  settings.set('expressMinutes', 0)       -- so that what the test orders arrives at once

  ---------------------------------------------------------------- visit 1: drive in
  try('visit 1', function()
    slrr_garage.enter()
    job.sleep(4)
    local inGarage, t = waitFor(job, function() return phase() == 'garage' end, 60)
    step('drive in reaches the garage', inGarage, string.format('%.1f s, phase %s', t, tostring(phase())))
    if not inGarage then return end
    job.sleep(5)
    v = getPlayerVehicle(0)

    -- music
    local m = music.status()
    step('music is playing', m.playing, string.format('%d tracks, placed at the radio: %s, %s', m.tracks, tostring(m.placed), tostring(m.file)))

    -- take a part off by pointing at the car
    local centre = v:getSpawnWorldOOBB():getCenter()
    local dir = vec3(v:getDirectionVector())
    local right = vec3(dir.y, -dir.x, 0)
    local targets = {}
    for _, a in ipairs({ 1.6, -1.6, 0.8, -0.8, 0, 2.0, -2.0 }) do
      for _, s in ipairs({ 0, 0.6, -0.6, 0.85, -0.85 }) do
        for _, u in ipairs({ 0.1, 0.4, -0.2 }) do targets[#targets + 1] = centre + dir * a + right * s + vec3(0, 0, u) end
      end
    end
    local function pointAtRemovable(skip)
      for _, target in ipairs(targets) do
        local picked, partPath = slrr_garage.debugPointAt(target)
        local d = partPath and parts.describe(partPath)
        if d and d.removable and partPath ~= skip then return partPath, d, target end
      end
    end
    local path, d = pointAtRemovable()
    step('a part can be picked', path ~= nil, path and (d.name .. ' at ' .. path) or 'nothing removable found under 105 points')
    if path then
      local before = #parts.getInventory()
      slrr_garage.click()
      job.sleep(0.5)
      local inv = parts.getInventory()
      step('clicking it puts it on the shelf', #inv == before + 1 and parts.describe(path) == nil, string.format('shelf %d -> %d', before, #inv))
      job.sleep(1.5)
      local item = inv[#inv]
      if item then
        slrr_garage.install(item.id)
        job.sleep(1.5)
        step('clicking it on the shelf refits it', #parts.getInventory() == before and parts.describe(path) ~= nil, 'phase ' .. tostring(phase()))
      end
      waitFor(job, function() return phase() == 'garage' end, 30)

      -- the sell tool, straight off the car
      slrr_garage.setTool('sell')
      local money = parts.getMoney()
      local sellPath, sd = pointAtRemovable()
      if sellPath then
        slrr_garage.click()
        job.sleep(0.6)
        step('sell tool sells a part off the car', parts.getMoney() > money and #parts.getInventory() == before, string.format('%s: $%d -> $%d', sd.name, money, parts.getMoney()))
      else
        step('sell tool sells a part off the car', false, 'nothing to point at')
      end
      slrr_garage.setTool('sell')
    end

    -- the catalog: a part with options of its own, and a plain one
    slrr_garage.openCatalog()
    job.sleep(1)
    step('catalog opens', phase() == 'catalog')
    local clock = hptimer()
    local cat = parts.buildCatalog()
    local total, withOptions, plain, checked = 0, nil, nil, 0
    for _, list in pairs(cat) do
      for _, e in ipairs(list) do
        total = total + 1
        if e.price > 0 and not e.fitted then
          if e.more and not withOptions and checked < 400 then
            checked = checked + 1
            for _, s in ipairs(parts.partSlots(e.slotPath, e.part)) do
              for _, o in ipairs(s.options) do
                if not withOptions and o.part ~= s.default then withOptions = { e = e, slot = s, opt = o } end
              end
            end
          elseif not e.more and not plain then
            plain = e
          end
        end
      end
    end
    step('catalog lists parts', total > 0, string.format('%d parts, looked into %d for options in %.0f ms', total, checked, clock:stop()))
    local shelfBefore = #parts.getInventory()
    if withOptions then
      local e, s, o = withOptions.e, withOptions.slot, withOptions.opt
      R.optionPick = string.format('%s (%s) with %s = %s', e.name, e.part, s.title, o.name)
      slrr_garage.buy(e.slotPath, e.part, { [s.id] = { part = o.part, sub = {} } })
      local cart = parts.cartSummary(false)
      step('a part with a chosen option goes on the list', #cart.items == 1 and cart.items[1].name:find('option', 1, true) ~= nil, cart.items[1] and (cart.items[1].name .. ' $' .. cart.items[1].price) or 'empty list')
    else
      step('a part with a chosen option goes on the list', false, 'this car has no part with options among the first ' .. checked)
    end
    if plain then slrr_garage.buy(plain.slotPath, plain.part) end
    local money = parts.getMoney()
    slrr_garage.checkout('express')
    job.sleep(0.5)
    local inv = parts.getInventory()
    step('checkout pays and delivers', #inv > shelfBefore and parts.getMoney() < money, string.format('shelf %d -> %d, $%d -> $%d', shelfBefore, #inv, money, parts.getMoney()))
    if withOptions then
      local got
      for _, item in ipairs(inv) do
        if item.new and item.part == withOptions.e.part then got = item end
      end
      local child = got and got.tree.children and got.tree.children[withOptions.slot.id]
      step('it arrives built as ordered', child ~= nil and child.chosenPartName == withOptions.opt.part, got and ('parts in the box: ' .. tostring(got.count)) or 'not on the shelf')
    end
    slrr_garage.closeCatalog()
    job.sleep(0.5)

    -- fit everything that was bought
    slrr_garage.installNew()
    job.sleep(1)
    local back, t2 = waitFor(job, function() return phase() == 'garage' end, 60)
    local left = 0
    for _, item in ipairs(parts.getInventory()) do
      if item.new then left = left + 1 end
    end
    step('fit all new parts', back and left == 0, string.format('%d new parts still on the shelf, took %.1f s', left, t2 + 1))
    if withOptions then
      local e, s, o = withOptions.e, withOptions.slot, withOptions.opt
      step('the chosen option is on the car', parts.partPathAtSlot(e.slotPath) == e.slotPath .. e.part and parts.partPathAtSlot(s.path) == s.path .. o.part,
        tostring(parts.partPathAtSlot(e.slotPath)) .. ' / ' .. tostring(parts.partPathAtSlot(s.path)))
    end
    job.sleep(2)

    -- paint, tuning, builds
    local money2 = parts.getMoney()
    slrr_garage.setPaint(1, { baseColor = { 0.7, 0.05, 0.05, 1 }, metallic = 0.6, roughness = 0.4, clearcoat = 1, clearcoatRoughness = 0.05 })
    job.sleep(1.5)
    local p = parts.getPaints()[1]
    step('respray', p and math.abs(p.baseColor[1] - 0.7) < 0.01 and parts.getMoney() < money2, string.format('$%d -> $%d', money2, parts.getMoney()))
    slrr_garage.setMode('tune')
    step('tuning list', #parts.getTuning() >= 0, #parts.getTuning() .. ' adjustments')
    slrr_garage.setMode('mechanic')
    slrr_garage.saveBuild('wwtest build')
    local builds = parts.getBuilds()
    step('saved build', #builds > 0 and builds[#builds].name == 'wwtest build')
    slrr_garage.deleteBuild(#builds)

    -- the lift
    local z0 = v:getPosition().z
    slrr_garage.toggleLift()
    job.sleep(6)
    v = getPlayerVehicle(0)
    step('lift raises the car', v:getPosition().z - z0 > 0.8, string.format('%.2f m', v:getPosition().z - z0))
    job.sleep(1)

    -- drive out (the car is rebuilt with what was fitted)
    slrr_garage.leave(true)
    job.sleep(6)
    local out, t3 = waitFor(job, function() return phase() == 'idle' end, 120)
    v = getPlayerVehicle(0)
    step('drive out', out and v ~= nil, string.format('%.1f s', t3 + 6))
    if out and v and withOptions then
      local vd = core_vehicle_manager.getVehicleData(v:getID())
      local node = vd and findNode(vd.config.partsTree, withOptions.slot.path)
      step('the rebuilt car has the chosen option', node ~= nil and node.chosenPartName == withOptions.opt.part, node and node.chosenPartName or 'slot not in the built car')
    end
  end)
  if phase() ~= 'idle' then slrr_garage.abort() job.sleep(3) end
  job.sleep(4)

  ---------------------------------------------------------------- visit 2: nothing changed, leave from the raised lift
  try('visit 2', function()
    slrr_garage.enter()
    local inGarage = waitFor(job, function() return phase() == 'garage' end, 60)
    step('second drive in', inGarage)
    if not inGarage then return end
    job.sleep(3)
    slrr_garage.toggleLift()
    job.sleep(6)
    slrr_garage.leave(true)
    local minVz, t = 0, 0
    while phase() ~= 'idle' and t < 120 do
      local car = getPlayerVehicle(0)
      if car then minVz = math.min(minVz, car:getVelocity().z) end
      job.sleep(0.03)
      t = t + 0.03
    end
    step('leaving from the lift lowers the car, it is not dropped', phase() == 'idle' and minVz > -1.5, string.format('fastest fall %.2f m/s', minVz))
    local car = getPlayerVehicle(0)
    wwtest_damage = nil
    if car then car:queueLuaCommand('obj:queueGameEngineLua("wwtest_damage = " .. tostring(beamstate.damage or 0))') end
    job.sleep(1)
    step('no damage from the visit', wwtest_damage ~= nil and wwtest_damage < 50, 'damage ' .. tostring(wwtest_damage))
  end)
  if phase() ~= 'idle' then slrr_garage.abort() job.sleep(3) end

  -- visit 3: another mod's screen (Street Legal's laptop) sends the car in, in a mode
  try('enterWith', function()
    local car = getPlayerVehicle(0)
    step('garageAt names the garage the car stands at', car ~= nil and slrr_garage.garageAt(car:getPosition()) ~= nil, car and tostring(slrr_garage.garageAt(car:getPosition())))
    if not car then return end
    local ok = slrr_garage.enterWith(car:getID(), 'tune')
    local inGarage = ok and waitFor(job, function() return phase() == 'garage' end, 60)
    step('enterWith(tune) opens the garage in tune mode', inGarage and slrr_garage.getMode() == 'tune', 'phase ' .. tostring(phase()) .. ', mode ' .. tostring(slrr_garage.getMode()))
    if not inGarage then return end
    slrr_garage.leave(true)
    waitFor(job, function() return phase() == 'idle' end, 120)
    job.sleep(2)
    local ok2 = slrr_garage.enterWith(car:getID(), 'catalog')
    local inCatalog = ok2 and waitFor(job, function() return phase() == 'catalog' end, 60)
    step('enterWith(catalog) opens the catalog', inCatalog, 'phase ' .. tostring(phase()))
    step('enterWith refuses while the garage is busy', slrr_garage.enterWith(car:getID(), 'tune') == false)
  end)
  if phase() ~= 'idle' then slrr_garage.abort() job.sleep(3) end
  job.sleep(3)

  ---------------------------------------------------------------- a shop
  try('shop', function()
    local shop = sites.getShops()[1]
    local car = getPlayerVehicle(0)
    spawn.safeTeleport(car, shop.pos + vec3(0, 0, 0.3), quatFromDir(vec3(0, 1, 0), vec3(0, 0, 1)), true, nil, false, true, false)
    local inShop, t = waitFor(job, function() return phase() == 'shop' end, 25)
    step('stopping at a shop opens its counter', inShop, string.format('%s, %.1f s', shop.name, t))
    if not inShop then return end
    job.sleep(2)
    local n = 0
    for _, list in pairs(parts.buildCatalog()) do n = n + #list end
    step('the shop has parts for the car', n > 0, n .. ' parts in all chapters')
    job.sleep(2)
    slrr_garage.closeCatalog()
    job.sleep(1)
    step('leaving the shop', phase() == 'idle')
  end)
  if phase() ~= 'idle' then slrr_garage.abort() job.sleep(3) end

  ---------------------------------------------------------------- on foot: an empty lift and a body shell
  try('walk in', function()
    local money = parts.getMoney()
    gameplay_walk.setWalkingMode(true)
    local walking = waitFor(job, function() local p = getPlayerVehicle(0) return p and p:getJBeamFilename() == 'unicycle' end, 15)
    step('walking mode', walking)
    if not walking then return end
    job.sleep(1)
    slrr_garage.enter()
    local inLot = waitFor(job, function() return phase() == 'lot' end, 15)
    step('on foot the garage offers body shells', inLot, 'phase ' .. tostring(phase()))
    if not inLot then return end
    job.sleep(5)
    job.sleep(1)
    slrr_garage.buyShell('covet')
    local inGarage, t = waitFor(job, function() return phase() == 'garage' end, 120)
    step('a bought shell is put on the lift', inGarage, string.format('%.1f s, phase %s', t, tostring(phase())))
    if not inGarage then return end
    job.sleep(4)
    local car = getPlayerVehicle(0)
    local info = parts.getCarInfo()
    step('it is a covet, and the player sits in it', car and car:getJBeamFilename() == 'covet')
    step('it is stripped', info.parts < 40, info.parts .. ' parts left on it')
    step('it was paid for', parts.getMoney() < money, string.format('$%d -> $%d', money, parts.getMoney()))
    local n = 0
    for _, list in pairs(parts.buildCatalog()) do n = n + #list end
    step('the catalog has parts for the shell', n > 0, n .. ' parts')
    job.sleep(2)
    slrr_garage.leave(true)
    local out, t2 = waitFor(job, function() return phase() == 'idle' end, 120)
    step('the shell leaves the garage', out and getPlayerVehicle(0) ~= nil, string.format('%.1f s', t2))
    job.sleep(3)
  end)
  if phase() ~= 'idle' then slrr_garage.abort() job.sleep(3) end

  ---------------------------------------------------------------- adding a garage and a shop where the car stands
  try('site helpers', function()
    local g, s = #sites.getSites(), #sites.getShops()
    slrr_garage.addGarageHere('WW Selftest Garage')
    slrr_garage.addShopHere('WW Selftest Shop', 'Everything')
    step('addGarageHere / addShopHere', #sites.getSites() == g + 1 and #sites.getShops() == s + 1, string.format('%d -> %d garages, %d -> %d shops', g, #sites.getSites(), s, #sites.getShops()))
  end)

  settings.set('expressMinutes', expressMinutes)
end

function M.onExtensionLoaded()
  core_jobsystem.create(function(job)
    local ok, err = xpcall(function() run(job) end, debug.traceback)
    if not ok then step('the test run itself', false, err) end
    R.finished = true
    save()
    local failed = 0
    for _, s in ipairs(R.steps) do
      if not s.ok then failed = failed + 1 end
    end
    if ui_message then ui_message(string.format('Wrench Works test: %d of %d checks passed. Details in settings/slrr_garage/test_results.json', #R.steps - failed, #R.steps), 20, 'wwtest') end
    extensions.unload('wwtest')
  end)
end

return M
