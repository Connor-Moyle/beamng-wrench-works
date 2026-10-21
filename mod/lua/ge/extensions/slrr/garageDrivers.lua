-- Wrench Works: Drivers & Pedestrians: what the garage's settings do to the drivers and pedestrians mod.
-- The "Driver" setting picks how its drivers are shown (hidden, not in first person, full, still); the World group's
-- pedestrian settings are sent too, each only when it differs from what the mod has.
-- The driver LOOK (skin, colours, size, helmet) is not applied from here any more: Pedestrians & Drivers' own page is its only store.
-- The old driver* keys of Wrench Works' settings.json are ignored (kept so old files do not error).
-- Its own file because garage.lua is near LuaJIT's limit of 200 top-level locals (tools/locals_check.js).

local settings = require('slrr/garageSettings')

local M = {}

-- only with a version of the mod that has setDisplayMode
local function driversCanDisplay() return slrrDrivers ~= nil and slrrDrivers.setDisplayMode ~= nil end

-- its pedestrians: the World group's settings (each def's `ped` names the option), only when one differs
local function applyPedestrians()
  if not (slrrPedestrians and slrrPedestrians.setOptions) then return end
  local now = slrrPedestrians.getOptions and slrrPedestrians.getOptions() or {}
  local want, differs = {}, false
  for _, d in ipairs(settings.defs) do
    if d.ped then
      want[d.ped] = settings.get(d.key)
      if now[d.ped] ~= want[d.ped] then differs = true end
    end
  end
  if differs then slrrPedestrians.setOptions(want) end
end

function M.apply()
  applyPedestrians()
  if not driversCanDisplay() then return end
  local mode = settings.get('driverMode') or 'full'
  -- only when it differs: setting it restarts every driver's animation and saves their settings file
  if not slrrDrivers.getDisplayMode or slrrDrivers.getDisplayMode() ~= mode then slrrDrivers.setDisplayMode(mode) end
end

return M
