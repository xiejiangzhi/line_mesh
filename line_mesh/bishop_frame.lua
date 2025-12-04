local M = {}

local Vec3
if _VERSION == 'Luau' then
  Vec3 = require('./vec3')
else
  local mdir = (...):gsub("%.[%w_]+$", '')
  Vec3 = require(mdir..'.vec3')
end

local Abs, Min, Max = math.abs, math.min, math.max
local ACos = math.acos

-- return { { pos, tangent, normal, binormal }, ... }
function M.calc(points)
  local count = #points
  assert(count >= 2, 'Total points must >= 2')

  local tangents = {}
  for i = 1, count do
    local t
    if i < count then
      t = (points[i+1] - points[i]):normalize()
    else
      t = (points[i] - points[i-1]):normalize()
    end
    tangents[i] = t
  end

  local t0 = tangents[1]
  local up = { 0, 1, 0 }
  if Abs(t0:dot(up)) > 0.999 then
    up = { 1, 0, 0 }
  end
  local currentNormal = Vec3(t0):cross(up):normalize()
  local dist = 0

  local frames = {}
  for i = 1, count do
    local tIn, tOut
    if i == 1 then
      tIn = tangents[1]
      tOut = tangents[1]
    elseif i == count then
      tIn = tangents[count-1]
      tOut = tangents[count-1]
    else
      tIn = tangents[i-1]
      tOut = tangents[i]
    end

    if i > 1 then
      local tPrev = tangents[i-1]
      dist = dist + points[i-1]:distance(points[i])

      local axis = Vec3(tPrev):cross(tOut)
      local dotVal = tPrev:dot(tOut)
      dotVal = Max(-1, Min(1, dotVal))

      if axis:length2() > 1e-8 then
        local angle = ACos(dotVal)
        currentNormal = Vec3.rotate(currentNormal, axis, angle)
      end
    end

    local bisector = (tIn + tOut):normalize()
    local dotMiter = bisector:dot(tIn)
    local miterScale = 1.0
    if dotMiter > 1e-6 then
      miterScale = 1.0 / dotMiter
    end
    miterScale = Min(miterScale, 5)

    local finalNormal = currentNormal
    local finalBinormal = Vec3(tOut):cross(finalNormal):normalize()

    if i > 1 and i < count then
      finalBinormal = Vec3(bisector):cross(finalNormal):normalize()
      finalNormal = Vec3(finalBinormal):cross(bisector):normalize()
    end

    frames[i] = {
      points[i],
      finalNormal,
      finalBinormal,
      miterScale,
      dist
    }
  end

  return frames
end

return M
