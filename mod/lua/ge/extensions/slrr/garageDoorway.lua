-- Wrench Works: where a garage's doorway is (pure geometry, tested by tools/doorway_test.js).
-- depth: metres along the way in, from the door (negative: outside); across: sideways from the door's middle.
local M = {}

-- a car: its nose reaching the door
function M.carZone(depth, across)
  return depth > -1.6 and depth < 1.2 and across < 2.6
end

-- a walker: anywhere in front of and in the door, any direction, standing or walking, and as wide as the garage
function M.footZone(depth, across, halfWidth)
  return depth > -2.5 and depth < 2.5 and across < math.max(3, (tonumber(halfWidth) or 3) + 0.5)
end

return M
