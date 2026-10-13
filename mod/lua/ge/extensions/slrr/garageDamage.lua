-- SLRR Garage: bookkeeping for damage that has to survive vehicle rebuilds.
-- The vehicle side (lua/vehicle/extensions/slrrGarageVeh.lua) records and re-applies bent and
-- broken beams. This module decides WHICH records belong to the car right now: when a part is
-- taken off, its records travel with it to the shelf; when it is fitted again they come back.
--
-- A record names the part it belongs to by part path ("/body/hood/hood_race"), so fitting a
-- fresh part in the same slot never inherits the old part's dents.

local M = {}

local car = { nodes = {}, beams = {} }

local function startsWith(s, prefix)
  return type(s) == 'string' and s:sub(1, #prefix) == prefix
end

local function empty() return { nodes = {}, beams = {} } end

function M.clear()
  car = empty()
end

-- the full record as captured from the vehicle
function M.setCar(data)
  car = empty()
  if type(data) ~= 'table' then return end
  for _, rec in ipairs(data.nodes or {}) do car.nodes[#car.nodes + 1] = rec end
  for _, rec in ipairs(data.beams or {}) do car.beams[#car.beams + 1] = rec end
end

local function split(list, belongs)
  local keep, taken = {}, {}
  for _, rec in ipairs(list) do
    if belongs(rec) then taken[#taken + 1] = rec else keep[#keep + 1] = rec end
  end
  return keep, taken
end

-- lift a part's damage out of the car's record (the part is going to the shelf)
function M.takePart(slotPath)
  local out = empty()
  car.nodes, out.nodes = split(car.nodes, function(rec) return startsWith(rec.p, slotPath) end)
  -- a beam between the part and its neighbour is the part's mounting; it goes with the part
  car.beams, out.beams = split(car.beams, function(rec) return startsWith(rec.pa, slotPath) or startsWith(rec.pb, slotPath) end)
  if #out.beams == 0 then return nil end
  return out
end

-- a shelf part goes back on the car and brings its damage along
function M.addPart(damage)
  if type(damage) ~= 'table' then return end
  for _, rec in ipairs(damage.nodes or {}) do car.nodes[#car.nodes + 1] = rec end
  for _, rec in ipairs(damage.beams or {}) do car.beams[#car.beams + 1] = rec end
end

-- repair: forget the damage of one part, or of the whole car
function M.repairPart(slotPath)
  return M.takePart(slotPath) ~= nil
end

function M.repairAll()
  local had = #car.beams > 0
  car = empty()
  return had
end

function M.countPart(slotPath)
  local n = 0
  for _, rec in ipairs(car.beams) do
    if startsWith(rec.pa, slotPath) or startsWith(rec.pb, slotPath) then n = n + 1 end
  end
  return n
end

function M.countAll()
  return #car.beams
end

-- damage records that belong to exactly this part (not to what is bolted to it)
function M.countOwn(partPath)
  local n = 0
  for _, rec in ipairs(car.beams) do
    if rec.pa == partPath or rec.pb == partPath then n = n + 1 end
  end
  return n
end

function M.count(damage)
  return type(damage) == 'table' and type(damage.beams) == 'table' and #damage.beams or 0
end

-- everything to put back after a rebuild: the car's own damage plus that of shelf parts that
-- are loaded (hidden) on the car, so they are still bent when they are shown again
function M.buildApply(shelfDamages)
  local out = empty()
  for _, rec in ipairs(car.nodes) do out.nodes[#out.nodes + 1] = rec end
  for _, rec in ipairs(car.beams) do out.beams[#out.beams + 1] = rec end
  for _, damage in ipairs(shelfDamages or {}) do
    for _, rec in ipairs(damage.nodes or {}) do out.nodes[#out.nodes + 1] = rec end
    for _, rec in ipairs(damage.beams or {}) do out.beams[#out.beams + 1] = rec end
  end
  return out
end

return M
