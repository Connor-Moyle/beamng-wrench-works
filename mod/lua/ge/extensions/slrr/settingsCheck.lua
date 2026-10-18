-- The Mods menu's in-game check at the data level (run by tools/qa/mods_walkthrough.sh through the test connection): for every mod and tab it changes one value, reads the store back and
-- restores it; applies each Quick setup preset and checks the current one; searches. Answers lines "PASS|FAIL|INFO text"; the summary line starts the answer.
-- Usage in the game's Lua console: slrr_settingsCheck.run()  (then slrr_settingsCheck.report())
local M = {}
local lines, fails = {}, 0

local function note(verdict, text)
  if verdict == 'FAIL' then fails = fails + 1 end
  lines[#lines + 1] = verdict .. ' ' .. text
end

-- another value of the same kind that is valid for the field (nil: do not test this one)
local function otherValue(f)
  local v = f.value
  if f.type == 'bool' then return not v end
  if f.type == 'slider' or f.type == 'int' then
    local span = f.max - f.min
    local mid = f.min + span * 0.5
    local candidate = (math.abs((tonumber(v) or 0) - mid) < span * 0.1) and (f.min + span * 0.75) or mid
    if f.type == 'int' then candidate = math.floor(candidate + 0.5) end
    return candidate
  end
  if f.type == 'enum' then
    for _, o in ipairs(f.options or {}) do if o.id ~= v then return o.id end end
  end
  return nil
end

function M.run()
  lines, fails = {}, 0
  local S = rawget(_G, 'slrr_settings')
  if not S then note('FAIL', 'slrr_settings is not loaded (Wrench Works installed?)') return M.report() end
  local mods = S.mods()
  note(#mods > 0 and 'PASS' or 'FAIL', #mods .. ' mods registered: ' .. (function() local t = {} for _, m in ipairs(mods) do t[#t + 1] = m.mod end return table.concat(t, ', ') end)())
  local before = S.quickSetup().current
  for _, m in ipairs(mods) do
    for _, t in ipairs(m.tabs) do
      local page = S.page(m.mod, t.id)
      local tested
      for _, f in ipairs(page.fields) do
        if not tested and f.value ~= nil and not f.advanced and f.type ~= 'button' and f.type ~= 'text' and f.type ~= 'color' and f.type ~= 'texture' then
          local want = otherValue(f)
          if want ~= nil then
            local old = S.get(m.mod, f.id)
            local r = S.set(m.mod, f.id, want)
            local back = S.get(m.mod, f.id)
            local ok = r.ok and (back == r.value)
            S.set(m.mod, f.id, old)
            local restored = S.get(m.mod, f.id) == old
            tested = true
            note(ok and restored and 'PASS' or 'FAIL', string.format('%s/%s: %s changed to %s, read back %s, restored %s', m.mod, t.id, f.id, tostring(want), tostring(back), tostring(restored)))
          end
        end
      end
      if not tested then note('INFO', string.format('%s/%s: no plain value to change (%d fields)', m.mod, t.id, #page.fields)) end
    end
  end
  -- Quick setup: each preset, then the current one; the values before are not restorable one by one, so this is run on a test profile
  local q = S.quickSetup()
  for _, p in ipairs(q.presets) do
    if p.fields > 0 then
      local r = S.applyPreset(p.id)
      note((r.ok and r.current == p.id) and 'PASS' or 'FAIL', string.format('quick setup %s: %d settings set, current is %s', p.id, r.changed or 0, tostring(r.current)))
    else
      note('INFO', 'quick setup ' .. p.id .. ': no setting declares it')
    end
  end
  note('INFO', 'quick setup before the check: ' .. tostring(before) .. ' (the presets above left the settings at the last preset)')
  -- search
  local hits = S.search('rain')
  note(#hits > 0 and 'PASS' or 'INFO', 'search "rain": ' .. #hits .. ' hits')
  note(#S.search('qzqzqz') == 0 and 'PASS' or 'FAIL', 'search for nonsense finds nothing')
  return M.report()
end

function M.report()
  local out = { (fails == 0 and 'PASS' or 'FAIL') .. ' Mods menu data check: ' .. fails .. ' failures, ' .. #lines .. ' lines' }
  for _, l in ipairs(lines) do out[#out + 1] = l end
  return table.concat(out, '\n')
end

return M
