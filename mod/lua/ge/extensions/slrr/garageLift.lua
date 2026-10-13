-- Wrench Works: the car lift.
-- A two-post lift stands at the parking spot of every garage. Its model is made here, out of
-- plain boxes, and written once to /temp. The car drives in between the posts; when it has
-- stopped, the four arms swing in under its sills, and when the lift is used they carry it
-- up. The lifting itself is done by forces on the car (see slrrGarageVeh.lua); this module
-- keeps the arms under it so that it looks carried.

local M = {}

local SHAPE_DIR = '/temp/slrr_garage/shapes/'
local MATERIALS = '/art/slrr_garage/main.materials.json'
local VERSION = 2

local POST_X = 1.74             -- posts stand this far either side of the car's centre line
local ARM_X = 1.50              -- arm pivots
local ARM_Y = 0.16              -- ... this far ahead of and behind the posts
local ARM_LENGTH = 1.18
local ARM_SWING = math.rad(54)  -- how far an arm turns in from pointing along the car
local REST_HEIGHT = 0.125       -- top of the pads with the lift all the way down
local SPEED = 0.55              -- m/s, the same as the car is raised at
local SWING_TIME = 0.9

local objects = {}              -- everything created, for clearing
local carriages, arms = {}, {}
local origin, forward, right, up
local padHeight, padTarget = REST_HEIGHT, REST_HEIGHT
local swing, swingTarget = 0, 0          -- 0 = arms stowed along the car, 1 = under the sills
local dirty = false
local counter = 0

----------------------------------------------------------------------------------------------
-- models out of boxes

