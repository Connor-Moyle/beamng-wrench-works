-- Wrench Works: Drivers & Pedestrians: what the garage's settings do to the drivers and pedestrians mod.
-- The "Driver" setting picks how its drivers are shown (hidden, not in first person, full, still); the World group's
-- pedestrian settings and the Driver look group are sent too. Each is sent only when it differs from what the mod has.
-- Its own file because garage.lua is near LuaJIT's limit of 200 top-level locals (tools/locals_check.js).

local settings = require('slrr/garageSettings')

local M = {}

local seen          -- the look last sent, so only what the player changed here is sent

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

-- and how the driver looks: the Driver look group, sent only when something differs
local COLOURS = { black = { 0.05, 0.05, 0.06 }, white = { 0.9, 0.9, 0.9 }, red = { 0.75, 0.08, 0.08 }, blue = { 0.1, 0.25, 0.7 },
  green = { 0.12, 0.45, 0.18 }, orange = { 0.95, 0.45, 0.05 }, grey = { 0.45, 0.45, 0.47 } }
local function applyAppearance()
  if not (slrrDrivers and slrrDrivers.setAppearance) then return end
  local colour = function(key) return COLOURS[settings.get(key)] or false end
  local skin = settings.get('driverSkin')
  local want = { shirt = colour('driverShirt'), trousers = colour('driverTrousers'), scale = settings.get('driverScale'),
    helmet = settings.get('driverHelmet') == true, helmetColor = COLOURS[settings.get('driverHelmetColor')] or COLOURS.white }
  if skin and skin ~= '' then want.skin = skin end
  local delta = require('slrr/garageOutfits').changes(seen, want)
  seen = want
  if delta then slrrDrivers.setAppearance(nil, delta) end
end

function M.apply()
  applyPedestrians()
  applyAppearance()
  if not driversCanDisplay() then return end
  local mode = settings.get('driverMode') or 'full'
  -- only when it differs: setting it restarts every driver's animation and saves their settings file
  if not slrrDrivers.getDisplayMode or slrrDrivers.getDisplayMode() ~= mode then slrrDrivers.setDisplayMode(mode) end
end

return M
