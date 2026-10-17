-- Wrench Works / Street Legal: a picture of every part the shops can list (T41). Runs in the game's GE Lua, in a level, with nothing else going on:
--   node bng.js run_lua @tools/part_shots.lua        (after setting the PART_SHOTS table, see below)
-- For each stock model it spawns the car (the car's materials must be loaded for the parts to wear their textures), builds each part's own 3D model
-- with slrr/garageShapes (the garage's catalog method), hangs it in the air 40 m above the car in front of a flat card, and takes TWO screenshots
-- of it from a fixed 3/4 view: once with a black card behind it, once with a white one. tools/part_shots.py turns each pair into a transparent
-- 128x128 PNG (difference matting, so there is no halo and glass keeps its see-through). Nothing here touches the player's career or save.
--
--   PART_SHOTS = {
--     models = { 'covet' },     which models (default: every stock car and truck found on this PC; mods are skipped)
--     count = true,             only count the parts (no spawn, no shots): how many, how many have a 3D model, how many are new after the earlier models
--     minValue = 150,           only parts worth at least this much (default 150: the cheap bits stay with their category icons)
--     limit = 20,               stop after this many parts (a trial)
--     only = { 'covet_exhaust_sport' },   just these parts
--     force = true,             shoot again parts whose raw pair or PNG exists
--   }
--   return PART_SHOTS_STATUS    read it afterwards ('running <model> n/m', 'done ...', 'stopped'); set PART_SHOTS_STOP = true to stop early
-- Output (the game's user folder): settings/street_legal/part_shots/raw/<part>_b.png and _w.png, index.json (part -> model, name), summary.json.
-- Resumable: a part whose pair (or PNG) exists is skipped, so a stopped run carries on where it left off.

local TAG = 'part_shots'
local cfg = rawget(_G, 'PART_SHOTS')
if type(cfg) ~= 'table' then cfg = {} end
local OUT = 'settings/street_legal/part_shots/'
local RAW = OUT .. 'raw/'
local CARD_DIR = '/temp/slrr_part_shots/'
local FOV = 30
local FILL = 0.5                                       -- the part's bounding sphere takes this much of the picture's height (the PC step crops to the part)
local SKY = 40                                         -- metres above the car the parts hang
local TEXTURES = 0.4                                   -- seconds a new part gets to load its textures
local SHOT_WAIT = 4                                    -- seconds to wait for a screenshot file

local jbeamIO = require('jbeam/io')
local shapes = require('slrr/garageShapes')
local catalog = require('slrr/garageCatalog')

-- the markets list wheels, tyres and hubs too, but they keep their category icons (and generic parts shared by every model, from /vehicles/common)
local SKIP_SUBS = { rims_f = true, rims_r = true, tyres_f = true, tyres_r = true, hubs = true }

rawset(_G, 'PART_SHOTS_STOP', false)
rawset(_G, 'PART_SHOTS_STATUS', 'starting')

local function status(text) rawset(_G, 'PART_SHOTS_STATUS', text) log('I', TAG, text) end

-- a jbeam name is a string, or a translation table { txt = ... }: always a string
local function textOf(v)
  if type(v) == 'string' then return v end
  if type(v) == 'table' then return textOf(v.txt) or textOf(v.val) or textOf(v[1]) end
  return nil
end

-- the part's bounding box from its vertices, without the stray ones: the 2nd to the 98th percentile on each axis (a few far-off vertices of a
-- mesh would make the part a speck in the picture). Returns lo, hi (vec3).
local function bounds(verts)
  local n = math.floor(#verts / 3)
  local axes = { {}, {}, {} }
  for i = 0, n - 1 do
    for a = 1, 3 do axes[a][#axes[a] + 1] = verts[i * 3 + a] end
  end
  local lo, hi = {}, {}
  for a = 1, 3 do
    table.sort(axes[a])
    local cut = n >= 100 and math.floor(n * 0.02) or 0
    lo[a], hi[a] = axes[a][1 + cut], axes[a][n - cut]
  end
  return vec3(lo[1], lo[2], lo[3]), vec3(hi[1], hi[2], hi[3])
end

local function safe(name) return (tostring(name):gsub('[^%w_%-]', '_')) end

-- which models: those asked for, else every stock car and truck
local function stockModels()
  local out = {}
  local ok, list = pcall(function() return core_vehicles.getModelList().models end)
  if not ok or type(list) ~= 'table' then return out end
  for name, m in pairs(list) do
    local t = tostring(m.Type or '')
    local real = tostring(FS:getFileRealPath('/vehicles/' .. name .. '/info.json') or ''):lower():gsub('\\', '/')
    if (t == 'Car' or t == 'Truck') and not real:find('/mods/', 1, true) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- the parts a shop can list (the same filter as sl/classifieds partsOf) that have a mesh to draw: { part, name, slot, rows }
local function partsOf(model, ctx)
  local list = {}
  shapes.setup(function(partName)
    local ok, part, file = pcall(jbeamIO.getPart, ctx, partName)
    if ok then return part, file end
  end, nil)
  for name, desc in pairs(jbeamIO.getAvailableParts(ctx) or {}) do
    if not desc.isAuxiliary then
      local part, file = jbeamIO.getPart(ctx, name)
      local info = part and part.information or {}
      local slot = part and (type(part.slotType) == 'table' and part.slotType[1] or part.slotType)
      local _, sub = catalog.classify(slot or '', name, nil)
      local shared = type(file) == 'string' and file:find('^/vehicles/common/') ~= nil
      if (tonumber(info.value) or 0) >= (tonumber(rawget(_G, "PART_SHOTS") and PART_SHOTS.minValue) or 150) and type(slot) == 'string' and slot ~= 'main' and not SKIP_SUBS[sub] and not shared then
        local rows = shapes.rowsOfPart(name)
        list[#list + 1] = { part = name, name = info.name or desc.description or name, slot = slot, rows = rows }
      end
    end
  end
  table.sort(list, function(a, b) return a.part < b.part end)
  return list
end

-- two parts that are drawn with the same meshes look the same (colour and engine variants, left and right copies of one mesh...): one picture
-- serves them all. A part's signature is its sorted mesh names.
local function signature(rows)
  local names = {}
  for _, row in ipairs(rows) do names[#names + 1] = row.mesh end
  table.sort(names)
  return table.concat(names, '|')
end

local function ctxFor(model) return jbeamIO.startLoading({ '/vehicles/' .. model .. '/', '/vehicles/common/' }) end

----------------------------------------------------------------------------------------------
-- the black and white cards

local function cardShape(kind, color)
  local name = 'slrr_part_shot_card_' .. kind
  if not scenetree.findObject(name) then
    local mat = createObject('Material')
    mat:setField('mapTo', 0, name)
    mat:setField('diffuseColor', 0, color)
    mat:setField('emissive', 0, '1')
    mat:setField('castShadows', 0, '0')
    mat.canSave = false
    mat:registerObject(name)
  end
  local path = CARD_DIR .. name .. '.dae'
  if not FS:fileExists(path) then
    writeFile(path, table.concat({
      '<?xml version="1.0" encoding="utf-8"?>',
      '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">',
      '<asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>',
      '<library_effects><effect id="card-fx"><profile_COMMON><technique sid="common"><phong><diffuse><color>0 0 0 1</color></diffuse></phong></technique></profile_COMMON></effect></library_effects>',
      '<library_materials><material id="' .. name .. '-material" name="' .. name .. '"><instance_effect url="#card-fx"/></material></library_materials>',
      '<library_geometries><geometry id="card-mesh" name="card"><mesh>',
      '<source id="card-pos"><float_array id="card-pos-array" count="12">-0.5 0 -0.5 0.5 0 -0.5 0.5 0 0.5 -0.5 0 0.5</float_array>',
      '<technique_common><accessor source="#card-pos-array" count="4" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>',
      '<source id="card-nrm"><float_array id="card-nrm-array" count="3">0 -1 0</float_array>',
      '<technique_common><accessor source="#card-nrm-array" count="1" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>',
      '<vertices id="card-vtx"><input semantic="POSITION" source="#card-pos"/></vertices>',
      '<triangles material="' .. name .. '-material" count="4"><input semantic="VERTEX" source="#card-vtx" offset="0"/><input semantic="NORMAL" source="#card-nrm" offset="1"/>',
      '<p>0 0 1 0 2 0 0 0 2 0 3 0 0 0 2 0 1 0 0 0 3 0 2 0</p></triangles>',
      '</mesh></geometry></library_geometries>',
      '<library_visual_scenes><visual_scene id="Scene" name="Scene"><node id="slrrcard" name="slrrcard" type="NODE">',
      '<instance_geometry url="#card-mesh" name="slrrcard"><bind_material><technique_common><instance_material symbol="' .. name .. '-material" target="#' .. name .. '-material"/></technique_common></bind_material></instance_geometry>',
      '</node></visual_scene></library_visual_scenes>',
      '<scene><instance_visual_scene url="#Scene"/></scene>',
      '</COLLADA>',
    }, '\n'))
  end
  return path
end

local counter = 0
local function newObject(path, colors)
  local o = createObject('TSStatic')
  o:setField('shapeName', 0, path)
  o:setField('useInstanceRenderData', 0, 'true')
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  for i, field in ipairs({ 'instanceColor', 'instanceColor1', 'instanceColor2' }) do
    if colors and colors[i] and colors[i] ~= '' then o:setField(field, 0, colors[i]) end
  end
  o.canSave = false
  counter = counter + 1
  o:registerObject('slrrPartShot' .. counter)
  return o
end

local function drop(o) if o then pcall(function() o:delete() end) end end

local function place(o, pos, forward, up, scale)
  local m = MatrixF(true)
  m:createOrientFromDirUp(forward, up)
  m:setPosition(pos)
  o:setTransform(m)
  o:setScale(scale)
end

----------------------------------------------------------------------------------------------
-- the run

local function exists(path) local f = io.open(path, 'rb') if f then f:close() return true end return false end

local function readIndex() return jsonReadFile(OUT .. 'index.json') or {} end

local models = type(cfg.models) == 'table' and cfg.models or stockModels()
if #models == 0 then return 'no models: is a level loaded? (core_vehicles.getModelList gave none)' end

if cfg.count then
  local seen, lines, total, withMesh, fresh = {}, {}, 0, 0, 0
  for _, model in ipairs(models) do
    local ok, list = pcall(partsOf, model, ctxFor(model))
    if ok then
      local n, m, f = #list, 0, 0
      for _, p in ipairs(list) do
        if #p.rows > 0 then
          m = m + 1
          local sig = signature(p.rows)
          if not seen[sig] then seen[sig] = true f = f + 1 end
        end
      end
      total, withMesh, fresh = total + n, withMesh + m, fresh + f
      lines[#lines + 1] = string.format('%s %d parts, %d with a 3D model, %d new', model, n, m, f)
    else
      lines[#lines + 1] = model .. ' failed: ' .. tostring(list)
    end
  end
  lines[#lines + 1] = string.format('TOTAL %d models, %d parts, %d with a 3D model, %d to shoot (one picture for every set of parts drawn with the same meshes)', #models, total, withMesh, fresh)
  for _, l in ipairs(lines) do log('I', TAG, l) end
  rawset(_G, 'PART_SHOTS_STATUS', 'counted')
  return table.concat(lines, '\n')
end

if not getCurrentLevelIdentifier() then return 'load a level first' end
if not FS:directoryExists(RAW) then FS:directoryCreate(RAW, true) end
if not FS:directoryExists(CARD_DIR) then FS:directoryCreate(CARD_DIR, true) end

local player = getPlayerVehicle(0)
local anchor = (player and player:getPosition() or core_camera.getPosition()) + vec3(25, 0, 0)

core_jobsystem.create(function(job)
  local uiWas
  local failures, aliased = {}, 0
  local started = os.time()
  local summaryOf
  local ok, err = pcall(function()
  -- the game's own UI (the camera help, the apps bar) must not be in the pictures
  pcall(function() extensions.load('ui_visibility') uiWas = ui_visibility.get() ui_visibility.set(false) end)
  local index = readIndex()
  local shot, skipped, failed, seen = 0, 0, 0, {}
  local canon = {}            -- signature -> the part whose picture serves every part drawn the same
  for name, entry in pairs(index) do if type(entry) == 'table' and entry.sig and not entry.alias then canon[entry.sig] = name end end
  local only
  if type(cfg.only) == 'table' then only = {} for _, p in ipairs(cfg.only) do only[p] = true end end
  local black = newObject(cardShape('black', '0 0 0 1'))
  local white = newObject(cardShape('white', '1 1 1 1'))
  black.hidden, white.hidden = true, true
  commands.setFreeCamera()
  job.sleep(0.5)
  pcall(function() core_environment.setTimeOfDay({ time = 0.15, play = false }) end)
  pcall(function() core_camera.setFOV(0, FOV) end)
  local stage = anchor + vec3(0, 0, SKY)

  for mi, model in ipairs(models) do
    if rawget(_G, 'PART_SHOTS_STOP') then break end
    local ctx = ctxFor(model)
    local okList, list = pcall(partsOf, model, ctx)
    if not okList then log('W', TAG, model .. ': listing failed: ' .. tostring(list)) list = {} end
    local todo = {}
    for _, p in ipairs(list) do
      local done = exists(OUT .. safe(p.part) .. '.png') or (exists(RAW .. safe(p.part) .. '_b.png') and exists(RAW .. safe(p.part) .. '_w.png'))
      local sig = #p.rows > 0 and signature(p.rows) or nil
      p.sig = sig
      if sig and canon[sig] and canon[sig] ~= p.part and not cfg.force then
        index[p.part] = { model = model, name = textOf(p.name) or p.part, slot = p.slot, alias = canon[sig] }      -- drawn like a part that has (or gets) a picture
        aliased = aliased + 1
      elseif sig and done and not canon[sig] then
        canon[sig] = p.part
        index[p.part] = { model = model, name = textOf(p.name) or p.part, slot = p.slot, sig = sig }
        skipped = skipped + 1
      elseif sig and not seen[p.part] and (not only or only[p.part]) and (cfg.force or not done) then
        seen[p.part] = true
        canon[sig] = canon[sig] or p.part
        todo[#todo + 1] = p
      elseif sig then skipped = skipped + 1 end
    end
    if cfg.limit then while #todo > cfg.limit - shot do todo[#todo] = nil end end
    if #todo > 0 then
      local veh = core_vehicles.spawnNewVehicle(model, { pos = anchor, rot = quat(0, 0, 0, 1), autoEnterVehicle = false })
      job.sleep(3)
      -- the camera stays a free camera, but the spawn may have taken it
      commands.setFreeCamera()
      local colors = veh and { veh:getField('color', 0), veh:getField('colorPalette0', 0), veh:getField('colorPalette1', 0) } or {}
      for i, p in ipairs(todo) do
        if rawget(_G, 'PART_SHOTS_STOP') then break end
        status(string.format('running %s %d/%d (%s)', model, i, #todo, p.part))
        local shape = shapes.get(model, p.part, p.rows, true)
        local verts = shape and shape.verts
        if shape and verts and #verts >= 3 then
          local lo, hi = bounds(verts)
          local centre = (lo + hi) * 0.5
          local radius = math.max(0.03, (hi - lo):length() * 0.5)
          local obj = newObject(shape.path, colors)
          place(obj, stage - centre, vec3(0, 1, 0), vec3(0, 0, 1), vec3(1, 1, 1))
          -- the outer face: front-right-above for a part at the front right, and so on (the car's front is -Y, its right +X)
          local dir = vec3(centre.x >= -0.15 and 0.8 or -0.8, centre.y <= 0 and -1 or 1, 0.55):normalized()
          local dist = radius / (math.tan(math.rad(FOV / 2)) * FILL)
          local camPos = stage + dir * dist
          local look = (stage - camPos):normalized()
          local rot = quatFromDir(look, vec3(0, 0, 1))
          core_camera.setPosRot(0, camPos.x, camPos.y, camPos.z, rot.x, rot.y, rot.z, rot.w)
          for _, card in ipairs({ black, white }) do
            place(card, stage + dir * -(radius * 1.5), look, vec3(0, 0, 1), vec3(radius * 60, 1, radius * 60))
          end
          job.sleep(TEXTURES)
          local okBoth = true
          for _, pass in ipairs({ { black, white, '_b' }, { white, black, '_w' } }) do
            pass[1].hidden, pass[2].hidden = false, true
            job.sleep(0.15)
            local file = RAW .. safe(p.part) .. pass[3]
            pcall(function() os.remove(file .. '.png') end)
            local id = createScreenshot2({ filename = file, writeJPG = false, superSampling = 1, rescaleFactor = 1 })
            local waited = 0
            while (not id or id == 0 or not exists(file .. '.png')) and waited < SHOT_WAIT do job.sleep(0.05) waited = waited + 0.05 end
            if waited >= SHOT_WAIT then okBoth = false failures[#failures + 1] = { part = p.part, why = 'no screenshot file within ' .. SHOT_WAIT .. ' s (' .. pass[3] .. ')' } break end
            job.sleep(0.1)                                  -- the file is written in the background: let it finish
          end
          black.hidden, white.hidden = true, true
          drop(obj)
          if okBoth then
            shot = shot + 1
            index[p.part] = { model = model, name = textOf(p.name) or p.part, slot = p.slot, sig = p.sig,
              size = string.format('%.2f x %.2f x %.2f m', hi.x - lo.x, hi.y - lo.y, hi.z - lo.z) }
          else
            failed = failed + 1
            log('W', TAG, 'no screenshot for ' .. p.part)
          end
        else
          failed = failed + 1
          local names = {}
          for _, row in ipairs(p.rows) do if #names < 3 then names[#names + 1] = row.mesh end end
          local why = shape == false and ('no mesh found in the vehicle .dae files for: ' .. table.concat(names, ', ')) or 'the model has no vertices'
          failures[#failures + 1] = { part = p.part, why = why }
          log('W', TAG, 'no 3D model for ' .. p.part .. ': ' .. why)
        end
      end
      jsonWriteFile(OUT .. 'index.json', index, true)
      if veh then pcall(function() veh:delete() end) end
      job.sleep(0.5)
    end
  end

  drop(black) drop(white)
  summaryOf = function() return shot, skipped, failed end
  end)
  if not ok then failures[#failures + 1] = { part = '(the run)', why = tostring(err) } log('E', TAG, 'the run failed: ' .. tostring(err)) end
  if uiWas ~= nil then pcall(function() ui_visibility.set(uiWas) end) end         -- the UI comes back
  pcall(function() commands.setGameCamera() end)
  local shot, skipped, failed = 0, 0, 0
  if summaryOf then shot, skipped, failed = summaryOf() end
  local seconds = os.time() - started
  local summary = { models = models, shot = shot, aliased = aliased, alreadyDone = skipped, failed = failed, failures = failures, seconds = seconds,
    secondsPerPart = shot > 0 and seconds / shot or 0, stopped = rawget(_G, 'PART_SHOTS_STOP') == true, userFolder = FS:getUserPath() }
  jsonWriteFile(OUT .. 'summary.json', summary, true)
  status(string.format('done: %d shot, %d share the picture of another part, %d done before, %d failed (reasons in summary.json), %.0f s (%.2f s a part), raw pairs in %s%s', shot, aliased, skipped,
    failed, seconds, summary.secondsPerPart, FS:getUserPath(), RAW))
end)
return 'started ' .. #models .. ' model(s); read PART_SHOTS_STATUS'
