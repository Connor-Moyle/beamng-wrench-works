-- SLRR Garage: parts shown as real 3D objects.
-- Two jobs, both done with the stand-alone part models written by garageShapes:
--
-- * previews: the turning parts in the catalog and on the shelf. The UI leaves a hole where a
--   part goes and says where the hole is; a small copy of the part is held in front of the
--   camera at exactly that spot, on a card of its own, and turned a little every frame. It
--   is the game's own rendering, so it runs at the game's frame rate with the game's textures
--   and the car's paint. The game moves such objects a few frames late, so they cannot keep
--   up with a camera that is moving: while it moves the previews are put away ("parked") and
--   the UI closes its holes; they come back as soon as it rests.
--
-- * stand-ins: parts fitted in the garage that the car's physics model has not been rebuilt
--   with yet. Their models are simply placed on the car where the part will sit, so nothing
--   has to load until the car drives out.

local M = {}

local shapes = require('slrr/garageShapes')

local SHAPE_DIR = '/temp/slrr_garage/shapes/'
local PART_DEPTH = 0.36         -- metres in front of the camera
local CARD_DEPTH = 0.50
local TILT = math.rad(20)       -- how far the top of a part leans towards the viewer
local FILL = 1.05               -- share of its card a part may take up
local SETTLE_FRAMES = 8         -- frames an object needs to arrive where it was put

local model
local slots = {}                -- slot id -> { part, x, y, w, h, spin, obj, card, angle, centre, radius, none }
local standins = {}             -- key -> { obj, visible }
local colors = {}               -- the car's three paint colours, as the game writes them
local counter = 0
local onResult                  -- function(partName, hasModel)
local onLive                    -- function(readyIds): which holes the UI may open (nil = none)
local parked = false            -- the camera is moving: everything is hidden
local still = 0                 -- frames the camera has not moved
local lastPos, lastForward
local sentLive = ''
local cardPaths = {}

----------------------------------------------------------------------------------------------
-- objects

local function newObject(path)
  local o = createObject('TSStatic')
  o:setField('shapeName', 0, path)
  o:setField('useInstanceRenderData', 0, 'true')
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  for i, field in ipairs({ 'instanceColor', 'instanceColor1', 'instanceColor2' }) do
    if colors[i] then o:setField(field, 0, colors[i]) end
  end
  o.canSave = false
  counter = counter + 1
  o:registerObject('slrrGaragePart' .. counter)
  return o
end

local function drop(o)
  if o then pcall(function() o:delete() end) end
end

-- The card behind a preview: a square facing the camera, in a flat colour that takes no light.
-- In the catalog it is the dark page the part lies on; on the shelf it is see-through, tinted
-- like the shelf, so the part seems to stand in its slot.
local cardKinds = {
  book = { color = '0.011 0.011 0.013 1' },
  shelf = { color = '0.012 0.012 0.014 0.72', translucent = true },
}

local function cardShape(kind)
  if cardPaths[kind] then return cardPaths[kind] end
  local def = cardKinds[kind]
  local name = 'slrr_garage_card5_' .. kind
  if not scenetree.findObject(name) then
    local mat = createObject('Material')
    mat:setField('mapTo', 0, name)
    mat:setField('diffuseColor', 0, def.color)
    mat:setField('emissive', 0, '1')
    mat:setField('castShadows', 0, '0')
    if def.translucent then
      mat:setField('translucent', 0, '1')
      mat:setField('translucentBlendOp', 0, 'LerpAlpha')
      mat:setField('translucentZWrite', 0, '0')
    end
    mat.canSave = false
    mat:registerObject(name)
  end
  local path = SHAPE_DIR .. name .. '.dae'
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
  cardPaths[kind] = path
  return path
end

local function place(o, pos, forward, up, scale)
  local m = MatrixF(true)
  m:createOrientFromDirUp(forward, up)
  m:setPosition(pos)
  o:setTransform(m)
  o:setScale(scale)
