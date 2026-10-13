-- Wrench Works: the catalog's table of contents, and the rules that sort BeamNG parts into it.
-- The sections follow Street Legal Racing: Redline's catalog (engine / body / running gear /
-- interior), with the audio and decal chapters swapped for things BeamNG cars actually have.
-- Chapters are kept small: anything that comes in a front and a rear flavour gets one of each.

local M = {}

M.sections = {
  { id = "engine", title = "ENGINE", subs = {
    { id = "blocks", title = "ENGINE BLOCKS" },
    { id = "internals", title = "ENGINE INTERNALS" },
    { id = "intake", title = "INTAKE SYSTEMS" },
    { id = "exhaust", title = "EXHAUST SYSTEMS" },
    { id = "fuel", title = "FUEL SYSTEMS" },
    { id = "forced", title = "TURBOS & SUPERCHARGERS" },
    { id = "nitrous", title = "NITROUS" },
    { id = "management", title = "ENGINE MANAGEMENT" },
    { id = "transmission", title = "TRANSMISSIONS" },
    { id = "clutch", title = "CLUTCH & FLYWHEELS" },
    { id = "cooling", title = "COOLING" },
    { id = "mounts", title = "MOUNTS & MISC" },
  } },
  { id = "body", title = "BODY", subs = {
    { id = "shells", title = "BODY SHELLS" },
    { id = "bumpers_f", title = "FRONT BUMPERS" },
    { id = "bumpers_r", title = "REAR BUMPERS" },
    { id = "hoods", title = "HOODS" },
    { id = "fenders", title = "FENDERS" },
    { id = "doors", title = "DOORS" },
    { id = "trunk", title = "TRUNK & TAILGATE" },
    { id = "roof", title = "ROOF" },
    { id = "glass", title = "GLASS" },
    { id = "lights_f", title = "FRONT LIGHTS" },
    { id = "lights_r", title = "REAR LIGHTS" },
    { id = "bulbs", title = "BULBS" },
    { id = "mirrors", title = "MIRRORS" },
    { id = "wings", title = "SPOILERS & WINGS" },
    { id = "aero", title = "SPLITTERS, SKIRTS & FLARES" },
    { id = "chassis", title = "CHASSIS & BRACING" },
    { id = "plates", title = "PLATE HOLDERS" },
    { id = "electrics", title = "HORNS & ELECTRONICS" },
    { id = "misc", title = "ACCESSORIES" },
  } },
  { id = "running", title = "RUNNING GEAR", subs = {
    { id = "suspension_f", title = "FRONT SUSPENSION" },
    { id = "suspension_r", title = "REAR SUSPENSION" },
    { id = "shocks_f", title = "FRONT SPRINGS & DAMPERS" },
    { id = "shocks_r", title = "REAR SPRINGS & DAMPERS" },
    { id = "bars", title = "SWAY BARS" },
    { id = "steering", title = "STEERING" },
    { id = "brakes_f", title = "FRONT BRAKES" },
    { id = "brakes_r", title = "REAR BRAKES" },
    { id = "brakes", title = "BRAKE SYSTEMS" },
    { id = "rims_f", title = "FRONT WHEELS" },
    { id = "rims_r", title = "REAR WHEELS" },
    { id = "tyres_f", title = "FRONT TYRES" },
    { id = "tyres_r", title = "REAR TYRES" },
    { id = "hubs", title = "HUBS & WHEEL DATA" },
    { id = "differentials", title = "DIFFERENTIALS" },
    { id = "driveline", title = "DRIVESHAFTS" },
  } },
  { id = "interior", title = "INTERIOR", subs = {
    { id = "steering", title = "STEERING WHEELS" },
    { id = "dash", title = "DASHBOARDS & GAUGES" },
    { id = "shifter", title = "GEAR KNOBS & PEDALS" },
    { id = "seats_f", title = "FRONT SEATS" },
    { id = "seats_r", title = "REAR SEATS" },
    { id = "trim", title = "DOOR PANELS & TRIM" },
    { id = "extras", title = "EXTRAS" },
  } },
  { id = "paint", title = "PAINT & DECALS", subs = {
    { id = "skins", title = "PAINT DESIGNS" },
    { id = "interior", title = "INTERIOR COLOURS" },
    { id = "plates", title = "LICENSE PLATES" },
  } },
}

