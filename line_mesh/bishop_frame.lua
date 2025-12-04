local M = {}

local mdir = (...):gsub("%.[%w_]+$", '')
local Vec3 = require(mdir..'.vec3')

local ffi = require 'ffi'

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
out_ptr: optional, cdata float[#points * 11]
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
local TmpTangents, TmpTangentsLen
function M.calc(points, out_ptr)
  local count = #points
  assert(count >= 2, 'Total points must >= 2')

  -- tangents
  local tangents
  if TmpTangentsLen and TmpTangentsLen > count then
    tangents = TmpTangents
  else
    TmpTangents = ffi.new('double[?]', count * 3)
    TmpTangentsLen = count
    tangents = TmpTangents
  end
  for i = 1, count do
    local p = points[i]
    local p2
    if i < count then
      p2 = points[i + 1]
    else
      p2 = p
      p = points[i - 1]
    end
    local idx = (i - 1) * 3
    tangents[idx], tangents[idx + 1], tangents[idx + 2] = NormalizeNum(
      p2[1] - p[1], p2[2] - p[2],  p2[3] - p[3]
    )
  end

  local t0x, t0y, t0z = tangents[0], tangents[1], tangents[2]
  local cnx, cny, cnz
  if Abs(Dot(t0x, t0y, t0z, 0, 1, 0)) > 0.99 then
    cnx, cny, cnz = NormalizeNum(Cross(t0x, t0y, t0z, 1, 0, 0))
  else
    cnx, cny, cnz = NormalizeNum(Cross(t0x, t0y, t0z, 0, 1, 0))
  end
  local dist = 0

  local frames_data = out_ptr or ffi.new('float[?]', count * 11)
  local ptr = frames_data
  for i = 1, count do
    local tin_x, tin_y, tin_z
    local tout_x, tout_y, tout_z
    if i == 1 then
      tin_x, tin_y, tin_z = tangents[0], tangents[1], tangents[2]
      tout_x, tout_y, tout_z = tin_x, tin_y, tin_z
    elseif i == count then
      local idx = (count - 2) * 3
      tin_x, tin_y, tin_z = tangents[idx], tangents[idx + 1], tangents[idx + 2]
      tout_x, tout_y, tout_z = tin_x, tin_y, tin_z
    else
      local idx_in = (i - 2) * 3
      tin_x, tin_y, tin_z = tangents[idx_in], tangents[idx_in + 1], tangents[idx_in + 2]
      local idx_out = (i - 1) * 3
      tout_x, tout_y, tout_z = tangents[idx_out], tangents[idx_out + 1], tangents[idx_out + 2]
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

    ptr[0], ptr[1], ptr[2] = point[1], point[2], point[3]
    ptr[3], ptr[4], ptr[5] = nx, ny, nz
    ptr[6], ptr[7], ptr[8] = bnx, bny, bnz
    ptr[9], ptr[10] = miterScale, dist
    ptr = ptr + 11
  end

  return frames_data
end

return M
