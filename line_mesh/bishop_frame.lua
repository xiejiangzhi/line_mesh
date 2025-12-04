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
local NormalizeNum = Vec3.normalize_num

--[[
return {
  {
    x, y, z,
    tangent_x, tangent_y, tangent_z,
    nrm_x, nrm_y, nrm_z,
    binrm_x, binrm_y, bi_nrmz,
    miter_scale, dist
  },
   ...
}
]]
function M.calc(points)
  local count = #points
  assert(count >= 2, 'Total points must >= 2')

  local tangents = {}
  for i = 1, count do
    local t
    if i < count then
      t = points[i+1]:clone():sub(points[i]):normalize()
    else
      t = points[i]:clone():sub(points[i-1]):normalize()
    end
    tangents[i] = t
  end

  local t0 = tangents[1]
  local up = { 0, 1, 0 }
  if Abs(t0:dot(up)) > 0.999 then
    up = { 1, 0, 0 }
  end
  local currentNormal = t0:clone():cross(up):normalize()
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
    local point = points[i]

    if i > 1 then
      dist = dist + points[i-1]:distance(point)

      local axis = tIn:clone():cross(tOut)
      local dotVal = tIn:dot(tOut)
      dotVal = Max(-1, Min(1, dotVal))

      if axis:length2() > 1e-12 then
        currentNormal = Vec3.rotate(currentNormal, axis, ACos(dotVal))
      end
    end

    local tcx, tcy, tcz = NormalizeNum(tIn[1] + tOut[1], tIn[2] + tOut[2], tIn[3] + tOut[3])
    local dotMiter = tcx * tIn[1] + tcy * tIn[2] + tcz * tIn[3]
    local miterScale = 1.0
    if dotMiter > 1e-6 then
      miterScale = 1.0 / dotMiter
    end
    miterScale = Min(miterScale, 5)

    -- local finalNormal = currentNormal
    -- local finalBinormal = Vec3(tOut):cross(finalNormal):normalize()
    local cnx, cny, cnz = currentNormal[1], currentNormal[2], currentNormal[3]
    local bnx, bny, bnz = NormalizeNum(tOut:cross_num(cnx, cny, cnz))

    if i > 1 and i < count then
      -- finalBinormal = Vec3(bisector):cross(finalNormal):normalize()
      -- finalNormal = Vec3(finalBinormal):cross(bisector):normalize()

      bnx, bny, bnz = NormalizeNum(Vec3.cross_num2(tcx, tcy, tcz, cnx, cny, cnz))
      cnx, cny, cnz = NormalizeNum(Vec3.cross_num2(bnx, bny, bnz, tcx, tcy, tcz))
    end

    frames[i] = {
      point[1], point[2], point[3],
      cnx, cny, cnz,
      bnx, bny, bnz,
      miterScale,
      dist
    }
  end

  return frames
end

return M