M.sectionIndex, M.subIndex = {}, {}
for _, section in ipairs(M.sections) do
  M.sectionIndex[section.id] = section
  for _, sub in ipairs(section.subs) do M.subIndex[section.id .. "/" .. sub.id] = sub end
end

-- First match wins, so the specific words sit above the general ones. A sub id ending in "_?"
-- is finished off with "f" or "r" from where the part sits on the car.
local rules = {
  { { "licenseplate_design", "license plate design" }, "paint", "plates" },
  { { "skin_interior", "interior_skin", "skin_.*seat", "interior_colou?r" }, "paint", "interior" },
  { { "paint_design", "livery", "skin_", "_skin", "^skin" }, "paint", "skins" },

  { { "doorpanel", "door_panel" }, "interior", "trim" },
  { { "doorglass", "door_glass", "quarterglass", "windshield", "backlight", "glass", "window" }, "body", "glass" },
  { { "brakepad", "brake_f", "brake_r", "brakes?_", "brake$" }, "running", "brakes_?" },
  { { "_abs$", "_abs_", "^abs", "_esc$", "_esc_", "handbrake", "brake" }, "running", "brakes" },
  { { "bulb" }, "body", "bulbs" },
  { { "taillight", "tail_light", "brakelight", "reverselight", "rearfog", "chmsl" }, "body", "lights_r" },
  { { "headlight", "foglight", "rallylight", "lightbar", "drl" }, "body", "lights_f" },
  { { "mirror" }, "body", "mirrors" },
  { { "signal", "lettering" }, "body", "lights_?" },
  { { "strut_bar", "strutbar" }, "body", "chassis" },
  { { "wheeldata", "_hub", "^hub", "lugnut", "wheelspacer", "spacer" }, "running", "hubs" },
  { { "hubcap", "trimring", "centercap" }, "running", "rims_?" },
  { { "_steer$", "^steer$", "^steer_", "steeringwheel", "steering_wheel" }, "interior", "steering" },
  { { "tire", "tyre" }, "running", "tyres_?" },

  { { "exhaust", "header", "muffler", "downpipe", "tailpipe" }, "engine", "exhaust" },
  { { "intake", "airbox", "throttle", "carb" }, "engine", "intake" },
  { { "n2o", "nitrous" }, "engine", "nitrous" },
  { { "turbo", "supercharger", "intercooler", "boost", "charger" }, "engine", "forced" },
  { { "_ecu", "ecu$", "^ecu", "drivemode", "drive_mode", "launch", "limiter" }, "engine", "management" },
  { { "transmission", "gearbox", "transfer_case", "transfercase", "rangebox" }, "engine", "transmission" },
  { { "clutch", "flywheel", "converter" }, "engine", "clutch" },
  { { "radiator", "radfan", "oilcooler", "coolant" }, "engine", "cooling" },
  { { "fueltank", "fuelcell", "fuel", "injector", "battery" }, "engine", "fuel" },
  { { "differential", "finaldrive", "_lsd", "_diff" }, "running", "differentials" },
  { { "driveshaft", "halfshaft", "axleshaft", "propshaft" }, "running", "driveline" },
  { { "engine_internals", "internals", "piston", "crank", "camshaft", "valvetrain", "longblock" }, "engine", "internals" },
  { { "enginemount", "engine_mount", "oilpan", "engine_cover", "frunk" }, "engine", "mounts" },
  { { "engine", "motor" }, "engine", "blocks" },

  { { "swaybar", "sway_bar", "antiroll" }, "running", "bars" },
  { { "coilover", "strut", "shock", "spring", "leaf", "damper" }, "running", "shocks_?" },
  { { "steering", "power_steering", "steeringrack" }, "running", "steering" },
  { { "suspension", "controlarm", "knuckle", "axle" }, "running", "suspension_?" },
  { { "wheel", "_rim", "^rim" }, "running", "rims_?" },

  { { "seat" }, "interior", "seats_?" },
  { { "dash", "gauge", "screen", "radio", "console", "infotainment", "navi" }, "interior", "dash" },
  { { "shifter", "gearknob", "pedal" }, "interior", "shifter" },
  { { "sunvisor", "interior", "carpet", "headliner" }, "interior", "extras" },

  { { "spoiler", "wing" }, "body", "wings" },
  { { "fenderflare", "flare", "splitter", "_lip", "diffuser", "sideskirt", "canard", "scoop", "bodykit", "widebody", "undertray" }, "body", "aero" },
  { { "rollcage", "cage", "subframe", "brace", "towhitch", "hitch", "bullbar", "skidplate" }, "body", "chassis" },
  { { "licenseplate" }, "body", "plates" },
  { { "horn", "soundscape", "electronics", "gps", "antenna", "radar", "sensor", "alarm" }, "body", "electrics" },
  { { "badge", "roof_accessory", "roofrack", "emergencylights" }, "body", "misc" },
  { { "light" }, "body", "lights_?" },
  { { "bumper" }, "body", "bumpers_?" },
  { { "hood", "bonnet" }, "body", "hoods" },
  { { "fender", "quarterpanel" }, "body", "fenders" },
  { { "door" }, "body", "doors" },
  { { "trunk", "tailgate", "bed", "hatch" }, "body", "trunk" },
  { { "roof", "pillar", "sunroof" }, "body", "roof" },
  { { "body", "frame", "chassis", "grille", "unibody" }, "body", "shells" },
}

