local LineMesh = require 'line_mesh'
local ffi = require 'ffi'

-- { { pass_fn_name, ...args }, ... }
local debug_draws = {}
local Meshes = {}

LineMesh.debug_draw = function(...)
  debug_draws[#debug_draws + 1] = { n = select('#', ...), ... }
end

local function add_line(points, radius, seg, _opts)
  local opts = { debug_draws = debug_draws }
  if _opts then
    for k, v in pairs(_opts) do
      opts[k] = v
    end
  end
  local st = os.clock()
  local ok, vlist, ilist, line_len, vtotal, itotal = xpcall(LineMesh.build, function(err)
    print(err)
    print(debug.traceback())
  end, points, radius, seg, opts)
  local cost = (os.clock() - st) * 1000
  print(string.format(
    'add line, points: %4i, cost: %7.4f ms. vtotal: %5i, itotal: %6i',
    #points, cost, vtotal or 0, itotal or 0
  ))

  local debug_line = {}
  for i, p in ipairs(points) do
    debug_line[i] = Vec3(p[1], p[2], p[3])
  end

  if ok then
    local mesh = lovr.graphics.newMesh({
      { name = 'VertexPosition', type = 'vec3' },
      { name = 'VertexNormal', type = 'vec3' },
      { name = 'VertexUV', type = 'vec2' },
      { name = 'VertexColor', type = 'vec4' },
    }, vtotal)

    if type(ilist) == 'cdata' then
      local blob = lovr.data.newBlob(vtotal * 12 * 4)
      local ptr = blob:getPointer()
      ffi.copy(ptr, vlist, vtotal * 12 * 4)
      mesh:setVertices(blob)
      ffi.copy(ptr, ilist, itotal * 4)
      mesh:setIndices(blob, 'u32')
    else
      mesh:setVertices(vlist)
      mesh:setIndices(ilist)
    end
    Meshes[#Meshes + 1] = { mesh, debug_line }
  else
    Meshes[#Meshes + 1] = { nil, debug_line }
  end
end

add_line({
  { 0.2, 0.2, 0 },
  { 1, 1, -1 },
}, 0.2, 8, {
  colors = { { 1, 0, 0 }, { 0, 0, 1 } }
})

add_line({
  { 1, 0.2, 0 },
  { 2, 0.2, 0 },
  { 2, 2, 0 },
  { 2, 2, 2 },
  { 2, 2.5, 0 },
  { 1.9, 2.5, 2 },
  -- { 1.899, 2.5, 1.9 }, -- bad point
}, nil, 6, {
  closed = true
})

add_line({
  { 0.3, 0.2, 0.3 },
  { 0.5, 0.2, 0.3 },
  { 1.0, 0.2, 0.3 },
  { 1.5, 0.2, 0.3 },
}, 0.2, 8, {
  colors = { { 1, 0, 0 }, { 0, 0, 1 } }
})

do
  add_line({
    { 1, 0.2, 0.5 },
    { 1.5, 0.2, 1 },
    { 1, .2, 1.5 },
    { 0.5, .2, 1 },
  }, nil, 8, {
    closed = true
  })

  local ps = {}
  for i = 1, 32 do
    local phi = i / 32 * math.pi * 2
    local x, y = math.cos(phi) * 0.25, math.sin(phi) * 0.25
    ps[#ps + 1] = { 1 + x, 0.2, 1 + y }
  end
  add_line(ps, 0.05, 8, { closed = true })

  local s = 0.1
  add_line({
    { 1, 0.2, 1 - s },
    { 1 + s, 0.2, 1 },
    { 1, .2, 1 + s },
    { 1 - s, .2, 1 },
  }, 0.05, 8, {
    closed = true
  })
end

do
  local ps = {}
  for i = 0, 200 do
    local z = i * 0.03
    ps[#ps + 1] = {
      -0.5 + math.sin(z * math.pi * 3) * 0.5,
      0.2 + (i >= 100 and ((i - 100) * 0.01) or 0),
      1 + -z + (i >= 100 and ((i - 100) * 0.05) or 0)
    }
  end
  add_line(ps)

  ps = {}
  for i = 0, 200 do
    local z = i * 0.03
    ps[#ps + 1] = {
      -2.5 + math.sin(z * math.pi * 3) * 0.5,
      0.2 + (i >= 100 and ((i - 100) * 0.01) or 0),
      1 + -z + (i >= 100 and ((i - 100) * 0.05) or 0)
    }
  end
  add_line(ps, 0.01, 3, { output_type = 'cdata' })
end

do
  add_line({
    { 0, 0.2, 2 },
    { 1, 0.7, 2 },
    { 2, 0.3, 2 },
    { 3, 0.5, 2 },
  }, nil, 10, {
    colors = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 1, 1 } },
    widths = { 0.05, 0.2, 0.02, 0.5 }
  })
end

do
  local ps = {}
  local x, y, z = 5, 5, -2
  math.randomseed(123)
  for i = 1, 1000 do
    ps[i] = { x, y, z }
    x = x + math.random() - 0.5
    y = y + math.random() - 0.5
    z = z + math.random() - 0.5
  end
  add_line(ps, nil, nil, { output_type = 'cdata' })
end


local function draw_debug_data(pass)
  for i, mesh_info in ipairs(Meshes) do
    for j, p in ipairs(mesh_info[2]) do
      pass:sphere(p, 0.001)
      pass:text(tostring(j), p + vec3(0, 0.1, 0), 0.05)
    end
  end

  for i, debug_draw in ipairs(debug_draws) do
    pass[debug_draw[1]](pass, unpack(debug_draw, 2, debug_draw.n))
  end
end

local draw_shader = lovr.graphics.newShader([[
vec4 lovrmain() {
  return DefaultPosition;
}
]], [[
uniform int ColorMode;
vec4 lovrmain() {
  vec4 col;
  if (ColorMode == 2) {
    col = vec4(Normal, 1);
  } else if (ColorMode == 3) {
    col = vec4(fract(PositionWorld * 4), 1);
  } else if (ColorMode == 4) {
    col = vec4(vec3(UV.x), 1);
  } else if (ColorMode == 5) {
    col = vec4(vec3(UV.y), 1);
  } else {
    col = DefaultColor;
  }
  return col;
}
]])
local ColorMode = 1
local ColorModes = {
  'Color',
  'Normal',
  'Positioin',
  'UV.x', 'UV.y',
  'Wireframe', 'Wireframe-Cull'
}

local time = 0
local Paused = false
function lovr.update(dt)
  if not Paused then
    time = time + dt
  end
end

function lovr.draw(pass)
  pass:transform(vec3(0, 0, -3))
  pass:setColor(0.4, 0.4, 0.4)
  pass:line(vec3(-10, 0, 0), vec3(10, 0, 0))
  pass:line(vec3(0, 0, -10), vec3(0, 0, 10))

  pass:setColor(1, 1, 1)
  for i, mesh_info in ipairs(Meshes) do
    pass:line(mesh_info[2])
  end

  draw_debug_data(pass)

  for x = -10, 10, 0.5 do
    for y = -10, 10, 0.5 do
      if (x + y) * 2 % 2 == 1 then
        pass:setColor(0.2, 0.2, 0.2, 1)
      else
        pass:setColor(0.5, 0.5, 0.5, 1)
      end
      pass:plane(vec3(x, 0, y), vec2(0.5), quat(math.pi * 0.5, 1, 0, 0))
    end
  end

  if ColorModes[ColorMode] == 'Wireframe-Cull' then
    pass:setFaceCull('back')
    pass:setColor(1, 1, 1, 1)
    pass:setWireframe(true)
  elseif ColorModes[ColorMode] == 'Wireframe' then
    pass:setFaceCull('none')
    pass:setColor(1, 1, 1, 1)
    pass:setWireframe(true)
  else
    pass:setFaceCull('back')
    pass:setColor(1, 1, 1, 0.15)
    pass:setShader(draw_shader)
    pass:send('ColorMode', ColorMode)
  end
  for i, mesh_info in ipairs(Meshes) do
    if mesh_info[1] then
      pass:draw(mesh_info[1])
    end
  end
end

function lovr.keypressed(key)
  if key == 'space' then
    Paused = not Paused
  else
    local i = tonumber(key)
    if i and ColorModes[i] then
      ColorMode = i
      print('ColorMode: '..ColorModes[i])
    end
  end
end
