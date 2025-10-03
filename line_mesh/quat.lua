local Vec3
if _VERSION == 'Luau' then
  Vec3 = require('./vec3')
else
  local mdir = (...):gsub("%.%w+$", '')
  Vec3 = require(mdir..'.vec3')
end

local Quat = {}
Quat.__index = Quat

local function FromAngleAxis(angle, ax, ay, az)
  local s, c = math.sin(angle * .5), math.cos(angle * .5)
  local length = (ax * ax + ay * ay + az * az) ^ .5
  if length > 0 then s = s / length end
  return ax * s, ay * s, az * s, c
end

local function QuatBetweenVec3(u, v)
  local dot = Vec3.dot(u, v)
  if dot > 0.99999999 then
    return 0, 0, 0, 1
  elseif dot < -0.99999999 then
    local axis = Vec3.cross({ 1, 0, 0 }, u)
    if Vec3.length(axis) < 0.00000001 then axis = Vec3.cross({ 0, 1, 0 }, u) end
    return FromAngleAxis(math.pi, axis[1], axis[2], axis[3])
  else
    local x, y, z =
      u[2] * v[3] - u[3] * v[2],
      u[3] * v[1] - u[1] * v[3],
      u[1] * v[2] - u[2] * v[1]
    local w = 1 + dot
    local length = (x * x + y * y + z * z + w * w) ^ .5
    if length == 0 then
      return x, y, z, w
    else
      return x / length, y / length, z / length, w / length
    end
  end
end

local function RotateVec3(q, x, y, z)
  local v1 = Vec3.cross({ q[1], q[2], q[3] }, x, y, z)
  local v2 = Vec3.cross({ q[1], q[2], q[3] }, v1)
  return
    x + (v1[1] * q[4] + v2[1]) * 2,
    y + (v1[2] * q[4] + v2[2]) * 2,
    z + (v1[3] * q[4] + v2[3]) * 2
end

local function raw_new_quat(x, y, z, w)
  local q = setmetatable({ x, y, z, w }, Quat)
  return q
end

local function new_quat(x, y, z, w, is_raw)
  if x == nil then
    x, y, z, w = 0, 0, 0, 1
  elseif type(x) == 'number' then
    if not is_raw then
      x, y, z, w = FromAngleAxis(x, y, z, w)
    end
  elseif x.__index == Vec3 or #x == 3 then
    if y and (y.__index == Vec3 or #y == 3) then
      x, y, z, w = QuatBetweenVec3(x, y)
    else
      x, y, z, w = QuatBetweenVec3({ 0, 0, -1 }, x)
    end
  else
    -- { x, y, z, w }
    x, y, z, w = x[1], x[2], x[3], x[4]
  end
  local q = setmetatable({ x, y, z, w }, Quat)
  return q
end

function Quat.direction(q)
  local x = -2 * q[1] * q[3] - 2 * q[4] * q[2]
  local y = -2 * q[2] * q[3] + 2 * q[4] * q[1]
  local z = -1 + 2 * q[3] * q[1] + 2 * q[2] * q[2]
  return Vec3.raw_new(x, y, z)
end

function Quat.conjugate(q)
  return new_quat(-q[1], -q[2], -q[3], q[4])
end

function Quat.clone(q)
  return new_quat(q[1], q[2], q[3], q[4])
end

function Quat.length(q)
  return (q[1] * q[1] + q[2] * q[2] + q[3] * q[3] + q[4] * q[4]) ^ .5
end

function Quat.to_angle_axis(q)
  local x, y, z, w = q[1], q[2], q[3], q[4]
  local length = q:length()
  if length ~= 0 then
    x, y, z, w = x / length, y / length, z / length, w / length
  end

  local s = math.sqrt(1 - w * w)
  if s < .0001 then s = 1 else s = 1 / s end
  return 2 * math.acos(w), x * s, y * s, z * s
end

local function quat_mul(a, b)
  return a[1] * b[4] + a[4] * b[1] + a[2] * b[3] - a[3] * b[2],
    a[2] * b[4] + a[4] * b[2] + a[3] * b[1] - a[1] * b[3],
    a[3] * b[4] + a[4] * b[3] + a[1] * b[2] - a[2] * b[1],
    a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3]
end

-- mul(quat, quat) -> quat
-- mul(quat, { x, y, z, w }) -> quat
-- mul(quat, vec3) -> vec3
-- mul(quat, { x, y, z }) -> vec3
function Quat.mul(a, b)
  if b.__index == Vec3 or #b == 3 then
    return Vec3.raw_new(RotateVec3(a, b[1], b[2], b[3]))
  else
    a[1], a[2], a[3], a[4] = quat_mul(a, b)
    return a
  end
end

function Quat.__mul(a, b)
  if b.__index == Vec3 or #b == 3 then
    return Vec3.raw_new(RotateVec3(a, b[1], b[2], b[3]))
  elseif b.__index == Quat or #b == 4 then
    local x, y, z, w = quat_mul(a, b)
    local q = setmetatable({ x, y, z, w }, Quat)
    return q
  else
    error("Invalid multiple object for Quat")
  end
end

function Quat.__tostring(q)
  return ('Quat(%f, %f, %f, %f)'):format(q[1], q[2], q[3], q[4])
end

function Quat.__index(q, k)
  if type(k) == 'number' then
    return rawget(q, k)
  elseif k == 'x' then
    return q[1]
  elseif k == 'y' then
    return q[2]
  elseif k == 'z' then
    return q[3]
  elseif k == 'w' then
    return q[4]
  else
    return Quat[k]
  end
end

Quat.new = new_quat
Quat.raw_new = raw_new_quat

setmetatable(Quat, {
  __call = function(t, ...)
    return new_quat(...)
  end
})

return Quat