-- SLRR Garage: everything the player can configure, with its defaults.
-- Stored in /settings/slrr_garage/settings.json and edited from the garage's settings screen.

local M = {}

local FILE = '/settings/slrr_garage/settings.json'

-- order here is the order on the settings screen
M.defs = {
  { key = 'unlimitedMoney', group = 'Money', title = 'Unlimited money', type = 'bool', default = false,
    desc = 'Outside career mode: buy anything, nothing is ever deducted.' },
  { key = 'freeroamMoney', group = 'Money', title = 'Freeroam money', type = 'number', min = 0, max = 100000000, step = 5000, default = 250000,
    desc = 'What you start with outside career mode. Buying, selling, repairs and deliveries then move it up and down, and it is remembered between sessions. Changing this number sets your money to it. In career mode your career money is used instead.' },
  { key = 'priceMultiplier', group = 'Money', title = 'Part prices', type = 'range', min = 0, max = 3, step = 0.05, default = 1, unit = 'x',
    desc = 'Multiplies every catalog price. 0 makes parts free.' },
  { key = 'sellFactor', group = 'Money', title = 'Sell-back value', type = 'range', min = 0, max = 1, step = 0.05, default = 0.5, unit = 'x',
    desc = 'Share of a part\'s price you get back when you sell it.' },
  { key = 'repairFactor', group = 'Money', title = 'Repair cost', type = 'range', min = 0, max = 1, step = 0.05, default = 0.25, unit = 'x',
    desc = 'Share of a part\'s price charged for repairing it.' },
  { key = 'paintPrice', group = 'Money', title = 'Respray price', type = 'number', min = 0, max = 100000, step = 50, default = 300,
    desc = 'Cost of changing one paint colour in the paint booth.' },

  { key = 'shopDiscount', group = 'Money', title = 'Shop discount', type = 'range', min = 0, max = 50, step = 1, default = 5, unit = '%',
    desc = 'Parts bought over the counter at a shop in town are this much cheaper than ordering them from the garage.' },
  { key = 'deliveryFactor', group = 'Money', title = 'Delivery charges', type = 'range', min = 0, max = 3, step = 0.05, default = 1, unit = 'x',
    desc = 'Multiplies what delivery of ordered parts costs. The charge goes by weight and bulk: a hood costs far more to send than a hub cap. 0 makes delivery free.' },
  { key = 'expressMultiplier', group = 'Money', title = 'Express delivery', type = 'range', min = 1, max = 6, step = 0.25, default = 2.5, unit = 'x',
    desc = 'How much more express delivery costs than standard. It arrives ten times sooner.' },
  { key = 'deliveryMinutes', group = 'Money', title = 'Standard delivery time', type = 'range', min = 0, max = 15, step = 0.5, default = 3, unit = ' min',
    desc = 'How long a standard delivery takes to reach the garage. 0 delivers at once. Parts bought in a shop in town never wait: you take them with you.' },

  { key = 'keepDamage', group = 'Garage', title = 'Parts keep their damage', type = 'bool', default = true,
    desc = 'A bent bumper is still bent after you take it off and refit it, and the car leaves as damaged as it came in unless you pay for repairs.' },
  { key = 'autoEnter', group = 'Garage', title = 'Drive up to the door to enter', type = 'bool', default = true,
    desc = 'Rolling towards the garage door starts the visit. Turn off to enter only with the key binding.' },
  { key = 'enterSpeed', group = 'Garage', title = 'Fastest speed to enter at', type = 'range', min = 5, max = 60, step = 1, default = 15, unit = ' km/h',
    desc = 'A door only takes the car in when it rolls up slower than this. Faster, and you just drive through.' },
  { key = 'playFilm', group = 'Garage', title = 'Drive-in film', type = 'bool', default = true,
    desc = 'Watch the car roll into the garage. Turn off to cut straight to the garage.' },
  { key = 'highlight', group = 'Garage', title = 'Highlight the part under the cursor', type = 'bool', default = true,
    desc = 'Pulses the part a click would act on.' },
  { key = 'invertCameraX', group = 'Garage', title = 'Invert camera left / right', type = 'bool', default = false,
    desc = 'Swaps which way the camera goes round the car when you drag sideways.' },
  { key = 'paintSmoke', group = 'Garage', title = 'Spray cloud when painting', type = 'bool', default = true,
    desc = 'A respray hides the car in a cloud of the new colour for a moment.' },

  { key = 'previews', group = 'Catalog', title = '3D part previews', type = 'bool', default = true,
    desc = 'Show each part as a turning 3D model in the catalog and on the shelf. They are drawn by the game itself, at the quality of your graphics settings.' },
  { key = 'spinSpeed', group = 'Catalog', title = 'Preview turn speed', type = 'range', min = 0, max = 3, step = 0.1, default = 1, unit = 'x',
    desc = 'How fast the previews turn.' },
  { key = 'spinClockwise', group = 'Catalog', title = 'Previews turn clockwise', type = 'bool', default = true,
    desc = 'Seen from above. Turn off for anticlockwise.' },
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