-- boxes: { { x1, y1, z1, x2, y2, z2, material }, ... }  -> text of a .dae
local function boxesToDae(boxes)
  local positions, groups, order = {}, {}, {}
  local normals = { '1 0 0', '-1 0 0', '0 1 0', '0 -1 0', '0 0 1', '0 0 -1' }
  -- corners of each face, counter-clockwise seen from outside, as picks of (x, y, z) from the two corners
  local faces = {
    { { 2, 1, 1 }, { 2, 2, 1 }, { 2, 2, 2 }, { 2, 1, 2 } },
    { { 1, 2, 1 }, { 1, 1, 1 }, { 1, 1, 2 }, { 1, 2, 2 } },
    { { 2, 2, 1 }, { 1, 2, 1 }, { 1, 2, 2 }, { 2, 2, 2 } },
    { { 1, 1, 1 }, { 2, 1, 1 }, { 2, 1, 2 }, { 1, 1, 2 } },
    { { 1, 1, 2 }, { 2, 1, 2 }, { 2, 2, 2 }, { 1, 2, 2 } },
    { { 1, 2, 1 }, { 2, 2, 1 }, { 2, 1, 1 }, { 1, 1, 1 } },
  }
  local count = 0
  for _, b in ipairs(boxes) do
    local xs, ys, zs = { math.min(b[1], b[4]), math.max(b[1], b[4]) }, { math.min(b[2], b[5]), math.max(b[2], b[5]) }, { math.min(b[3], b[6]), math.max(b[3], b[6]) }
    local list = groups[b[7]]
    if not list then list = {}; groups[b[7]] = list; order[#order + 1] = b[7] end
    for f, face in ipairs(faces) do
      local base = count
      for _, c in ipairs(face) do
        positions[#positions + 1] = string.format('%.4f %.4f %.4f', xs[c[1]], ys[c[2]], zs[c[3]])
        count = count + 1
      end
      local n = f - 1
      list[#list + 1] = string.format('%d %d %d %d %d %d %d %d %d %d %d %d', base, n, base + 1, n, base + 2, n, base, n, base + 2, n, base + 3, n)
    end
  end
  local out = {
    '<?xml version="1.0" encoding="utf-8"?>',
    '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">',
    '<asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>',
    '<library_effects><effect id="fx"><profile_COMMON><technique sid="common"><phong><diffuse><color>1 1 1 1</color></diffuse></phong></technique></profile_COMMON></effect></library_effects>',
    '<library_materials>',
  }
  for _, name in ipairs(order) do out[#out + 1] = string.format('<material id="%s-material" name="%s"><instance_effect url="#fx"/></material>', name, name) end
  out[#out + 1] = '</library_materials><library_geometries><geometry id="mesh" name="mesh"><mesh>'
  out[#out + 1] = string.format('<source id="pos"><float_array id="pos-array" count="%d">%s</float_array><technique_common><accessor source="#pos-array" count="%d" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>', count * 3, table.concat(positions, ' '), count)
  out[#out + 1] = string.format('<source id="nrm"><float_array id="nrm-array" count="18">%s</float_array><technique_common><accessor source="#nrm-array" count="6" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>', table.concat(normals, ' '))
  out[#out + 1] = '<vertices id="vtx"><input semantic="POSITION" source="#pos"/></vertices>'
  local binds = {}
  for _, name in ipairs(order) do
    local list = groups[name]
    out[#out + 1] = string.format('<triangles material="%s-material" count="%d"><input semantic="VERTEX" source="#vtx" offset="0"/><input semantic="NORMAL" source="#nrm" offset="1"/><p>%s</p></triangles>', name, #list * 2, table.concat(list, ' '))
    binds[#binds + 1] = string.format('<instance_material symbol="%s-material" target="#%s-material"/>', name, name)
  end
  out[#out + 1] = '</mesh></geometry></library_geometries>'
  out[#out + 1] = '<library_visual_scenes><visual_scene id="Scene" name="Scene"><node id="slrrlift" name="slrrlift" type="NODE"><instance_geometry url="#mesh" name="slrrlift"><bind_material><technique_common>' .. table.concat(binds) .. '</technique_common></bind_material></instance_geometry></node></visual_scene></library_visual_scenes>'
  out[#out + 1] = '<scene><instance_visual_scene url="#Scene"/></scene></COLLADA>'
  return table.concat(out, '\n')
end

local function shape(name, boxes)
  local path = SHAPE_DIR .. 'lift_v' .. VERSION .. '_' .. name .. '.dae'
  if not FS:fileExists(path) then writeFile(path, boxesToDae(boxes)) end
  return path
end

local PAINT, STEEL, RUBBER, WARN = 'slrr_lift_paint', 'slrr_lift_steel', 'slrr_lift_rubber', 'slrr_lift_warn'

-- both posts with their feet and the plate across the floor between them
local function postsShape()
  local boxes = { { -POST_X, -0.17, 0, POST_X, 0.17, 0.022, STEEL } }
  for _, side in ipairs({ -1, 1 }) do
    local x = side * POST_X
    boxes[#boxes + 1] = { x - 0.13, -0.15, 0, x + 0.13, 0.15, 2.85, PAINT }             -- column
    boxes[#boxes + 1] = { x - 0.30, -0.34, 0, x + 0.30, 0.34, 0.035, STEEL }            -- foot
    boxes[#boxes + 1] = { x - 0.15, -0.17, 2.85, x + 0.15, 0.17, 2.93, STEEL }          -- cap
    boxes[#boxes + 1] = { x - side * 0.135, -0.05, 0.25, x - side * 0.15, 0.05, 2.7, STEEL }   -- guide rail
    boxes[#boxes + 1] = { x + side * 0.13, -0.11, 0.9, x + side * 0.24, 0.11, 1.35, WARN }     -- motor unit
  end
  return shape('posts', boxes)
end

-- the block that runs up one post and carries two arms; its origin is at pad height, on the post
local function carriageShape()
  return shape('carriage', {
    { -0.20, -0.21, -0.09, 0.02, 0.21, 0.34, WARN },
    { -0.30, -0.26, -0.085, -0.16, 0.26, -0.005, STEEL },
  })
end

-- one arm: pivot at the origin, pointing along +Y, pad on top at the far end (top of pad = z 0)
local function armShape()
  return shape('arm', {
    { -0.055, -0.07, -0.085, 0.055, ARM_LENGTH * 0.55, -0.02, STEEL },
    { -0.042, ARM_LENGTH * 0.45, -0.078, 0.042, ARM_LENGTH, -0.027, STEEL },
    { -0.075, ARM_LENGTH - 0.09, -0.027, 0.075, ARM_LENGTH + 0.06, 0, RUBBER },
  })
end

----------------------------------------------------------------------------------------------
-- objects

local function newObject(path)
  local o = createObject('TSStatic')
  o:setField('shapeName', 0, path)
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  counter = counter + 1
  o:registerObject('slrrGarageLift' .. counter)
  objects[#objects + 1] = o
  return o
end

local function place(o, pos, dir)
  local m = MatrixF(true)
  m:createOrientFromDirUp(dir, up)
  m:setPosition(pos)
  o:setTransform(m)
end

local function at(x, y, z)
  return origin + right * x + forward * y + up * z
end

local function layout()
  for _, c in ipairs(carriages) do
    -- the model has its body on the -x side of its origin; turned round for the left post
    place(c.obj, at(c.side * (POST_X - 0.13), 0, padHeight), forward * c.side)
  end
  for _, a in ipairs(arms) do
    -- stowed, an arm points along the car (ahead for the front pair, back for the rear pair);
    -- swung in, it has turned towards the car's centre line
    local angle = ARM_SWING * swing
    local dir = forward * (a.fore * math.cos(angle)) - right * (a.side * math.sin(angle))
    place(a.obj, at(a.side * ARM_X, a.fore * ARM_Y, padHeight), dir)
  end
end

----------------------------------------------------------------------------------------------
-- public

-- put a lift at a garage's parking spot. dir: the garage's axis.
function M.setup(spot, dir)
  M.clear()
  if FS:fileExists(MATERIALS) and not scenetree.findObject(PAINT) then loadJsonMaterialsFile(MATERIALS) end
  origin, forward, up = vec3(spot), vec3(dir):normalized(), vec3(0, 0, 1)
  right = forward:cross(up):normalized()
  padHeight, padTarget, swing, swingTarget = REST_HEIGHT, REST_HEIGHT, 0, 0
  place(newObject(postsShape()), origin, forward)
  for _, side in ipairs({ -1, 1 }) do
    carriages[#carriages + 1] = { obj = newObject(carriageShape()), side = side }
    for _, fore in ipairs({ -1, 1 }) do
      arms[#arms + 1] = { obj = newObject(armShape()), side = side, fore = fore }
    end
  end
  layout()
end

-- swing the arms in under the car, or back out of its way
function M.setArms(under, instantly)
  swingTarget = under and 1 or 0
  if instantly then swing = swingTarget end
  dirty = true
end

-- how high the top of the pads should be above the floor (nil = all the way down)
function M.setPadHeight(height, instantly)
  padTarget = math.max(REST_HEIGHT, height or REST_HEIGHT)
  if instantly then padHeight = padTarget end
  dirty = true
end

function M.getPadHeight() return padHeight end
function M.restHeight() return REST_HEIGHT end
function M.isMoving() return padHeight ~= padTarget or swing ~= swingTarget end

function M.update(dt)
  if not origin or not (dirty or M.isMoving()) then return end
  dirty = false
  dt = math.min(dt or 0.016, 0.05)
  if padHeight < padTarget then padHeight = math.min(padTarget, padHeight + SPEED * dt)
  elseif padHeight > padTarget then padHeight = math.max(padTarget, padHeight - SPEED * dt) end
  if swing < swingTarget then swing = math.min(swingTarget, swing + dt / SWING_TIME)
  elseif swing > swingTarget then swing = math.max(swingTarget, swing - dt / SWING_TIME) end
  layout()
end

function M.clear()
  for _, o in ipairs(objects) do pcall(function() o:delete() end) end
  objects, carriages, arms = {}, {}, {}
  origin = nil
end

return M
