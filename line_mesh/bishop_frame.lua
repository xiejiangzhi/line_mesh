local M = {}

local Vec3
if _VERSION == 'Luau' then
  Vec3 = require('./vec3')
else
  local mdir = (...):gsub("%.[%w_]+$", '')
  Vec3 = require(mdir..'.vec3')
end

local Abs, Min, Max = math.abs, math.min, math.max
local Sqrt = math.sqrt
local Cos, Sin = math.cos, math.sin
local ACos = math.acos
local NormalizeNum = Vec3.normalize_num

local function Dot(x, y, z, x2, y2, z2)
  return x * x2 + y * y2 + z * z2
end

function Cross(x, y, z, x2, y2, z2)
  return
    y * z2 - z * y2,
    z * x2 - x * z2,
    x * y2 - y * x2
end

local function Vec3Rotate(x, y, z, ax, ay, az, angle)
  local cosA = Cos(angle)
  local sinA = Sin(angle)

  -- v * cosA
  local tx, ty, tz = x * cosA, y * cosA, z * cosA
  -- (k x v) * sinA
  local t2x, t2y, t2z = Cross(ax, ay, az, x, y, z)
  t2x = t2x * sinA
  t2y = t2y * sinA
  t2z = t2z * sinA
  -- k * (k . v) * (1 - cosA)
  local kdv = ax * x + ay * y + az * z
  local s3 = 1 - cosA
  local t3x = ax * kdv * s3
  local t3y = ay * kdv * s3
  local t3z = az * kdv * s3

  return tx + t2x + t3x, ty + t2y + t3y, tz + t2z + t3z
end

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

  -- tangents
  local ts_x, ts_y, ts_z = {}, {}, {}
  for i = 1, count do
    local p = points[i]
    local p2
    if i < count then
      p2 = points[i + 1]
    else
      p2 = p
      p = points[i - 1]
    end
    ts_x[i], ts_y[i], ts_z[i] = NormalizeNum(p2[1] - p[1], p2[2] - p[2],  p2[3] - p[3])
  end

  local t0x, t0y, t0z = ts_x[1], ts_y[1], ts_z[1]
  local cnx, cny, cnz
  if Abs(Dot(t0x, t0y, t0z, 0, 1, 0)) > 0.99 then
    cnx, cny, cnz = NormalizeNum(Cross(t0x, t0y, t0z, 1, 0, 0))
  else
    cnx, cny, cnz = NormalizeNum(Cross(t0x, t0y, t0z, 0, 1, 0))
  end
  local dist = 0

  local frames = {}
  for i = 1, count do
    local tin_x, tin_y, tin_z
    local tout_x, tout_y, tout_z
    if i == 1 then
      tin_x, tin_y, tin_z = ts_x[1], ts_y[1], ts_z[1]
      tout_x, tout_y, tout_z = tin_x, tin_y, tin_z
    elseif i == count then
      local idx = count - 1
      tin_x, tin_y, tin_z = ts_x[idx], ts_y[idx], ts_z[idx]
      tout_x, tout_y, tout_z = tin_x, tin_y, tin_z
    else
      local idx_in = i - 1
      tin_x, tin_y, tin_z = ts_x[idx_in], ts_y[idx_in], ts_z[idx_in]
      tout_x, tout_y, tout_z = ts_x[i], ts_y[i], ts_z[i]
    end
    local point = points[i]

    if i > 1 then
      dist = dist + points[i-1]:distance(point)

      local ax, ay, az = Cross(tin_x, tin_y, tin_z, tout_x, tout_y, tout_z)
      local dotVal = Dot(tin_x, tin_y, tin_z, tout_x, tout_y, tout_z)
      dotVal = Max(-1, Min(1, dotVal))

      local len2 = ax * ax + ay * ay + az * az
      if len2 > 1e-12 then
        local s = 1 / Sqrt(len2)
        ax, ay, az = ax * s, ay * s, az * s
        cnx, cny, cnz = Vec3Rotate(cnx, cny, cnz, ax, ay, az, ACos(dotVal))
      end
    end

    local tcx, tcy, tcz = NormalizeNum(tin_x + tout_x, tin_y + tout_y, tin_z + tout_z)
    local dotMiter = tcx * tin_x + tcy * tin_y + tcz * tin_z
    local miterScale = 1.0
    if dotMiter > 1e-8 then
      miterScale = 1.0 / dotMiter
    end
    miterScale = Min(miterScale, 5)


    -- local finalNormal = currentNormal
    -- local finalBinormal = Vec3(tOut):cross(finalNormal):normalize()
    local nx, ny, nz = cnx, cny, cnz
    local bnx, bny, bnz = NormalizeNum(Cross(tout_x, tout_y, tout_z, nx, ny, nz))

    if i > 1 and i < count then
      -- finalBinormal = Vec3(bisector):cross(finalNormal):normalize()
      -- finalNormal = Vec3(finalBinormal):cross(bisector):normalize()

      bnx, bny, bnz = NormalizeNum(Cross(tcx, tcy, tcz, nx, ny, nz))
      nx, ny, nz = NormalizeNum(Cross(bnx, bny, bnz, tcx, tcy, tcz))
    end

    frames[i] = {
      point[1], point[2], point[3],
      nx, ny, nz,
      bnx, bny, bnz,
      miterScale,
      dist
    }
  end

  return frames
end

return M
