-- SLRR Garage: everything the player can configure, with its defaults.
-- Stored in /settings/slrr_garage/settings.json and edited from the garage's settings screen.

local M = {}

local FILE = '/settings/slrr_garage/settings.json'

-- order here is the order on the settings screen
M.defs = {
  { key = 'freeroamMoney', group = 'Money', title = 'Freeroam budget', type = 'number', min = 0, max = 100000000, step = 5000, default = 250000,
    desc = 'Outside career mode you always have exactly this much to spend. It never runs down. In career mode your real career money is used instead.' },
  { key = 'priceMultiplier', group = 'Money', title = 'Part prices', type = 'range', min = 0, max = 3, step = 0.05, default = 1, unit = 'x',
    desc = 'Multiplies every catalog price. 0 makes parts free.' },
  { key = 'sellFactor', group = 'Money', title = 'Sell-back value', type = 'range', min = 0, max = 1, step = 0.05, default = 0.5, unit = 'x',
    desc = 'Share of a part\'s price you get back when you sell it.' },
  { key = 'repairFactor', group = 'Money', title = 'Repair cost', type = 'range', min = 0, max = 1, step = 0.05, default = 0.25, unit = 'x',
    desc = 'Share of a part\'s price charged for repairing it.' },
  { key = 'paintPrice', group = 'Money', title = 'Respray price', type = 'number', min = 0, max = 100000, step = 50, default = 300,
    desc = 'Cost of changing one paint colour in the paint booth.' },

  { key = 'keepDamage', group = 'Garage', title = 'Parts keep their damage', type = 'bool', default = true,
    desc = 'A bent bumper is still bent after you take it off and refit it, and the car leaves as damaged as it came in unless you pay for repairs.' },
  { key = 'autoEnter', group = 'Garage', title = 'Drive up to the door to enter', type = 'bool', default = true,
    desc = 'Rolling towards the garage door starts the visit. Turn off to enter only with the key binding.' },
  { key = 'playFilm', group = 'Garage', title = 'Drive-in film', type = 'bool', default = true,
    desc = 'Watch the car roll into the garage. Turn off to cut straight to the garage.' },
  { key = 'highlight', group = 'Garage', title = 'Highlight the part under the cursor', type = 'bool', default = true,
    desc = 'Pulses the part a click would act on.' },

  { key = 'previews', group = 'Catalog', title = '3D part previews', type = 'bool', default = true,
    desc = 'Show each part as a turning white 3D model in the catalog and on the shelf.' },
  { key = 'photoPreviews', group = 'Catalog', title = 'Photographed previews', type = 'bool', default = false,
    desc = 'Instead of white models, photograph parts on a hidden copy of your car so previews show real textures, paint and livery. Entering the garage takes a little longer and new parts take a moment to appear.' },
  { key = 'spinSpeed', group = 'Catalog', title = 'Preview turn speed', type = 'range', min = 0, max = 3, step = 0.1, default = 1, unit = 'x',
    desc = 'How fast the previews turn.' },
}

local values = {}
local byKey = {}

local function sanitize(def, value)
  if def.type == 'bool' then
    if type(value) ~= 'boolean' then return def.default end
    return value
  end
  value = tonumber(value)
  if not value then return def.default end
  return clamp(value, def.min, def.max)
end

local function load()
  local data = jsonReadFile(FILE)
  if type(data) ~= 'table' then data = {} end
  for _, def in ipairs(M.defs) do
    byKey[def.key] = def
    values[def.key] = sanitize(def, data[def.key])
  end
end

function M.get(key)
  return values[key]
end

function M.set(key, value)
  local def = byKey[key]
  if not def then return false end
  values[key] = sanitize(def, value)
  jsonWriteFile(FILE, values, true)
  return true
end

function M.reset()
  for _, def in ipairs(M.defs) do values[def.key] = def.default end
  jsonWriteFile(FILE, values, true)
end

-- definitions with their current values, for the settings screen
function M.describe()
  local out = {}
  for _, def in ipairs(M.defs) do
    local d = deepcopy(def)
    d.value = values[def.key]
    out[#out + 1] = d
  end
  return out
end

load()

return M