end

----------------------------------------------------------------------------------------------
-- previews

local function dropSlot(slot)
  drop(slot.obj)
  drop(slot.card)
  slot.obj, slot.card, slot.age = nil, nil, nil
end

local function setHidden(slot, hidden)
  if slot.obj then slot.obj.hidden = hidden end
  if slot.card then slot.card.hidden = hidden end
end

-- tell the UI which previews are in place, so it opens a hole only where there is one
local function sendLive()
  local ids = {}
  if not parked then
    for id, slot in pairs(slots) do
      if slot.obj and (slot.age or 0) >= SETTLE_FRAMES then ids[#ids + 1] = id end
    end
    table.sort(ids)
  end
  local key = table.concat(ids, '|')
  if key == sentLive then return end
  sentLive = key
  if onLive then onLive(ids) end
end

-- the camera is about to move (or is moving): put the previews away at once
function M.park()
  still = 0
  if parked then return end
  parked = true
  for _, slot in pairs(slots) do
    setHidden(slot, true)
    slot.age = 0
  end
  sendLive()
end

local function loadSlot(slot)
  local shape = shapes.ofPart(model, slot.part)
  if not shape then
    slot.none = true
    if onResult then onResult(slot.part, false) end
    return
  end
  local o = newObject(shape.path)
  local box = o:getObjectBox()
  local lo, hi = box.minExtents, box.maxExtents
  slot.obj = o
  slot.centre = (vec3(lo) + vec3(hi)) * 0.5
  slot.radius = math.max(0.02, (vec3(hi) - vec3(lo)):length() * 0.5)
  slot.angle = slot.angle or 0.7
  slot.age = 0
  o.hidden = parked
  if onResult then onResult(slot.part, true) end
end

-- list: { { id, part, x, y, w, h, spin = true|false, card = 'book'|'shelf' }, ... } with the hole of each preview in
-- fractions of the screen. Anything not in the list is put away.
function M.setSlots(list)
  local seen = {}
  for _, entry in ipairs(list or {}) do
    if type(entry) == 'table' and entry.id and type(entry.part) == 'string' then
      local id = tostring(entry.id)
      local slot = slots[id]
      if slot and slot.part ~= entry.part then
        dropSlot(slot)
        slot = nil
      end
      if not slot then
        slot = { part = entry.part }
        slots[id] = slot
      end
      local x, y, w, h = tonumber(entry.x) or 0, tonumber(entry.y) or 0, tonumber(entry.w) or 0, tonumber(entry.h) or 0
      if x ~= slot.x or y ~= slot.y or w ~= slot.w or h ~= slot.h then slot.age = 0 end      -- it has to travel first
      slot.x, slot.y, slot.w, slot.h = x, y, w, h
      slot.spin = entry.spin and true or false
      slot.kind = entry.card == 'book' and 'book' or 'shelf'
      seen[id] = true
    end
  end
  for id, slot in pairs(slots) do
    if not seen[id] then
      dropSlot(slot)
      slots[id] = nil
    end
  end
end

-- cam: { pos, forward, right, up, tanX, tanY }   spinRate: radians per second, sign = direction
local function updateSlots(dt, cam, spinRate)
  if lastPos and ((cam.pos - lastPos):squaredLength() > 2.5e-7 or cam.forward:dot(lastForward) < 1 - 2e-9) then
    M.park()
  else
    still = still + 1
  end
  lastPos, lastForward = cam.pos, cam.forward
  if parked and still >= 4 then
    -- at rest again: bring them back (the UI opens its holes once they have arrived)
    parked = false
    for _, slot in pairs(slots) do setHidden(slot, false) end
  end
  local loaded = false
  for _, slot in pairs(slots) do
    if slot.obj and not parked then slot.age = (slot.age or 0) + 1 end
    if not slot.obj and not slot.none and not loaded and slot.w > 0 then
      loadSlot(slot)          -- one new model per frame, so a full page does not arrive as one jolt
      loaded = true
    end
    if slot.w > 0 and slot.h > 0 then
      local sx = ((slot.x + slot.w * 0.5) * 2 - 1) * cam.tanX
      local sy = (1 - (slot.y + slot.h * 0.5) * 2) * cam.tanY
      local ray = cam.forward + cam.right * sx + cam.up * sy
      if not slot.card then
        slot.card = newObject(cardShape(slot.kind))
        slot.card.hidden = parked
      end
      place(slot.card, cam.pos + ray * CARD_DEPTH, cam.forward, cam.up,
        vec3(slot.w * 2 * cam.tanX * CARD_DEPTH, 1, slot.h * 2 * cam.tanY * CARD_DEPTH))
      if slot.obj then
        if slot.spin then slot.angle = slot.angle + spinRate * dt end
        local half = math.min(slot.w * cam.tanX, slot.h * cam.tanY) * PART_DEPTH
        local s = half * FILL / slot.radius
        local z = (cam.up * math.cos(TILT) - cam.forward * math.sin(TILT)):normalized()
        local e2 = z:cross(cam.right):normalized()
        local y = cam.right * math.sin(slot.angle) + e2 * math.cos(slot.angle)
        local x = y:cross(z)
        local c = slot.centre
        place(slot.obj, cam.pos + ray * PART_DEPTH - (x * c.x + y * c.y + z * c.z) * s, y, z, vec3(s, s, s))
      end
    end
  end
  sendLive()
end

----------------------------------------------------------------------------------------------
-- stand-ins on the car

-- show the model at `path` on the car under `key`
function M.addStandin(key, path)
  local entry = standins[key]
  if entry then drop(entry.obj) end
  standins[key] = { obj = newObject(path), visible = true }
end

function M.setStandinVisible(key, visible)
  local entry = standins[key]
  if not entry or entry.visible == visible then return end
  entry.visible = visible
  entry.obj.hidden = not visible
end

function M.removeStandin(key)
  local entry = standins[key]
  if entry then drop(entry.obj) end
  standins[key] = nil
end

function M.clearStandins()
  for _, entry in pairs(standins) do drop(entry.obj) end
  standins = {}
end

-- frame: the car's own coordinate system in the world { origin, y, z } (see garagePicker)
local function updateStandins(frame)
  if not frame then return end
  for _, entry in pairs(standins) do
    if entry.visible then place(entry.obj, frame.origin, frame.y, frame.z, vec3(1, 1, 1)) end
  end
end

----------------------------------------------------------------------------------------------
-- public

function M.setup(_model, callback, liveCallback)
  if _model ~= model then M.clear() end
  model, onResult, onLive = _model, callback, liveCallback
  sentLive = ''
end

-- take the paint off the car: parts in body colour are shown in it
function M.setPaintFrom(veh)
  if not veh then return end
  colors = { veh:getField('color', 0), veh:getField('colorPalette0', 0), veh:getField('colorPalette1', 0) }
  local function repaint(o)
    if not o then return end
    for i, field in ipairs({ 'instanceColor', 'instanceColor1', 'instanceColor2' }) do
      if colors[i] and colors[i] ~= '' then o:setField(field, 0, colors[i]) end
    end
  end
  for _, slot in pairs(slots) do repaint(slot.obj) end
  for _, entry in pairs(standins) do repaint(entry.obj) end
end

function M.update(dt, cam, spinRate, frame)
  if cam then updateSlots(dt, cam, spinRate or 0) end
  updateStandins(frame)
end

function M.hasStandins() return next(standins) ~= nil end

function M.clear()
  for _, slot in pairs(slots) do dropSlot(slot) end
  slots = {}
  parked, still, lastPos, lastForward, sentLive = false, 0, nil, nil, ''
  M.clearStandins()
end

return M