-- front or rear? read from the slot id first ("..._F", "..._RL"), then from its description
local function position(id, description)
  if id:find("_f$") or id:find("_f_") or id:find("_f[lr]$") or id:find("_f[lr]_") or id:find("front") then return "f" end
  if id:find("_r$") or id:find("_r_") or id:find("_r[lr]$") or id:find("_r[lr]_") or id:find("rear") then return "r" end
  if description:find("front") then return "f" end
  if description:find("rear") or description:find("back") then return "r" end
  return nil
end

-- sub ids that exist without a front/rear half, for parts that sit in neither
local unsplit = {
  ["running/brakes_?"] = "brakes", ["body/lights_?"] = "lights_f", ["running/rims_?"] = "rims_f",
  ["running/tyres_?"] = "tyres_f", ["running/shocks_?"] = "shocks_f", ["running/suspension_?"] = "suspension_f",
  ["interior/seats_?"] = "seats_f", ["body/bumpers_?"] = "bumpers_f",
}

local function match(text)
  for _, rule in ipairs(rules) do
    for _, pattern in ipairs(rule[1]) do
      if text:find(pattern) then return rule[2], rule[3] end
    end
  end
end

-- classify(slotId, partName, slotDescription) -> sectionId, subId (always a pair that exists)
function M.classify(slotId, partName, slotDescription)
  local id = tostring(slotId or ""):lower()
  local description = tostring(slotDescription or ""):lower()
  local section, sub = match(id)
  if not section then
    section, sub = match(id .. " " .. tostring(partName or ""):lower() .. " " .. (description:gsub("%s+", "_")))
  end
  if not section then return "body", "misc" end
  if sub:sub(-2) == "_?" then
    local where = position(id, description) or position(tostring(partName or ""):lower(), "")
    sub = where and (sub:sub(1, -2) .. where) or unsplit[section .. "/" .. sub] or sub
  end
  if not M.subIndex[section .. "/" .. sub] then return "body", "misc" end
  return section, sub
end

return M
