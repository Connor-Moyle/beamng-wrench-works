-- Wrench Works: everything the player can configure, with its defaults.
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

  { key = 'saveBetweenSessions', group = 'Money', title = 'Keep parts and money between sessions', type = 'bool', default = true,
    desc = 'On: the parts on your shelf, parts on order and your freeroam money are saved and are there again next time you play. Off: every time you start the game you begin with an empty shelf and the starting money, and nothing is written to disk.' },

  { key = 'deliveryMinutes', group = 'Delivery', title = 'Standard delivery time', type = 'range', min = 0, max = 30, step = 0.5, default = 3, unit = ' min',
    desc = 'How long a standard delivery takes to reach the garage. 0 delivers at once.' },
  { key = 'expressMinutes', group = 'Delivery', title = 'Express delivery time', type = 'range', min = 0, max = 10, step = 0.1, default = 0.3, unit = ' min',
    desc = 'How long an express delivery takes. 0 delivers at once.' },
  { key = 'deliveryFactor', group = 'Delivery', title = 'Delivery charges', type = 'range', min = 0, max = 3, step = 0.05, default = 1, unit = 'x',
    desc = 'Multiplies what delivery of ordered parts costs. The charge goes by weight and bulk: a hood costs far more to send than a hub cap. 0 makes delivery free.' },
  { key = 'expressMultiplier', group = 'Delivery', title = 'Express surcharge', type = 'range', min = 1, max = 6, step = 0.25, default = 2.5, unit = 'x',
    desc = 'How much more express delivery costs than standard.' },
  { key = 'shopDiscount', group = 'Delivery', title = 'Shop discount', type = 'range', min = 0, max = 50, step = 1, default = 5, unit = '%',
    desc = 'Parts bought over the counter at a shop in town are this much cheaper than ordering them from the garage, and you take them with you: no delivery, no waiting.' },

  { key = 'keepDamage', group = 'Garage', title = 'Parts keep their damage', type = 'bool', default = true,
    desc = 'A bent bumper is still bent after you take it off and refit it, and the car leaves as damaged as it came in unless you pay for repairs.' },
  { key = 'autoEnter', group = 'Garage', title = 'Drive up to the door to enter', type = 'bool', default = true,
    desc = 'Rolling towards the garage door starts the visit. Turn off to enter only with the key binding.' },
  { key = 'enterSpeed', group = 'Garage', title = 'Fastest speed to enter at', type = 'range', min = 5, max = 60, step = 1, default = 15, unit = ' km/h',
    desc = 'A door only takes the car in when it rolls up slower than this. Faster, and you just drive through.' },
  { key = 'walkIn', group = 'Garage', title = 'Walk in to start from a body shell', type = 'bool', default = true,
    desc = 'Walking into a garage on foot finds the lift empty and any car\'s bare body shell for sale: a car to build from nothing. Not in career mode.' },
  { key = 'shellPrice', group = 'Money', title = 'Body shell price', type = 'range', min = 0, max = 1, step = 0.05, default = 0.2, unit = 'x',
    desc = 'What a bare body shell costs, as a share of the list price of that car.' },
  { key = 'shops', group = 'Garage', title = 'Parts shops in town', type = 'bool', default = true,
    desc = 'Stopping on a shop\'s blue marker opens its counter. Off: the shops are closed and you order everything from the garage.' },
  { key = 'markers', group = 'Garage', title = 'Show door and shop markers', type = 'bool', default = true,
    desc = 'The glowing markers in garage doorways and on shop forecourts. The doors and shops work without them.' },
  { key = 'playFilm', group = 'Garage', title = 'Drive-in film', type = 'bool', default = true,
    desc = 'Watch the car roll into the garage. Turn off to cut straight to the garage.' },
  { key = 'sounds', group = 'Garage', title = 'Sounds', type = 'bool', default = true,
    desc = 'Clicks, clunks and the till. They are the game\'s own sounds.' },
  { key = 'music', group = 'Garage', title = 'Background music', type = 'bool', default = true,
    desc = 'Plays your music while you are in a garage or a shop. No music comes with the mod: put .ogg, .wav or .flac files in settings/slrr_garage/music/ in your BeamNG user folder, or let add_music.ps1 convert any music you have - including the garage music of your own copy of Street Legal Racing: Redline.' },
  { key = 'musicRadio', group = 'Garage', title = 'Music comes from the radio', type = 'bool', default = true,
    desc = 'The music has a place in the garage: louder near the radio, and it moves between your ears as the camera goes round the car. Needs mono files (add_music.ps1 makes them). Off: plain music, the same everywhere.' },
  { key = 'musicVolume', group = 'Garage', title = 'Music volume', type = 'range', min = 0, max = 1, step = 0.05, default = 0.5, unit = 'x',
    desc = 'How loud the background music is.' },
  { key = 'jobSheet', group = 'Garage', title = 'Job sheet before driving out', type = 'bool', default = true,
    desc = 'Drive out first shows what was fitted, taken off and spent this visit.' },
  { key = 'labour', group = 'Garage', title = 'Work takes time', type = 'bool', default = false,
    desc = 'Taking a part off or fitting it takes a moment, longer for heavy parts: a mirror is quick, an engine is not.' },
  { key = 'labourSpeed', group = 'Garage', title = 'Working speed', type = 'range', min = 0.25, max = 4, step = 0.25, default = 1, unit = 'x',
    desc = 'How fast the work goes when it takes time.' },
  { key = 'driveSpeed', group = 'Garage', title = 'Drive-in and drive-out speed', type = 'range', min = 0.5, max = 2, step = 0.1, default = 1, unit = 'x',
    desc = 'How briskly the car drives itself in and out.' },
  { key = 'driverMode', group = 'Garage', title = 'Driver', type = 'choice', default = 'full', needs = 'drivers',
    options = { { id = 'hidden', label = 'Hidden' }, { id = 'hideFirstPerson', label = 'Hide in first person' }, { id = 'full', label = 'Full driver' }, { id = 'still', label = 'No animations' } },
    desc = 'The driver from Wrench Works: Drivers & Pedestrians: not shown at all, shown but not in your own first-person view, fully animated, or sitting still.' },
  { key = 'carRadio', group = 'Radio', title = 'Car radio', type = 'bool', default = true,
    desc = 'The garage radio\'s music while you drive, one station per music folder. Keys under Options > Controls: Wrench Works: radio on/off, next station.' },
  { key = 'carRadioVolume', group = 'Radio', title = 'Radio volume', type = 'range', min = 0, max = 1, step = 0.05, default = 0.35, unit = 'x',
    desc = 'How loud the car radio plays.' },
  { key = 'injuryMode', group = 'Garage', title = 'Injuries', type = 'choice', default = 'injuries', needs = 'injury',
    options = { { id = 'off', label = 'Off' }, { id = 'injuries', label = 'Injuries' }, { id = 'full', label = 'Injuries and death' } },
    desc = 'Wrench Works: Drivers & Pedestrians: whether a crash hurts your driver, and whether it can kill them.' },
  -- Wrench Works: Drivers & Pedestrians: how your driver looks (slrrDrivers.setAppearance; eight colours keep its
  -- outfit combinations within what it loads at once)
  { key = 'driverSkin', group = 'Driver look', title = 'Driver', type = 'choice', dynamic = true, default = '', needs = 'appearance',
    options = { { id = '', label = 'Default' } }, desc = 'Who sits behind the wheel of your cars.' },
  { key = 'driverShirt', group = 'Driver look', title = 'Shirt', type = 'choice', default = 'skin', needs = 'appearance', options = { { id = 'skin', label = 'As drawn' }, { id = 'black', label = 'Black' }, { id = 'white', label = 'White' }, { id = 'red', label = 'Red' }, { id = 'blue', label = 'Blue' }, { id = 'green', label = 'Green' }, { id = 'orange', label = 'Orange' }, { id = 'grey', label = 'Grey' } },
    desc = 'The colour of the shirt.' },
  { key = 'driverTrousers', group = 'Driver look', title = 'Trousers', type = 'choice', default = 'skin', needs = 'appearance', options = { { id = 'skin', label = 'As drawn' }, { id = 'black', label = 'Black' }, { id = 'white', label = 'White' }, { id = 'red', label = 'Red' }, { id = 'blue', label = 'Blue' }, { id = 'green', label = 'Green' }, { id = 'orange', label = 'Orange' }, { id = 'grey', label = 'Grey' } },
    desc = 'The colour of the trousers.' },
  { key = 'driverScale', group = 'Driver look', title = 'Size', type = 'range', min = 0.9, max = 1.1, step = 0.02, default = 1, unit = 'x', needs = 'appearance',
    desc = 'A little smaller or bigger.' },
  { key = 'driverHelmet', group = 'Driver look', title = 'Helmet', type = 'bool', default = false, needs = 'appearance',
    desc = 'A helmet, for the track.' },
  { key = 'driverHelmetColor', group = 'Driver look', title = 'Helmet colour', type = 'choice', default = 'white', needs = 'appearance', options = { { id = 'skin', label = 'As drawn' }, { id = 'black', label = 'Black' }, { id = 'white', label = 'White' }, { id = 'red', label = 'Red' }, { id = 'blue', label = 'Blue' }, { id = 'green', label = 'Green' }, { id = 'orange', label = 'Orange' }, { id = 'grey', label = 'Grey' } },
    desc = 'The colour of the helmet.' },
  -- Wrench Works: Drivers & Pedestrians' people on the pavements (each maps to slrrPedestrians.setOptions's key `ped`)
  { key = 'pedAmount', ped = 'amount', group = 'World', title = 'Pedestrians', type = 'choice', default = 'medium', needs = 'pedestrians',
    options = { { id = 'off', label = 'Off' }, { id = 'low', label = 'Low' }, { id = 'medium', label = 'Medium' }, { id = 'high', label = 'High' }, { id = 'veryhigh', label = 'Very high' } },
    desc = 'How many people walk the pavements of Valo City.' },
  { key = 'pedMax', ped = 'maxCount', group = 'World', title = 'Most pedestrians at once', type = 'range', min = 0, max = 200, step = 10, default = 60, unit = '', needs = 'pedestrians',
    desc = 'A ceiling, whatever the amount above.' },
  { key = 'pedAuto', ped = 'autoReduce', group = 'World', title = 'Fewer when the frame rate drops', type = 'bool', default = true, needs = 'pedestrians',
    desc = 'Thins the crowd out when the game runs slower than the target below.' },
  { key = 'pedFps', ped = 'targetFps', group = 'World', title = 'Target frame rate', type = 'range', min = 30, max = 144, step = 1, default = 55, unit = ' fps', needs = 'pedestrians',
    desc = 'What "fewer when the frame rate drops" aims for.' },
  { key = 'pedIdle', ped = 'idling', group = 'World', title = 'People stop and stand about', type = 'bool', default = true, needs = 'pedestrians',
    desc = 'Now and then somebody stops, looks around, waits.' },
  { key = 'pedCross', ped = 'crossing', group = 'World', title = 'People cross at the lights', type = 'bool', default = true, needs = 'pedestrians',
    desc = 'They cross the road at crossings when the lights let them.' },
  { key = 'pedBusy', ped = 'busyAreas', group = 'World', title = 'Busier downtown and on the beachfront', type = 'bool', default = true, needs = 'pedestrians',
    desc = 'More people where a city would have them.' },
  { key = 'driverDoor', group = 'Garage', title = 'Driver\'s door opens on arrival', type = 'bool', default = true,
    desc = 'When the car has parked, the driver\'s door swings open and shut as if someone got out.' },
  { key = 'liftHeight', group = 'Garage', title = 'Lift height', type = 'range', min = 0.6, max = 1.9, step = 0.05, default = 1.35, unit = ' m',
    desc = 'How high the lift raises the car.' },
  { key = 'confirmSellAll', group = 'Garage', title = 'Ask before selling everything', type = 'bool', default = true,
    desc = 'Sell everything needs a second click to go through.' },
  { key = 'hints', group = 'Garage', title = 'Show the controls reminder', type = 'bool', default = true,
    desc = 'The small list of mouse controls in the top right corner of the garage.' },
  { key = 'cameraSensitivity', group = 'Garage', title = 'Camera drag sensitivity', type = 'range', min = 0.3, max = 2.5, step = 0.1, default = 1, unit = 'x',
    desc = 'How far the camera turns for a given drag of the mouse.' },
  { key = 'highlight', group = 'Garage', title = 'Highlight the part under the cursor', type = 'bool', default = true,
    desc = 'Pulses the part a click would act on.' },
  { key = 'invertCameraX', group = 'Garage', title = 'Invert camera left / right', type = 'bool', default = false,
    desc = 'Swaps which way the camera goes round the car when you drag sideways.' },
  { key = 'paintSmoke', group = 'Garage', title = 'Spray cloud when painting', type = 'bool', default = true,
    desc = 'A respray hides the car in a cloud of the new colour for a moment.' },

  { key = 'previews', group = 'Catalog', title = '3D part previews', type = 'bool', default = true,
    desc = 'Show each part as a turning 3D model in the catalog and on the shelf. They are drawn by the game itself, at the quality of your graphics settings.' },
  { key = 'retroCatalog', group = 'Catalog', title = 'Paper catalog', type = 'bool', default = false,
    desc = 'Just for a laugh: the catalog and the shops as a spiral-bound paper parts catalogue, the way a street racing game of the early 2000s would have had it.' },
  { key = 'spinSpeed', group = 'Catalog', title = 'Preview turn speed', type = 'range', min = 0, max = 3, step = 0.1, default = 1, unit = 'x',
    desc = 'How fast the previews turn.' },
  { key = 'spinClockwise', group = 'Catalog', title = 'Previews turn clockwise', type = 'bool', default = true,
    desc = 'Seen from above. Turn off for anticlockwise.' },
}

local values = {}
local byKey = {}

local function sanitize(def, value)
  if def.type == 'choice' then
    if def.dynamic then return type(value) == 'string' and value or def.default end      -- (its options come from another mod at runtime)
    for _, o in ipairs(def.options or {}) do if o.id == value then return value end end
    return def.default
  end
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
