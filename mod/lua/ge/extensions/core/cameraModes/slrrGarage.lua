-- Wrench Works camera mode. A thin shell: the garage extension owns the camera logic
-- (slrr/garageCamera.lua); this mode just asks it where the camera is each frame.

local C = {}
C.__index = C

function C:init()
  self.isGlobal = true
  self.hidden = true
end

function C:update(data)
  local cam = package.loaded['slrr/garageCamera']
  if not cam then return false end
  local pos, rot, fov, target = cam.update(data.dt)
  if not pos then return false end
  data.res.pos:set(pos)
  data.res.rot:set(rot)
  data.res.fov = fov
  if target then data.res.targetPos:set(target) end
  return true
end

function C:onCameraChanged(focused)
  if focused then
    guihooks.trigger('onCameraNameChanged', {name = 'slrrGarage'})
  end
end

-- DO NOT CHANGE CLASS IMPLEMENTATION BELOW

return function(...)
  local o = ... or {}
  setmetatable(o, C)
  o:init()
  return o
end
