-- Wrench Works: the car radio (extension name: slrr_carRadio). The garage radio's music, in every car you drive:
-- stations are the music folders' subfolders (/settings/slrr_garage/music/<station>/ and the same under
-- /art/sound/slrr_garage/music/), and the music lying loose in them is "Wrench Works FM". Bindable keys switch it
-- on and off and change station; its volume is in the settings. Each car keeps its own station (by model). In a
-- garage the garage's own radio plays instead; paused or in a menu it holds. One track is open at a time (each
-- source is let go before the next), so the music never sits in memory all at once.

local M = {}

local settings = require('slrr/garageSettings')

local DIRS = { '/settings/slrr_garage/music/', '/art/sound/slrr_garage/music/' }
local LOOSE = 'Wrench Works FM'
local STATE_FILE = '/settings/slrr_garage/radio.json'

local stations          -- { { name, tracks = {...} } }, found once a session (M.rescan to look again)
local station = 1
local on = true
local sourceId, age, volume, index = nil, 0, nil, {}
local perCar = {}         -- car (model) -> station name
local carKey             -- the car the radio is in

local function shuffle(list)
  for i = #list, 2, -1 do local j = math.random(i) list[i], list[j] = list[j], list[i] end
  return list
end

local function scan()
  local byName, order = {}, {}
  for _, dir in ipairs(DIRS) do
    for _, file in ipairs(FS:findFiles(dir, '*.ogg\t*.wav\t*.flac', -1, false, false) or {}) do
      local rel = file:sub(#dir + 1)
      local name = rel:match('^([^/]+)/') or LOOSE
      if not byName[name] then byName[name] = {} order[#order + 1] = name end
      table.insert(byName[name], file)
    end
  end
  table.sort(order, function(a, b) if a == LOOSE then return true elseif b == LOOSE then return false end return a < b end)
  stations = {}
  for _, name in ipairs(order) do stations[#stations + 1] = { name = name, tracks = shuffle(byName[name]) } end
  local saved = jsonReadFile(STATE_FILE)
  if type(saved) == 'table' then
    on = saved.on ~= false
    perCar = type(saved.perCar) == 'table' and saved.perCar or {}
    for i, st in ipairs(stations) do if st.name == saved.station then station = i end end
  end
end

local function stationName() return stations and stations[station] and stations[station].name end
local function save()
  if carKey then perCar[carKey] = stationName() end
  jsonWriteFile(STATE_FILE, { on = on, station = stationName(), perCar = perCar }, true)
end

local function source() return sourceId and scenetree.findObjectById(sourceId) or nil end

local function stop()
  if not sourceId then return end
  local snd = source()
  if snd then snd:stop(-1) end
  Engine.Audio.deleteSource(sourceId)
  sourceId = nil
end

local function play()
  local st = stations[station]
  if not st or #st.tracks == 0 then return false end
  index[station] = (index[station] or 0) % #st.tracks + 1
  local id = Engine.Audio.createSource('AudioGui', st.tracks[index[station]])
  local snd = type(id) == 'number' and id ~= 0 and scenetree.findObjectById(id)
  if not snd then return false end
  sourceId, age, volume = id, 0, settings.get('carRadioVolume')
  snd:setVolume(volume)
  snd:play(-1)
  return true
end

-- on the air: the setting and the switch on, at the wheel of a car, and not in a garage or a shop
local function wanted()
  if not on or not settings.get('carRadio') then return false end
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() == 'unicycle' then return false end
  if slrr_garage and slrr_garage.getPhase and slrr_garage.getPhase() ~= 'idle' then return false end
  return true
end

local function paused() return simTimeAuthority and simTimeAuthority.getPause and simTimeAuthority.getPause() end

local fails = 0
local held = false
function M.onUpdate(dtReal)
  if not wanted() then stop() held = false return end
  if not stations then scan() end
  if #stations == 0 or fails >= 3 then return end
  -- in another car: its own station
  local v = getPlayerVehicle(0)
  local key = v and v:getJBeamFilename()
  if key ~= carKey then
    carKey = key
    local want = perCar[key]
    for i, st in ipairs(stations) do if st.name == want and i ~= station then station = i stop() end end
  end
  local snd = source()
  -- paused (the menu): hold the song where it is
  if paused() then
    if snd and not held and snd.pause then snd:pause(-1) held = true end
    return
  elseif held then
    held = false
    if snd then snd:play(-1) end
    return
  end
  if snd then
    age = age + dtReal
    local want = settings.get('carRadioVolume')
    if want ~= volume then volume = want snd:setVolume(volume) end
    if age < 2 or snd:isPlaying() then return end
    fails = age < 5 and fails + 1 or 0
  end
  stop()
  if not play() then fails = fails + 1 end
end

local function announce()
  local st = stations and stations[station]
  if ui_message then ui_message(on and st and ('Radio: ' .. st.name) or 'Radio off', 2, 'slrrRadio') end
end

-- the keys (Options > Controls: Wrench Works: radio on/off, next station)
function M.toggle()
  if not stations then scan() end
  on = not on
  if not on then stop() end
  save()
  announce()
end

function M.nextStation()
  if not stations then scan() end
  if #stations == 0 then if ui_message then ui_message('No music: put some in settings/slrr_garage/music', 3, 'slrrRadio') end return end
  station = station % #stations + 1
  on, fails = true, 0
  stop()
  save()
  announce()
end

function M.rescan() stations = nil end
function M.status() return { on = on, station = stations and stations[station] and stations[station].name, stations = stations and #stations or 0, playing = source() ~= nil } end
function M.onClientEndMission() stop() end
function M.onExtensionUnloaded() stop() end

return M
