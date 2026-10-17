-- Wrench Works: what a part does, read from its own jbeam data, for the catalog's hover card. Pure (tested by tools/stats_test.js).
--   of(part, weightKg) -> { { label, value }, ... }   part: the decoded jbeam part (what jbeamIO.getPart returns)
-- Engines: peak power and torque from the torque curve, the rev range, how much torque the block is rated for. Forced induction: its boost.
-- Anything else shows what its data holds: spring rate, damping, grip, brake torque. Every part gets its weight when it is known.

local M = {}

local KW_TO_HP = 1.34102

local function num(v) return type(v) == 'number' and v == v and v or nil end

local function round(v, step) return math.floor(v / step + 0.5) * step end

-- every number a modifier row like { beamSpring = 5001000 } puts on `key` in the part's sections
local function modifiers(part, key)
  local out = {}
  for _, rows in pairs(part) do
    if type(rows) == 'table' then
      for _, row in ipairs(rows) do
        if type(row) == 'table' and row[1] == nil and num(row[key]) then out[#out + 1] = row[key] end
      end
    end
  end
  return out
end

local function minOf(list) local m for _, v in ipairs(list) do if not m or v < m then m = v end end return m end
local function maxOf(list) local m for _, v in ipairs(list) do if not m or v > m then m = v end end return m end

local function engine(part, rows)
  local e = part.mainEngine
  if type(e) ~= 'table' then return false end
  local peakT, atT, peakP, atP = 0, 0, 0, 0
  for _, row in ipairs(type(e.torque) == 'table' and e.torque or {}) do
    local rpm, t = num(row[1]), num(row[2])
    if rpm and t then
      if t > peakT then peakT, atT = t, rpm end
      local kw = t * rpm / 9549
      if kw > peakP then peakP, atP = kw, rpm end
    end
  end
  if peakP > 0 then
    rows[#rows + 1] = { label = 'Peak power', value = string.format('%d hp at %d rpm', round(peakP * KW_TO_HP, 1), round(atP, 50)) }
    rows[#rows + 1] = { label = 'Peak torque', value = string.format('%d Nm at %d rpm', round(peakT, 1), round(atT, 50)) }
  end
  local idle, top = num(e.idleRPM), num(e.revLimiterRPM) or num(e.maxRPM)
  if top then rows[#rows + 1] = { label = 'Rev range', value = (idle and (round(idle, 50) .. ' - ') or 'to ') .. round(top, 50) .. ' rpm' } end
  local rating = num(e.maxTorqueRating)
  if rating then rows[#rows + 1] = { label = 'Strength', value = string.format('rated for %d Nm', round(rating, 1)) } end
  local wall = num(e.cylinderWallTemperatureDamageThreshold)
  if wall then rows[#rows + 1] = { label = 'Heat limit', value = string.format('%d C at the cylinder wall', round(wall, 1)) } end
  return true
end

local function induction(part, rows)
  local f = part.turbocharger or part.supercharger
  if type(f) ~= 'table' then return end
  local psi = num(f.wastegateStart) or num(f.maxPressure) or num(f.boostPressure)
  rows[#rows + 1] = { label = part.turbocharger and 'Turbo' or 'Supercharger', value = psi and string.format('up to %.1f psi of boost', psi) or 'adds boost' }
end

function M.of(part, weightKg)
  local rows = {}
  if type(part) ~= 'table' then return rows end
  local isEngine = engine(part, rows)
  induction(part, rows)
  if not isEngine then
    local spring = minOf((function() local l = {} for _, v in ipairs(modifiers(part, 'beamSpring')) do if v < 1000000 then l[#l + 1] = v end end return l end)())
    if spring then rows[#rows + 1] = { label = 'Spring rate', value = string.format('%d N/mm', round(spring / 1000, 1)) } end
    local damp = maxOf((function() local l = {} for _, v in ipairs(modifiers(part, 'beamDamp')) do if v < 5000 then l[#l + 1] = v end end return l end)())
    if spring and damp then rows[#rows + 1] = { label = 'Damping', value = tostring(round(damp, 1)) } end
    local grip = maxOf(modifiers(part, 'frictionCoef'))
    if grip then rows[#rows + 1] = { label = 'Grip', value = string.format('%.2f friction', grip) } end
    local brake = maxOf(modifiers(part, 'brakeTorque'))
    if brake then rows[#rows + 1] = { label = 'Brake torque', value = string.format('%d Nm', round(brake, 10)) } end
  end
  if num(weightKg) and weightKg > 0 then
    rows[#rows + 1] = { label = 'Weight', value = weightKg >= 10 and string.format('%d kg', round(weightKg, 1)) or string.format('%.1f kg', weightKg) }
  end
  return rows
end

return M
