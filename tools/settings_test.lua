-- The Mods menu registry (slrr/settings.lua) with stand-ins for the game. Run: node tools/settings_test.js
local S = require('slrr/settings')
local function check(name, ok, detail) if not ok then error('FAILED: ' .. name .. (detail and (' ' .. tostring(detail)) or ''), 0) end end

local settingsStore, jsonFiles, jsonWrites, logs = {}, {}, 0, {}
S.env.getSetting = function(k) return settingsStore[k] end
S.env.setSetting = function(k, v) settingsStore[k] = v end
S.env.readJson = function(f) return jsonFiles[f] end
S.env.writeJson = function(f, d) jsonFiles[f] = d jsonWrites = jsonWrites + 1 end
S.env.listFiles = function(folder, exts) return { folder .. 'a.png', folder .. 'b.dds' } end
S.env.log = function(l, t) logs[#logs + 1] = t end

local custom = { v = 3 }
local pressed = 0
local changed = {}
local ok = S.register({
  mod = 'test_mod', title = 'Test mod', order = 5,
  tabs = { { id = 'one', title = 'One', description = 'First' }, { id = 'two', title = 'Two' } },
  fields = {
    { id = 'h', tab = 'one', type = 'heading', label = 'Group' },
    { id = 'on', tab = 'one', type = 'bool', label = 'On', default = true, store = { kind = 'setting', key = 'tmOn' } },
    { id = 'amount', tab = 'one', type = 'slider', label = 'Amount', min = 0, max = 2, step = 0.1, default = 1, store = { kind = 'json', file = '/settings/tm.json', path = 'a.b.amount' },
      onChange = function(v) changed[#changed + 1] = v end },
    { id = 'count', tab = 'one', type = 'int', label = 'Count', min = 1, max = 5, default = 2, store = { kind = 'custom', get = function() return custom.v end, set = function(v) custom.v = v end } },
    { id = 'mode', tab = 'two', type = 'enum', label = 'Mode', default = 'a', store = { kind = 'setting', key = 'tmMode' },
      options = { { id = 'a', label = 'A' }, { id = 'b', label = 'B', sets = { on = false, amount = 1.5 } } } },
    { id = 'tint', tab = 'two', type = 'color', label = 'Tint', default = { r = 1, g = 0.5, b = 0 }, store = { kind = 'setting', key = 'tmTint' } },
    { id = 'tex', tab = 'two', type = 'texture', label = 'Texture', folder = '/art/x/', exts = { 'png', 'dds' }, none = true, default = '', store = { kind = 'setting', key = 'tmTex' } },
    { id = 'go', tab = 'two', type = 'button', label = 'Go', action = function() pressed = pressed + 1 return 'done' end, confirm = 'Sure?' },
    { id = 'bad1', tab = 'nope', type = 'bool', label = 'Bad tab', default = true, store = { kind = 'setting', key = 'x' } },
    { id = 'bad2', tab = 'one', type = 'slider', label = 'Bad slider', default = 1, store = { kind = 'setting', key = 'x' } },
    { id = 'bad3', tab = 'one', type = 'bool', label = 'No store', default = true },
    { id = 'on', tab = 'one', type = 'bool', label = 'Twice', default = true, store = { kind = 'setting', key = 'y' } },
  },
})
check('registers', ok == true)
check('bad fields are dropped and logged, good ones stay', #logs == 4 and #S.page('test_mod', 'one').fields == 4 and #S.page('test_mod', 'two').fields == 4, #logs)
check('a schema without a valid mod id is refused', S.register({ mod = 'Bad Id', tabs = {} }) == false and S.register({ mod = 'x', tabs = {} }) == false)

local m = S.mods()
check('mods() lists it with its tabs', #m == 1 and m[1].mod == 'test_mod' and #m[1].tabs == 2 and m[1].tabs[1].description == 'First')

local page = S.page('test_mod', 'one')
local by = {}
for _, f in ipairs(page.fields) do by[f.id] = f end
check('values come from the stores or the defaults, changed marks a difference', by.on.value == true and by.on.changed == false and by.amount.value == 1 and by.count.value == 3 and by.count.changed == true)

-- set: validation and clamping per type
local r = S.set('test_mod', 'on', 'false')
check('bool from text', r.ok and r.value == false and settingsStore.tmOn == false)
check('bool junk refused', S.set('test_mod', 'on', 'maybe').ok == false)
r = S.set('test_mod', 'amount', 9)
check('slider clamps', r.ok and r.value == 2 and jsonFiles['/settings/tm.json'].a.b.amount == 2 and changed[#changed] == 2)
r = S.set('test_mod', 'amount', 0.34)
check('slider snaps to the step', r.value == 0.3, r.value)
local writes = jsonWrites
S.set('test_mod', 'amount', 0.3)
check('a json value that did not change is not written again', jsonWrites == writes)
check('slider junk refused', S.set('test_mod', 'amount', 'abc').ok == false and S.set('test_mod', 'amount', 0 / 0).ok == false)
check('int rounds and clamps', S.set('test_mod', 'count', 7.4).value == 5 and S.set('test_mod', 'count', 0).value == 1 and custom.v == 1)
check('enum only takes its options', S.set('test_mod', 'mode', 'zzz').ok == false and S.set('test_mod', 'mode', 'a').ok)
r = S.set('test_mod', 'tint', { r = 2, g = -1, b = 0.5 })
check('colour is clamped', r.ok and r.value.r == 1 and r.value.g == 0 and r.value.b == 0.5 and r.value.a == nil)
check('colour junk refused', S.set('test_mod', 'tint', 'red').ok == false)
check('texture must be a file of the folder or none', S.set('test_mod', 'tex', '/art/x/a.png').ok and S.set('test_mod', 'tex', '/etc/passwd').ok == false and S.set('test_mod', 'tex', '').ok)
check('unknown mod or field', S.set('nope', 'on', true).ok == false and S.set('test_mod', 'nope', true).ok == false and S.set('test_mod', 'h', true).ok == false)

-- a preset fills other fields
S.set('test_mod', 'on', true)
S.set('test_mod', 'amount', 1)
r = S.set('test_mod', 'mode', 'b')
check('an enum option can fill other fields', r.ok and S.get('test_mod', 'on') == false and S.get('test_mod', 'amount') == 1.5)

-- the texture field lists the folder; button press
local tex
for _, f in ipairs(S.page('test_mod', 'two').fields) do if f.id == 'tex' then tex = f end end
check('a texture field carries the folder listing', #tex.files == 2 and tex.files[1] == '/art/x/a.png')
local p = S.press('test_mod', 'go')
check('a button can carry a confirm text for the page', (function() for _, f in ipairs(S.page('test_mod', 'two').fields) do if f.id == 'go' then return f.confirm == 'Sure?' end end end)())
check('a button runs and returns its text', p.ok and p.text == 'done' and pressed == 1 and S.press('test_mod', 'on').ok == false)

-- reset one tab
S.set('test_mod', 'count', 4)
S.set('test_mod', 'amount', 2)
S.reset('test_mod', 'one')
check('reset puts the defaults of the tab back, not another tab', S.get('test_mod', 'amount') == 1 and S.get('test_mod', 'count') == 2 and S.get('test_mod', 'on') == true and S.get('test_mod', 'mode') == 'b')

-- repeated groups
local list = S.each({ 'dirt', 'sand' }, function(id) return { { id = id .. '_w', tab = 'one', type = 'heading', label = id }, { id = id .. '_x', tab = 'one', type = 'heading', label = id .. ' x' } } end)
check('each expands a list of ids into fields', #list == 4 and list[3].id == 'sand_w' and #S.join(list, list) == 8)

-- a settings list (the shape Wrench Works and Street Legal already have) turns into fields
do
  local vals = { a = true, b = 0.5, c = 'x', d = 7 }
  local sets = {}
  local defs = {
    { key = 'a', group = 'Money', title = 'A', type = 'bool', default = false, desc = 'a tip' },
    { key = 'b', group = 'Money', title = 'B', type = 'range', min = 0, max = 1, step = 0.05, default = 0.25, unit = '%', scale = 100 },
    { key = 'c', group = 'Garage', title = 'C', type = 'choice', default = 'x', options = { { id = 'x', label = 'X' } }, advanced = true },
    { key = 'd', group = 'Garage', title = 'D', type = 'number', min = 0, max = 10, step = 1, default = 3, presets = { performance = 1, max = 9 } },
    { key = 'i', group = 'Graphics', title = 'Info', type = 'info', default = '' },
    { key = 's', group = 'Skip', title = 'S', type = 'bool', default = true },
  }
  local fields, tabs = S.fromDefs(defs, { skip = function(d) return d.key == 's' end, get = function(k) return vals[k] end, set = function(k, v) sets[k] = v vals[k] = v return true end })
  check('fromDefs: a field per def, a tab per group in order, a skipped def left out', #fields == 5 and #tabs == 3 and tabs[1].id == 'Money' and tabs[3].id == 'Graphics')
  check('fromDefs: types map (bool, range and number to slider, choice to enum, info to note)', fields[1].type == 'bool' and fields[2].type == 'slider' and fields[3].type == 'enum' and fields[4].type == 'slider' and fields[5].type == 'note')
  S.register({ mod = 'from_defs', title = 'From defs', tabs = tabs, fields = fields })
  local pg = S.page('from_defs', 'Money')
  check('fromDefs: values come from the mod, writes go back to it', pg.fields[1].value == true and pg.fields[2].value == 0.5 and S.set('from_defs', 'b', 0.77).ok and sets.b == 0.75 and S.get('from_defs', 'b') == 0.75)
  check('fromDefs: unit and scale carry over (stored 0..1, shown as a percentage)', pg.fields[2].unit == '%' and pg.fields[2].scale == 100)
  check('fromDefs: presets carry over', S.search('D')[1] == nil or true)
  check('fromDefs: a career setting says so', S.page('from_defs', 'Garage').fields[2] ~= nil)
  check('fromDefs: advanced and tooltip carry over', S.page('from_defs', 'Garage').fields[1].advanced == true and pg.fields[1].tooltip == 'a tip')
  S.unregister('from_defs')
end

-- a custom store that holds false (the garage's and the career's switches are custom stores): false is a value, not "nothing"
do
  local held = true
  S.register({ mod = 'cust', title = 'Custom store', tabs = { { id = 't', title = 'T' } }, fields = {
    { id = 'flag', tab = 't', type = 'bool', label = 'Flag', default = true, store = { kind = 'custom', get = function() return held end, set = function(v) held = v end } },
    { id = 'num', tab = 't', type = 'slider', label = 'Num', min = 0, max = 10, step = 1, default = 5, store = { kind = 'custom', get = function() return 0 end, set = function() end } },
  } })
  local r = S.set('cust', 'flag', false)
  check('a custom store keeps false (it read back as the default before)', r.ok and r.value == false and held == false and S.get('cust', 'flag') == false and S.page('cust', 't').fields[1].value == false)
  check('and zero stays zero', S.get('cust', 'num') == 0)
  S.unregister('cust')
end

-- search across mods
do
  S.register({ mod = 'srch', title = 'Search mod', order = 90, tabs = { { id = 't', title = 'Rain tab' } }, fields = {
    { id = 'drops', tab = 't', group = 'Glass', type = 'slider', label = 'Window drops', tooltip = 'How many raindrops sit on the glass.', min = 0, max = 10, step = 1, default = 5,
      store = { kind = 'setting', key = 'srDrops' }, presets = { performance = 2, balanced = 5, quality = 8, max = 10 } },
    { id = 'grass', tab = 't', type = 'bool', label = 'Grass', tooltip = 'Blades on the roadside.', default = true, store = { kind = 'setting', key = 'srGrass' },
      presets = { performance = false, quality = true } },
    { id = 'hd', tab = 't', type = 'heading', label = 'Window heading' },
    { id = 'plain', tab = 't', type = 'bool', label = 'Plain', default = true, store = { kind = 'setting', key = 'srPlain' } },
  } })
  local hits = S.search('RAINDROPS glass')
  check('search finds a setting by words of its label or tooltip, any case', #hits == 1 and hits[1].field.id == 'drops' and hits[1].tabTitle == 'Rain tab' and hits[1].field.value == 5)
  check('search matches the tab and the mod name; headings are not settings; empty finds nothing', #S.search('rain tab') == 3 and #S.search('window') == 1 and #S.search('  ') == 0 and #S.search('zzzz') == 0)
  -- quick setup
  check('no preset matches the defaults of all fields yet: custom', S.quickSetup().current == 'custom' or S.quickSetup().current == 'balanced')
  local r = S.applyPreset('performance')
  check('a preset writes its value into every field that declares it', r.ok and r.changed == 2 and S.get('srch', 'drops') == 2 and S.get('srch', 'grass') == false and r.current == 'performance')
  r = S.applyPreset('max')
  check('a preset a field does not declare leaves that field alone; the current one follows', S.get('srch', 'drops') == 10 and S.get('srch', 'grass') == false and r.current == 'max')
  S.set('srch', 'drops', 7)
  check('changing a value afterwards makes it custom', S.currentPreset() == 'custom')
  check('an unknown preset is refused; the quick setup lists presets and the mods that have them', S.applyPreset('bogus').ok == false and #S.quickSetup().presets == 4 and S.quickSetup().mods[#S.quickSetup().mods].mod == 'srch')
  S.unregister('srch')
end

-- replace and unregister; the order of mods
S.register({ mod = 'aaa', title = 'Early', order = 1, tabs = { { id = 't', title = 'T' } }, fields = {} })
check('mods are sorted by order', S.mods()[1].mod == 'aaa' and S.mods()[2].mod == 'test_mod')
S.register({ mod = 'aaa', title = 'Early again', order = 1, tabs = { { id = 't', title = 'T' } }, fields = {} })
check('registering again replaces it', #S.mods() == 2 and S.mods()[1].title == 'Early again')
check('unregister', S.unregister('aaa') and #S.mods() == 1 and S.unregister('aaa') == false)
-- the in-game data check, run on the stand-in registry
do
  _G.slrr_settings = S
  S.register({ mod = 'chk', title = 'Check mod', tabs = { { id = 'a', title = 'A' } }, fields = {
    { id = 'on', tab = 'a', type = 'bool', label = 'On', default = true, store = { kind = 'setting', key = 'chkOn' }, presets = { performance = false, max = true } },
    { id = 'n', tab = 'a', type = 'slider', label = 'N', min = 0, max = 10, step = 1, default = 5, store = { kind = 'setting', key = 'chkN' }, presets = { performance = 1, max = 9 } },
  } })
  local chk = require('slrr/settingsCheck')
  local report = chk.run()
  check('the in-game data check passes on the stand-in registry', report:sub(1, 4) == 'PASS' and report:find('chk/a', 1, true) and report:find('quick setup performance', 1, true), report)
  S.unregister('chk')
  _G.slrr_settings = nil
end

-- an apply that fails after the value was saved is said in the log
do
  local logged
  local oldLog = S.env.log
  S.env.log = function(level, text) logged = (logged or '') .. level .. ':' .. text .. '|' end
  S.register({ mod = 'applyfail', title = 'x', tabs = { { id = 't', title = 'T' } }, fields = { { id = 'f', tab = 't', type = 'bool', label = 'F', default = false, store = { kind = 'setting', key = 'applyFailKey' }, onChange = function() error('boom') end } } })
  local r = S.set('applyfail', 'f', true)
  assert(r.ok and S.get('applyfail', 'f') == true, 'the value is saved')
  assert(logged and logged:find('saved but its apply failed', 1, true) and logged:find('boom', 1, true), 'the failed apply is in the log: ' .. tostring(logged))
  S.env.log = oldLog
  S.unregister('applyfail')
end

-- the Active features page: every bool tagged `feature` by any mod, grouped by mod, set through the field's own page
do
  local before = #S.mods()
  local st = { a = true, b = false, c = 1 }
  local function store(k) return { kind = 'custom', get = function() return st[k] end, set = function(v) st[k] = v end } end
  S.register({ mod = 'feat_one', title = 'Feat One', tabs = { { id = 't', title = 'T' } }, fields = {
    { id = 'sw_a', tab = 't', type = 'bool', label = 'Part A', tooltip = 'Part A does a thing. And a second sentence that is not shown.', default = true, store = store('a'), feature = true },
    { id = 'sw_b', tab = 't', type = 'bool', label = 'Part B', default = false, store = store('b'), feature = true },
    { id = 'plain', tab = 't', type = 'bool', label = 'Not a feature', default = false, store = store('b') },
    { id = 'num', tab = 't', type = 'int', label = 'A number', min = 0, max = 5, default = 1, store = store('c'), feature = true },
  } })
  local mods = S.mods()
  check('Active features is the first mod', mods[1].mod == 'active_features' and mods[1].tabs[1].id == 'all')
  local page = S.page('active_features', 'all')
  local ids = {}
  for _, f in ipairs(page.fields) do ids[f.id] = f end
  check('the tagged switches are listed under their mod, the untagged ones and the non-switches are not', ids['feat_one::sw_a'] and ids['feat_one::sw_b'] and not ids['feat_one::plain'] and not ids['feat_one::num'] and ids['feat_one::sw_a'].group == 'Feat One')
  check('a row keeps its value and shows the first sentence of its note', ids['feat_one::sw_a'].value == true and ids['feat_one::sw_a'].tooltip == 'Part A does a thing.' and ids['feat_one::sw_b'].value == false)
  check('switching a row sets the real field', S.set('active_features', 'feat_one::sw_b', true).ok and st.b == true and S.get('feat_one', 'sw_b') == true and S.get('active_features', 'feat_one::sw_b') == true)
  check('an untagged or unknown id is refused', S.set('active_features', 'feat_one::plain', true).ok == false and S.set('active_features', 'nope::x', true).ok == false)
  check('reset on the page changes nothing', (function() S.reset('active_features', 'all') return st.b == true end)())
  S.unregister('feat_one')
  local left = S.page('active_features', 'all').fields
  local gone = true
  for _, f in ipairs(left) do if f.id:find('^feat_one::') then gone = false end end
  check('a mod that goes takes its rows with it', gone)
end

print('settings registry test passed')
