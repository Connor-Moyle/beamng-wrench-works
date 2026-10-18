-- Wrench Works: the Mods menu's settings registry (extension name: slrr_settings). Docs: docs/MODS_MENU.md.
-- Every one of our mods (Wrench Works, Street Legal, Drivers & Pedestrians, Car Surface FX, ...) registers a schema of tabs and fields here; the page in the pause menu
-- (ui/ui-vue/mods/slrr_settings/ModsMenu.vue) only calls mods / page / set / reset / press. The registry validates and clamps every value that comes from the page.
-- Registrations are plain data; nothing is written until the player changes something.

local M = {}

local TAG = 'slrr_settings'
M.TAB = 'slrr_mods'                    -- the pause-menu tab that holds one button per mod
M.COMPONENT = '/ui/ui-vue/mods/slrr_settings/ModsMenu.vue'
M.QUICK_COMPONENT = '/ui/ui-vue/mods/slrr_settings/QuickSetup.vue'
M.FIND_COMPONENT = '/ui/ui-vue/mods/slrr_settings/FindSetting.vue'

local TYPES = { heading = true, note = true, bool = true, slider = true, int = true, enum = true, color = true, texture = true, button = true, text = true }
local VALUE_TYPES = { bool = true, slider = true, int = true, enum = true, color = true, texture = true, text = true }

