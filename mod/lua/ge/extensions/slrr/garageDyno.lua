-- Wrench Works: the dyno's figures for the UI.
-- The dyno's "before": the first run on a model (kept between visits), or the run pinned as baseline;
-- later runs are drawn over it. Its own file because garage.lua is near LuaJIT's limit of 200 top-level locals (tools/locals_check.js).

local parts = require('slrr/garageParts')

local M = {}

local DYNO_FILE = '/settings/slrr_garage/dyno.json'
local dynoBase, lastDyno

local function modelOf(id) local v = getObjectByID(id) return v and v:getJBeamFilename() or nil end

local function send()
  if not lastDyno then return end
  local out = shallowcopy(lastDyno.data)
  if not parts.getFeatures().dyno then out.torque, out.power, out.noCurve = nil, nil, true end     -- (no dyno: the figures, no curve)
  local base = dynoBase and dynoBase[lastDyno.model]
  if base and base.maxPower and (base.maxPower ~= out.maxPower or base.maxTorque ~= out.maxTorque) then out.baseline = base end
  guihooks.trigger('slrrGarageDyno', out)
end

-- a run reported by the vehicle (vehId: the car in the garage)
function M.onDyno(id, data, vehId)
  extensions.hook('onWrenchWorksDyno', id, data)      -- other mods may want the figures (a career's tuning challenge)
  if id ~= vehId or type(data) ~= 'table' then return end
  local model = modelOf(id)
  dynoBase = dynoBase or jsonReadFile(DYNO_FILE) or {}
  if model and data.maxPower and not dynoBase[model] then
    dynoBase[model] = data
    jsonWriteFile(DYNO_FILE, dynoBase, true)
  end
  lastDyno = { model = model, data = data }
  send()
end

-- "Pin this run as baseline"
function M.pin()
  if not lastDyno or not lastDyno.model then return end
  dynoBase = dynoBase or jsonReadFile(DYNO_FILE) or {}
  dynoBase[lastDyno.model] = lastDyno.data
  jsonWriteFile(DYNO_FILE, dynoBase, true)
  send()
end

return M
