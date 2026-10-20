-- Wrench Works: the Drivers tab's outfits (#37). Pure (tested by tools/outfits_test.js).
-- The SLRR Drivers mod can tint a driver's shirt and trousers and put a helmet on (slrrDrivers.setAppearance). This module says what the garage's
-- Drivers tab offers and what a click means:
--   entries(driver, appearance, hasHelmet) -> service entries { id, tab = 'drivers', group = 'Outfit', label, desc, disabled }
--   look(id, appearance) -> the table for slrrDrivers.setAppearance, or nil for an id that is not an outfit one

local M = {}

-- colours 0..1; false clears the tint (the driver's own clothes)
M.OUTFITS = {
  { name = 'Original', shirt = false, trousers = false },
  { name = 'Street black', shirt = { 0.08, 0.08, 0.09 }, trousers = { 0.05, 0.05, 0.07 } },
  { name = 'Racing red', shirt = { 0.75, 0.08, 0.08 }, trousers = { 0.10, 0.10, 0.12 } },
  { name = 'Racing blue', shirt = { 0.10, 0.25, 0.75 }, trousers = { 0.08, 0.08, 0.10 } },
  { name = 'Hi-vis', shirt = { 0.95, 0.80, 0.05 }, trousers = { 0.10, 0.12, 0.16 } },
  { name = 'White', shirt = { 0.90, 0.90, 0.90 }, trousers = { 0.25, 0.25, 0.30 } },
}

local function sameColour(a, b)
  if a == false or a == nil then return b == false or b == nil end
  if type(a) ~= 'table' or type(b) ~= 'table' then return false end
  for i = 1, 3 do if math.abs((a[i] or 0) - (b[i] or 0)) > 0.01 then return false end end
  return true
end

function M.entries(driver, appearance, hasHelmet)
  appearance = appearance or {}
  local out = {}
  local helmet = appearance.helmet == true
  out[#out + 1] = { id = 'helmet:toggle', tab = 'drivers', group = 'Outfit', label = helmet and 'Helmet: on' or 'Helmet: off',
    desc = (driver and not hasHelmet) and 'this driver has no helmet' or 'click to switch it; it is always on at track events', disabled = not driver or not hasHelmet }
  for _, o in ipairs(M.OUTFITS) do
    local current = sameColour(appearance.shirt, o.shirt) and sameColour(appearance.trousers, o.trousers)
    out[#out + 1] = { id = 'outfit:' .. o.name, tab = 'drivers', group = 'Outfit', label = o.name, desc = current and 'on now' or 'shirt and trousers', disabled = not driver or current }
  end
  return out
end

function M.look(id, appearance)
  id = tostring(id or '')
  if id == 'helmet:toggle' then return { helmet = not ((appearance or {}).helmet == true) } end
  local name = id:match('^outfit:(.+)$')
  if not name then return nil end
  for _, o in ipairs(M.OUTFITS) do
    if o.name == name then return { shirt = o.shirt, trousers = o.trousers } end
  end
  return nil
end

-- The Driver look settings of the garage are pushed to the Drivers mod only when the player changes one of them: the first call of a session just notes the values
-- (Drivers keeps its own saved look, and its Mods page and the Active features page write only there, so pushing the garage's stale copy at every start wiped it).
-- Returns the changed fields (a value of false clears one there), or nil when nothing changed or it is the first call (seen == nil).
local function same(a, b)
  if type(a) == 'table' and type(b) == 'table' then
    for i = 1, 3 do if math.abs((a[i] or -1) - (b[i] or -1)) > 1e-3 then return false end end
    return true
  end
  return a == b
end
function M.changes(seen, want)
  if not seen then return nil end
  local out
  for k, v in pairs(want) do
    if not same(seen[k], v) then out = out or {} out[k] = v end
  end
  return out
end

return M
