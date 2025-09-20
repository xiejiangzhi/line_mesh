local Vec3 = {}
Vec3.__index = Vec3

local function raw_new_vec3(x, y, z)
  local v = setmetatable({ x, y, z }, Vec3)
  return v
end

local function new_vec3(x, y, z)
  if x == nil then
    x, y, z = 0, 0, 0
  elseif type(x) == 'number' then
    if not y then y = x end
    if not z then z = x end
  else
    -- { x, y, z }
    x, y, z = x[1], x[2], x[3]
  end
  local v = setmetatable({ x, y, z }, Vec3)
  return v
end

-- add(x)
-- add(x, y, z)
-- add({ x, y, z })
function Vec3.add(a, x, y, z)
  if type(x) == 'number' then
    a[1] = a[1] + x
    a[2] = a[2] + (y or x)
    a[3] = a[3] + (z or x)
  else
    a[1] = a[1] + x[1]
    a[2] = a[2] + x[2]
    a[3] = a[3] + x[3]
  end
  return a
end

function Vec3.sub(a, x, y, z)
  if type(x) == 'number' then
    a[1] = a[1] - x
    a[2] = a[2] - (y or x)
    a[3] = a[3] - (z or x)
  else
    a[1] = a[1] - x[1]
    a[2] = a[2] - x[2]
    a[3] = a[3] - x[3]
  end
  return a
end

-- mul(x)
-- mul(x, y, z)
-- mul({ x, y, z })
function Vec3.mul(a, x, y, z)
  if type(x) == 'number' then
    a[1] = a[1] * x
    a[2] = a[2] * (y or x)
    a[3] = a[3] * (z or x)
  else
    a[1] = a[1] * x[1]
    a[2] = a[2] * x[2]
    a[3] = a[3] * x[3]
  end
  return a
end

function Vec3.div(a, x, y, z)
  if type(x) == 'number' then
    a[1] = a[1] / x
    a[2] = a[2] / (y or x)
    a[3] = a[3] / (z or x)
  else
    a[1] = a[1] / x[1]
    a[2] = a[2] / x[2]
    a[3] = a[3] / x[3]
  end
  return a
end

function Vec3.length(a)
  return (a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) ^ 0.5
end

function Vec3.distance(a, b)
  local x, y, z = a[1] - b[1], a[2] - b[2], a[3] - b[3]
  return (x * x + y * y + z * z) ^ 0.5
end

function Vec3.normalize(a)
  local len = Vec3.length(a)
  if len == 0 then
    a[1], a[2], a[3] = 1, 0, 0
  else
    Vec3.div(a, len, len, len)
  end
  return a
end

function Vec3.dot(a, b)
  return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

-- a:cross(x, y, z)
-- a:cross({ x, y, z })
function Vec3.cross(a, x, y, z)
  if type(x) == 'number' then
    a[1], a[2], a[3] =
      a[2] * z - a[3] * y,
      a[3] * x - a[1] * z,
      a[1] * y - a[2] * x
  else
    a[1], a[2], a[3] =
      a[2] * x[3] - a[3] * x[2],
      a[3] * x[1] - a[1] * x[3],
      a[1] * x[2] - a[2] * x[1]
  end
  return a
end

function Vec3.clone(a)
  return raw_new_vec3(a[1], a[2], a[3])
end

function Vec3.__add(a, b)
  if type(b) == 'number' then
    return raw_new_vec3(a[1] + b, a[2] + b, a[3] + b)
  elseif type(a) == 'number' then
    return raw_new_vec3(a + b[1], a + b[2], a + b[3])
  else
    return raw_new_vec3(a[1] + b[1], a[2] + b[2], a[3] + b[3])
  end
end

function Vec3.__sub(a, b)
  if type(b) == 'number' then
    return raw_new_vec3(a[1] - b, a[2] - b, a[3] - b)
  elseif type(a) == 'number' then
    return raw_new_vec3(a - b[1], a - b[2], a - b[3])
  else
    return raw_new_vec3(a[1] - b[1], a[2] - b[2], a[3] - b[3])
  end
end

function Vec3.__mul(a, b)
  if type(b) == 'number' then
    return raw_new_vec3(a[1] * b, a[2] * b, a[3] * b)
  elseif type(a) == 'number' then
    return raw_new_vec3(a * b[1], a * b[2], a * b[3])
  else
    return raw_new_vec3(a[1] * b[1], a[2] * b[2], a[3] * b[3])
  end
end

function Vec3.__div(a, b)
  if type(b) == 'number' then
    return raw_new_vec3(a[1] / b, a[2] / b, a[3] / b)
  elseif type(a) == 'number' then
    return raw_new_vec3(a / b[1], a / b[2], a / b[3])
  else
    return raw_new_vec3(a[1] / b[1], a[2] / b[2], a[3] / b[3])
  end
end

function Vec3.__unm(a)
  return raw_new_vec3(-a[1], -a[2], -a[3])
end

function Vec3.__tostring(a)
  return ('Vec3(%f, %f, %f)'):format(a[1], a[2], a[3])
end

function Vec3.__index(v, k)
  if type(k) == 'number' then
    return rawget(v, k)
  elseif type(k) == 'string' then
    if k == 'x' then
      return v[1]
    elseif k == 'y' then
      return v[2]
    elseif k == 'z' then
      return v[3]
    else
      return Vec3[k]
    end
  end
end

Vec3.new = new_vec3
Vec3.raw_new = raw_new_vec3

setmetatable(Vec3, {
  __call = function(t, ...)
    return new_vec3(...)
  end
})

return Vec3