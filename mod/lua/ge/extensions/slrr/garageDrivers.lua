-- Wrench Works: the garage's Drivers panel: the pick goes to Wrench Works: Drivers & Pedestrians' own saved settings, the same store as its Mods page,
-- so it survives a respawn and nothing here overwrites it later. (The driver look, the driver mode and the pedestrian options are no longer kept or
-- applied by Wrench Works at all: that page is their only store. The old keys in settings.json are ignored.)
-- Its own file because garage.lua is near LuaJIT's limit of 200 top-level locals (tools/locals_check.js).

local M = {}

-- an outfit or helmet pick: the global look (it applies at once, and Drivers saves it)
function M.pickOutfit(look)
  slrrDrivers.setAppearance(nil, look)
end

-- a driver pick: behind the wheel of this car now, and the saved default for the cars that follow (what the Mods page's "Who drives" sets)
function M.pickDriver(vehId, driver)
  slrrDrivers.setDriver(vehId, driver)
  if slrrDrivers.setDefaultDriver then slrrDrivers.setDefaultDriver(driver) end
end

return M
