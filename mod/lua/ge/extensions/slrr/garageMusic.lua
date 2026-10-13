-- Wrench Works: the radio.
-- Plays whatever music files it finds, one after another in a shuffled order, while you are in
-- a garage or a shop. No music comes with the mod. It looks in two places:
--   /settings/slrr_garage/music/      in your BeamNG user folder: yours (tools/add_music.ps1 fills it)
--   /art/sound/slrr_garage/music/     for music a mod or a pack brings along
-- .ogg, .wav and .flac play as they are.
--
-- With "Music comes from the radio" switched on the sound has a place in the world - the
-- garage's radio - so it is louder near it and moves between your ears as the camera goes round
-- the car. That needs mono files (add_music.ps1 makes them); the game does not place stereo.

local M = {}

local settings = require('slrr/garageSettings')

local DIRS = { '/settings/slrr_garage/music/', '/art/sound/slrr_garage/music/' }
local PLAIN, PLACED = 'AudioGui', 'AudioDefault3D'      -- the game's own sound descriptions

local tracks              -- files found, shuffled; looked up again on every visit
local index = 0
local sourceId            -- the sound source of the track that is playing
local at                  -- the radio it was started for (nil: plain music, the same everywhere)
local age = 0             -- seconds since it was started
local volume
local fails = 0           -- tracks in a row that would not play; after three it stays quiet this visit

local function source()
  return sourceId and scenetree.findObjectById(sourceId) or nil
end

function M.stop()
  if not sourceId then return end
  local snd = source()
  if snd then snd:stop(-1) end
  Engine.Audio.deleteSource(sourceId)
  sourceId = nil
end

local function findTracks()
  local list = {}
  for _, dir in ipairs(DIRS) do
    for _, file in ipairs(FS:findFiles(dir, '*.ogg\t*.wav\t*.flac', 0, false, false) or {}) do list[#list + 1] = file end
  end
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

local function create(description, file)
  local id = Engine.Audio.createSource(description, file)
  if type(id) ~= 'number' or id == 0 or not scenetree.findObjectById(id) then return nil end
  return id
end

local function start(file, radioPos)
  local placed = radioPos ~= nil
  sourceId = placed and create(PLACED, file) or nil
  if not sourceId then
    -- the game would not give it a place: plain music is better than none
    placed = false
    sourceId = create(PLAIN, file)
  end
  local snd = source()
  if not snd then
    sourceId = nil
    return false
  end
  if placed and snd.setTransform then
    local m = MatrixF(true)
    m:setPosition(radioPos)
    snd:setTransform(m)
  end
  at = radioPos
  age, volume = 0, settings.get('musicVolume')
  snd:setVolume(volume)
  snd:play(-1)
  return true
end

-- playing: we are in a garage or a shop.  radioPos: where its radio stands (nil: nowhere in particular)
function M.update(dt, playing, radioPos)
  if not playing or not settings.get('music') or fails >= 3 then
    if not playing then tracks, fails = nil, 0 end
    M.stop()
    return
  end
  if not settings.get('musicRadio') then radioPos = nil end
  local snd = source()
  if snd and ((radioPos ~= nil) ~= (at ~= nil) or (radioPos and at and (radioPos - at):squaredLength() > 0.01)) then
    -- the radio setting was flipped, or this is another radio: the same track again, the other way
    M.stop()
    snd = nil
    index = index - 1
  end
  if snd then
    age = age + dt
    local wanted = settings.get('musicVolume')
    if wanted ~= volume then
      volume = wanted
      snd:setVolume(volume)
    end
    if age < 2 or snd:isPlaying() then return end
    fails = age < 5 and fails + 1 or 0      -- over at once: it never got going
  end
  M.stop()
  tracks = tracks or findTracks()
  if #tracks == 0 then return end
  index = index % #tracks + 1
  if not start(tracks[index], radioPos) then fails = fails + 1 end
end

return M