-- what the registry needs from the game; a test replaces it
M.env = {
  getSetting = function(key) return settings and settings.getValue and settings.getValue(key) end,
  setSetting = function(key, value) if settings and settings.setValue then settings.setValue(key, value) end end,
  readJson = function(file) return jsonReadFile and jsonReadFile(file) end,
  writeJson = function(file, data) if jsonWriteFile then jsonWriteFile(file, data, true) end end,
  listFiles = function(folder, exts)
    local out = {}
    for _, f in ipairs(FS and FS:findFiles(folder, '*.*', -1, true, false) or {}) do
      local ext = tostring(f):match('%.([%w]+)$')
      for _, e in ipairs(exts) do if ext and ext:lower() == e:lower() then out[#out + 1] = f break end end
    end
    table.sort(out)
    return out
  end,
  log = function(level, text) if log then log(level, TAG, text) end end,
  toast = function(text) if guihooks then guihooks.trigger('slrrSettingsToast', { text = text }) end end,
}

local mods = {}                        -- mod id -> { mod, title, icon, order, tabs = { {id,title,description} }, fields = { ... }, byId = { field id -> field } }
local order = {}                       -- mod ids in the order of `order`, then registration

local function warn(text) M.env.log('W', text) end

-- ---- registration -------------------------------------------------------------------------------------------------------------------------------------------

local function validField(mod, tabs, f, seen)
  if type(f) ~= 'table' or type(f.id) ~= 'string' or f.id == '' then return false, 'a field without an id' end
  if seen[f.id] then return false, 'the field id ' .. f.id .. ' twice' end
  if not TYPES[f.type] then return false, f.id .. ': unknown type ' .. tostring(f.type) end
  if not tabs[f.tab] then return false, f.id .. ': unknown tab ' .. tostring(f.tab) end
  if type(f.label) ~= 'string' or f.label == '' then return false, f.id .. ': no label' end
  if VALUE_TYPES[f.type] then
    if type(f.store) ~= 'table' or not (f.store.kind == 'setting' or f.store.kind == 'json' or f.store.kind == 'custom') then return false, f.id .. ': no store' end
    if f.store.kind == 'setting' and type(f.store.key) ~= 'string' then return false, f.id .. ': a setting store needs a key' end
    if f.store.kind == 'json' and (type(f.store.file) ~= 'string' or type(f.store.path) ~= 'string') then return false, f.id .. ': a json store needs file and path' end
    if f.store.kind == 'custom' and (type(f.store.get) ~= 'function' or type(f.store.set) ~= 'function') then return false, f.id .. ': a custom store needs get and set' end
    if f.default == nil then return false, f.id .. ': no default' end
  end
  if f.type == 'slider' and not (type(f.min) == 'number' and type(f.max) == 'number' and f.max > f.min) then return false, f.id .. ': a slider needs min < max' end
  if f.type == 'int' and not (type(f.min) == 'number' and type(f.max) == 'number' and f.max >= f.min) then return false, f.id .. ': an int needs min <= max' end
  if f.type == 'enum' and not (type(f.options) == 'table' and #f.options > 0) then return false, f.id .. ': an enum needs options' end
  if f.type == 'texture' and not (type(f.folder) == 'string' and type(f.exts) == 'table' and #f.exts > 0) then return false, f.id .. ': a texture field needs folder and exts' end
  if f.type == 'button' and not (type(f.action) == 'function') then return false, f.id .. ': a button needs an action function' end
  if f.presets ~= nil and (type(f.presets) ~= 'table' or not VALUE_TYPES[f.type]) then return false, f.id .. ': presets must be a table on a setting' end
  return true
end

-- schema: { mod, title, icon, order, tabs = {{id,title,description}}, fields = {...} }. Registering a mod again replaces it. Bad fields are dropped (and logged), the rest stays.
function M.register(schema)
  if type(schema) ~= 'table' or type(schema.mod) ~= 'string' or not schema.mod:match('^[a-z0-9_]+$') then warn('register: a schema without a valid mod id') return false end
  local tabs, tabList = {}, {}
  for _, t in ipairs(schema.tabs or {}) do
    if type(t.id) == 'string' and type(t.title) == 'string' and not tabs[t.id] then tabs[t.id] = t tabList[#tabList + 1] = t end
  end
  if #tabList == 0 then warn('register: ' .. schema.mod .. ' has no tabs') return false end
  local entry = { mod = schema.mod, title = schema.title or schema.mod, icon = schema.icon or 'wrench', order = tonumber(schema.order) or 100, tabs = tabList, fields = {}, byId = {} }
  local seen = {}
  for _, f in ipairs(schema.fields or {}) do
    local ok, why = validField(schema.mod, tabs, f, seen)
    if ok then
      seen[f.id] = true
      entry.fields[#entry.fields + 1] = f
      entry.byId[f.id] = f
    else
      warn('register ' .. schema.mod .. ': ' .. tostring(why))
    end
  end
  if not mods[schema.mod] then order[#order + 1] = schema.mod end
  mods[schema.mod] = entry
  table.sort(order, function(a, b)
    if mods[a].order ~= mods[b].order then return mods[a].order < mods[b].order end
    return a < b
  end)
  if M.onRegistered then M.onRegistered(schema.mod) end
  return true
end

function M.unregister(modId)
  if not mods[modId] then return false end
  mods[modId] = nil
  for i, id in ipairs(order) do if id == modId then table.remove(order, i) break end end
  if M.onRegistered then M.onRegistered(modId) end
  return true
end

-- fields for a list of ids (eight surfaces with the same twelve settings, say): M.each({ 'dirt', 'sand' }, function(id) return { {...}, {...} } end) -> one flat list;
-- join the lists with M.join(listA, listB, ...).
function M.each(ids, make)
  local out = {}
  for _, id in ipairs(ids) do for _, f in ipairs(make(id) or {}) do out[#out + 1] = f end end
  return out
end
function M.join(...)
  local out = {}
  for _, list in ipairs({ ... }) do for _, f in ipairs(list) do out[#out + 1] = f end end
  return out
end

-- ---- from the settings lists the mods already have ---------------------------------------------------------------------------------------------------------------

-- The settings lists of Wrench Works and Street Legal are definitions { key, title, desc, type = bool | range | number | choice | info, default, min, max, step, unit, options,
-- group, tab, advanced }. This turns such a list into schema fields, so those mods keep their own data model and the menu is generated from it.
--   opts.tabOf(def) -> tab id (default: def.tab or def.group), opts.get(key), opts.set(key, value), opts.skip(def) -> true to leave a def out
-- Returns fields, tabs (in the order they first appear).
function M.fromDefs(defs, opts)
  local fields, tabs, seenTab = {}, {}, {}
  local function tabFor(d)
    local t = opts.tabOf and opts.tabOf(d) or d.tab or d.group or 'Settings'
    if not seenTab[t] then seenTab[t] = true tabs[#tabs + 1] = { id = t, title = t } end
    return t
  end
  for _, d in ipairs(defs) do
    if not (opts.skip and opts.skip(d)) and type(d.key) == 'string' then
      local f = { id = d.key, tab = tabFor(d), group = d.sub, label = d.title or d.key, tooltip = d.desc, default = d.default, advanced = d.advanced, apply = d.apply, presets = d.presets, requires = d.career and 'career' or nil }
      f.store = { kind = 'custom', get = function() return opts.get(d.key) end, set = function(v) return opts.set(d.key, v) end }
      if d.type == 'bool' then f.type = 'bool'
      elseif d.type == 'range' or d.type == 'number' then
        f.type, f.min, f.max, f.step, f.unit, f.scale = 'slider', d.min, d.max, d.step, d.unit, d.scale
      elseif d.type == 'choice' then f.type, f.options = 'enum', d.options
      elseif d.type == 'info' then f.type, f.store, f.default = 'note', nil, nil
      end
      if f.type then fields[#fields + 1] = f end
    end
  end
  return fields, tabs
end

-- ---- stores ---------------------------------------------------------------------------------------------------------------------------------------------------

local function splitPath(path)
  local keys = {}
  for k in tostring(path):gmatch('[^%.]+') do keys[#keys + 1] = k end
  return keys
end

local function readStore(f)
  local s = f.store
  if s.kind == 'setting' then return M.env.getSetting(s.key) end
  if s.kind == 'custom' then
    local ok, v = pcall(s.get)
    if ok then return v end      -- (not `ok and v or nil`: a false setting is a value, and that turned every false into nil, then into the default)
    return nil
  end
  local d = M.env.readJson(s.file)
  for _, k in ipairs(splitPath(s.path)) do
    if type(d) ~= 'table' then return nil end
    d = d[k]
  end
  return d
end

local function same(a, b)
  if type(a) == 'table' and type(b) == 'table' then
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end
  return a == b
end

local function writeStore(f, value)
  local s = f.store
  if s.kind == 'setting' then M.env.setSetting(s.key, value) return true end
  if s.kind == 'custom' then return (pcall(s.set, value)) end
  local d = M.env.readJson(s.file)
  if type(d) ~= 'table' then d = {} end
  local keys, cur = splitPath(s.path), d
  for i = 1, #keys - 1 do
    if type(cur[keys[i]]) ~= 'table' then cur[keys[i]] = {} end
    cur = cur[keys[i]]
  end
  if same(cur[keys[#keys]], value) then return true end      -- (nothing changed: nothing written)
  cur[keys[#keys]] = value
  M.env.writeJson(s.file, d)
  return true
end

-- ---- values ---------------------------------------------------------------------------------------------------------------------------------------------------

local function round(x, step)
  if not step or step <= 0 then return x end
  local snapped = math.floor(x / step + 0.5) * step
  return tonumber(string.format('%.6f', snapped))
end

local function textureFiles(f)
  return M.env.listFiles(f.folder, f.exts)
end

-- value from the page (or anywhere) -> the clean value to store, or nil and a reason
local function coerce(f, v)
  local t = f.type
  if t == 'bool' then
    if v == true or v == 1 or v == 'true' or v == '1' then return true end
    if v == false or v == 0 or v == 'false' or v == '0' then return false end
    return nil, 'not a yes or no'
  elseif t == 'slider' then
    v = tonumber(v)
    if not v or v ~= v then return nil, 'not a number' end
    return round(math.max(f.min, math.min(f.max, v)), f.step)
  elseif t == 'int' then
    v = tonumber(v)
    if not v or v ~= v then return nil, 'not a number' end
    return math.max(f.min, math.min(f.max, math.floor(v + 0.5)))
  elseif t == 'enum' then
    for _, o in ipairs(f.options) do if o.id == v then return v end end
    return nil, 'not one of the options'
  elseif t == 'color' then
    if type(v) ~= 'table' then return nil, 'not a colour' end
    local out = {}
    for i, k in ipairs({ 'r', 'g', 'b' }) do
      local c = tonumber(v[k] or v[i])
      if not c then return nil, 'not a colour' end
      out[k] = math.max(0, math.min(1, c))
    end
    if f.alpha then out.a = math.max(0, math.min(1, tonumber(v.a or v[4]) or 1)) end
    return out
  elseif t == 'texture' then
    if v == '' or v == nil then
      if f.none then return '' end
      return nil, 'a picture is needed'
    end
    for _, file in ipairs(textureFiles(f)) do if file == v then return v end end
    return nil, 'not a file of the folder'
  elseif t == 'text' then
    if type(v) ~= 'string' then return nil, 'not text' end
    return v:sub(1, f.maxLength or 80)
  end
  return nil, 'not a setting'
end

local function currentValue(f)
  local v = readStore(f)
  if v == nil then return f.default end
  local clean = coerce(f, v)
  if clean == nil then return f.default end
  return clean
end

-- ---- what the page asks ---------------------------------------------------------------------------------------------------------------------------------------

function M.mods()
  local out = {}
  for _, id in ipairs(order) do
    local m = mods[id]
    local tabs = {}
    for _, t in ipairs(m.tabs) do tabs[#tabs + 1] = { id = t.id, title = t.title, description = t.description } end
    out[#out + 1] = { mod = m.mod, title = m.title, icon = m.icon, tabs = tabs }
  end
  return out
end

local function publicField(f)
  local out = { id = f.id, tab = f.tab, group = f.group, type = f.type, label = f.label, tooltip = f.tooltip, default = f.default, apply = f.apply or 'live',
    min = f.min, max = f.max, step = f.step, unit = f.unit, scale = f.scale, options = f.options, alpha = f.alpha, none = f.none, thumbs = f.thumbs,
    maxLength = f.maxLength, advanced = f.advanced, visibleIf = f.visibleIf, confirm = f.confirm, hasPresets = type(f.presets) == 'table' or nil,
    requires = f.requires == 'career' and not (rawget(_G, 'sl_career') and sl_career.isActive and sl_career.isActive()) and 'career' or nil }      -- (the note "only while a career is loaded" is for when none is)
  if VALUE_TYPES[f.type] then
    out.value = currentValue(f)
    out.changed = not same(out.value, f.default)
  end
  if f.type == 'texture' then out.files = textureFiles(f) end
  return out
end

function M.page(modId, tabId)
  local m = mods[modId]
  if not m then return { fields = {}, error = 'no such mod' } end
  local fields = {}
  for _, f in ipairs(m.fields) do if f.tab == tabId then fields[#fields + 1] = publicField(f) end end
  return { mod = modId, tab = tabId, fields = fields }
end

function M.get(modId, fieldId)
  local f = mods[modId] and mods[modId].byId[fieldId]
  if not f or not VALUE_TYPES[f.type] then return nil end
  return currentValue(f)      -- (not `and ... or nil`: a false setting is a value)
end

-- the value is saved before its apply runs: an apply that fails is said in the log (the setting is saved but not in effect)
local function runOnChange(f, value)
  if not f.onChange then return end
  local ok, err = pcall(f.onChange, value)
  if not ok then warn('the setting ' .. tostring(f.id) .. ' was saved but its apply failed: ' .. tostring(err)) end
end

function M.set(modId, fieldId, value)
  local f = mods[modId] and mods[modId].byId[fieldId]
  if not f or not VALUE_TYPES[f.type] then return { ok = false, error = 'no such setting' } end
  local clean, why = coerce(f, value)
  if clean == nil then return { ok = false, error = why, value = currentValue(f) } end
  M.env.log('I', 'set ' .. tostring(modId) .. '.' .. tostring(fieldId) .. ' = ' .. (type(clean) == 'table' and 'table' or tostring(clean)))
  writeStore(f, clean)
  runOnChange(f, clean)
  -- a preset: the chosen option of an enum can fill other fields of the mod (options[i].sets = { fieldId = value, ... })
  if f.type == 'enum' then
    for _, o in ipairs(f.options) do
      if o.id == clean and type(o.sets) == 'table' then
        for otherId, v in pairs(o.sets) do
          local other = mods[modId].byId[otherId]
          if other and other ~= f and VALUE_TYPES[other.type] then
            local c = coerce(other, v)
            if c ~= nil then writeStore(other, c) runOnChange(other, c) end
          end
        end
      end
    end
  end
  return { ok = true, value = clean }
end

function M.reset(modId, tabId)
  local m = mods[modId]
  if not m then return { fields = {} } end
  for _, f in ipairs(m.fields) do
    if f.tab == tabId and VALUE_TYPES[f.type] then
      local clean = coerce(f, f.default)
      if clean ~= nil then
        writeStore(f, clean)
        runOnChange(f, clean)
      end
    end
  end
  return M.page(modId, tabId)
end

function M.press(modId, fieldId)
  local f = mods[modId] and mods[modId].byId[fieldId]
  if not f or f.type ~= 'button' then return { ok = false, error = 'no such button' } end
  local ok, text = pcall(f.action)
  M.env.log('I', 'press ' .. modId .. '.' .. fieldId .. ' -> ' .. tostring(text))
  if not ok then warn('button ' .. fieldId .. ': ' .. tostring(text)) return { ok = false, error = tostring(text) } end
  return { ok = true, text = type(text) == 'string' and text or nil }
end

-- ---- find a setting, and the whole-pack presets ---------------------------------------------------------------------------------------------------------------

-- every word of the query must be in the label, the tooltip, the group, the tab or the mod's name (case does not matter); headings and notes are not settings
function M.search(query)
  local words = {}
  for w in tostring(query or ''):lower():gmatch('%S+') do words[#words + 1] = w end
  if #words == 0 then return {} end
  local out = {}
  for _, id in ipairs(order) do
    local m = mods[id]
    local tabTitle = {}
    for _, t in ipairs(m.tabs) do tabTitle[t.id] = t.title end
    for _, f in ipairs(m.fields) do
      if f.type ~= 'heading' and f.type ~= 'note' then
        local hay = (tostring(f.label) .. ' ' .. tostring(f.tooltip or '') .. ' ' .. tostring(f.group or '') .. ' ' .. tostring(tabTitle[f.tab] or '') .. ' ' .. m.title):lower()
        local all = true
        for _, w in ipairs(words) do if not hay:find(w, 1, true) then all = false break end end
        if all then
          out[#out + 1] = { mod = id, modTitle = m.title, tab = f.tab, tabTitle = tabTitle[f.tab], field = publicField(f) }
          if #out >= 40 then return out end
        end
      end
    end
  end
  return out
end

-- Quick setup: a field may declare presets = { performance = v, balanced = v, quality = v, max = v } (any of them). A preset writes its value into every field that declares it;
-- the current preset is the one whose values all match, else 'custom'.
M.PRESETS = { { id = 'performance', title = 'Performance' }, { id = 'balanced', title = 'Balanced' }, { id = 'quality', title = 'Quality' }, { id = 'max', title = 'Max' } }

local function presetFields(presetId)
  local out = {}
  for _, id in ipairs(order) do
    for _, f in ipairs(mods[id].fields) do
      if VALUE_TYPES[f.type] and type(f.presets) == 'table' and f.presets[presetId] ~= nil then out[#out + 1] = { mod = id, field = f } end
    end
  end
  return out
end

function M.currentPreset()
  local any
  for _, p in ipairs(M.PRESETS) do
    local list = presetFields(p.id)
    if #list > 0 then
      any = true
      local match = true
      for _, e in ipairs(list) do
        local want = coerce(e.field, e.field.presets[p.id])
        if want == nil or not same(currentValue(e.field), want) then match = false break end
      end
      if match then return p.id end
    end
  end
  return any and 'custom' or 'none'
end

function M.quickSetup()
  local out = { presets = {}, current = M.currentPreset(), mods = {} }
  for _, p in ipairs(M.PRESETS) do out.presets[#out.presets + 1] = { id = p.id, title = p.title, fields = #presetFields(p.id) } end
  for _, id in ipairs(order) do
    local n = 0
    for _, f in ipairs(mods[id].fields) do if VALUE_TYPES[f.type] and type(f.presets) == 'table' then n = n + 1 end end
    if n > 0 then out.mods[#out.mods + 1] = { mod = id, title = mods[id].title, fields = n } end
  end
  return out
end

function M.applyPreset(presetId)
  local known
  for _, p in ipairs(M.PRESETS) do if p.id == presetId then known = true end end
  if not known then return { ok = false, error = 'no such preset' } end
  local n = 0
  for _, e in ipairs(presetFields(presetId)) do
    local clean = coerce(e.field, e.field.presets[presetId])
    if clean ~= nil then
      writeStore(e.field, clean)
      if e.field.onChange then pcall(e.field.onChange, clean) end
      n = n + 1
    end
  end
  local r = M.quickSetup()
  r.ok, r.changed = true, n
  return r
end

-- ---- the pause menu ---------------------------------------------------------------------------------------------------------------------------------------------

local function registerMenu()
  local a = rawget(_G, 'ui_pause_actions')
  if not a and extensions and extensions.load then pcall(extensions.load, 'ui_pause_actions') a = rawget(_G, 'ui_pause_actions') end
  if not (a and a.registerModTab and a.registerModButton) then return false end
  local ok = pcall(a.registerModTab, { id = M.TAB, label = 'Mods menu', icon = 'wrench' })
  if not ok then return false end
  pcall(a.registerModButton, { id = 'slrr_settings_quick', tabId = M.TAB, label = 'Quick setup', icon = 'wrench', componentName = M.QUICK_COMPONENT })
  pcall(a.registerModButton, { id = 'slrr_settings_find', tabId = M.TAB, label = 'Find a setting', icon = 'wrench', componentName = M.FIND_COMPONENT })
  for _, id in ipairs(order) do
    pcall(a.registerModButton, { id = 'slrr_settings_' .. id, tabId = M.TAB, label = mods[id].title, icon = mods[id].icon, componentName = M.COMPONENT, props = { mod = id } })
  end
  return true
end
M.registerMenu = registerMenu
M.onRegistered = function() registerMenu() end

-- Wrench Works' own settings (its garage settings list: money, delivery, garage, radio, catalog), as the Mods menu's first mod
local function registerWrenchWorks()
  local g = rawget(_G, 'slrr_garage')
  if not (g and g.ownSettingsDefs and g.setSetting) then return false end
  local defs = g.ownSettingsDefs()
  -- the driver, pedestrian and injury settings are Pedestrians & Drivers' (they register their own page)
  local function skip(d) return d.needs == 'drivers' or d.needs == 'appearance' or d.needs == 'pedestrians' or d.needs == 'injury' or d.group == 'Driver look' or d.key == 'driverMode' or d.key == 'injuryMode' end
  local function tabOf(d) return d.group == 'Radio' and 'Car radio' or d.group end
  local byKey = {}
  for _, d in ipairs(defs) do byKey[d.key] = d end
  local fields, tabs = M.fromDefs(defs, {
    tabOf = tabOf, skip = skip,
    get = function(key) local cur = g.ownSettingsDefs() for _, d in ipairs(cur) do if d.key == key then return d.value end end end,
    set = function(key, value) g.setSetting(key, value) return true end,
  })
  if #tabs == 0 then return false end
  return M.register({ mod = 'wrench_works', title = 'Wrench Works', icon = 'wrench', order = 10, tabs = tabs, fields = fields })
end
M.registerWrenchWorks = registerWrenchWorks

-- every extension of ours that wants to register is asked once the registry is there (a mod that loaded earlier is asked again)
local function askForSchemas()
  if extensions and extensions.hook then extensions.hook('onSlrrSettingsReady') end
end
M.onExtensionLoaded = function()
  setExtensionUnloadMode(M, 'manual')
  registerWrenchWorks()
  askForSchemas()
  registerMenu()
end
M.onSlrrSettingsReady = function() registerWrenchWorks() end
M.onClientStartMission = function() registerWrenchWorks() registerMenu() end

return M
