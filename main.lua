local LineMesh = require 'line_mesh'
local ffi = require 'ffi'

-- { { pass_fn_name, ...args }, ... }
local debug_draws = {}
local Meshes = {}

LineMesh.debug_draw = function(...)
  debug_draws[#debug_draws + 1] = { n = select('#', ...), ... }
end

local err_cb = function(err)
  print(err)
  print(debug.traceback())
end

local function add_line(points, radius, seg, opts)
  local st = os.clock()
  local ok, vlist, ilist, line_len, vtotal, itotal = xpcall(
    LineMesh.build, err_cb, points, radius, seg, opts
  )
  local cost = (os.clock() - st) * 1000
  print(string.format(
    'add line, points: %4i, cost: %7.4f ms. len: %7.2f, vtotal: %5i, itotal: %6i',
    #points, cost, line_len, vtotal or 0, itotal or 0
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
  add_line(ps, 0.04, 3, { output_type = 'cdata' })
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

local DrawSet = {}
local DrawFunc = nil

local time = 0

function lovr.update(dt)
  time = time + dt
end

function lovr.draw(pass)
  (DrawFunc or DrawSet.default)(pass)
end

-- change color mode by 1 - #ColorModes
function lovr.keypressed(key)

  if lovr.system.isKeyDown('lalt') then
    if key == '1' then
      DrawFunc = DrawSet.default
      print('draw set: default')
    elseif key == '2' then
      DrawFunc = DrawSet.cpu_mesh
      print('draw set: cpu_mesh')
    elseif key == '3' then
      DrawFunc = DrawSet.gpu_mesh
      print('draw set: gpu_mesh')
    elseif key == '4' then
      DrawFunc = DrawSet.static_mesh
      print('draw set: static_mesh')
    end
  else
    local i = tonumber(key)
    if i and ColorModes[i] then
      ColorMode = i
      print('ColorMode: '..ColorModes[i])
    end
  end
end


function DrawSet.default(pass)
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

  local gpoints = {
    { 1, 0.5, 3 },
    { -1, 0.5, 3 },
    { -1, 1.5, 3 },
    { -1, 1.5, 4 },
    { 0, 1, 3 },
    { -0.5, 1.5, 4 },
  }
  local gline1 = LineMesh.gpu_build(pass, gpoints, 0.1, 8, {
    colors = {
      { 1, 0, 0, 1 },
      { 0, 1, 0, 1 },
      { 0, 0, 1, 1 },
      { 0, 1, 1, 1 },
      { 1, 1, 0, 1 },
      { 1, 0, 1, 1 },
    }
  })
  pass:mesh(gline1.vertex_buffer, gline1.index_buffer, { 0, 0, 0 })

  local gline2 = LineMesh.gpu_build(pass, gpoints, 0.1, 8, {
    colors = {
      { 1, 0, 0, 1 },
      { 0, 1, 0, 1 },
      { 0, 0, 1, 1 },
      { 0, 1, 1, 1 },
      { 1, 1, 0, 1 },
      { 1, 0, 1, 1 },
    },
    widths = { 0.2, 2, 2.5, 1.5, 1.0, 0.8 }
  })
  pass:mesh(gline2.vertex_buffer, gline2.index_buffer, { 0, 2, 0 })
end

local function gen_points(dir, n)
  local r = {}
  for i = 1, n do
    local l = i * 0.5
    r[#r + 1] = {
      dir[1] * l,
      dir[2] * l,
      dir[3] * l
    }
  end
  return r
end

local TestLinesN = 128
local Lines = {}
for i = 1, TestLinesN do
  local angle = i / TestLinesN * math.pi * 2
  local x, z = math.cos(angle), math.sin(angle)
  local points = gen_points({ x, 0, z }, 100)

  Lines[i] = {
    raw_points = points,
    points = nil
  }
end

local function update_test_lines()
  for i, line in ipairs(Lines) do
    local ps = line.points
    if not ps then
      ps = {}
      line.points = ps
      for j, p in ipairs(line.raw_points) do
        ps[j] = { p[1], p[2], p[3] }
      end
    end
    for j, p in ipairs(line.raw_points) do
      ps[j][2] = p[2] + math.sin(time + i + j) * 0.5
    end
  end
end

function DrawSet.cpu_mesh(pass)
  local fps = lovr.timer.getFPS()
  pass:text('FPS: '..fps, { 0, 2, 0})
  pass:line({ -10, 0, 0 }, { 10, 0, 0 })
  pass:line({ 0, 0, -10 }, { 0, 0, 10 })

  update_test_lines()
  for i, line in ipairs(Lines) do
    local vlist, ilist, len, vtotal, itotal = LineMesh.build(
      line.points, 0.1, 8, { output_type = 'cdata' }
    )

    local mesh = line.mesh or lovr.graphics.newMesh({
      { name = 'VertexPosition', type = 'vec3' },
      { name = 'VertexNormal', type = 'vec3' },
      { name = 'VertexUV', type = 'vec2' },
      { name = 'VertexColor', type = 'vec4' },
    }, vtotal)
    line.mesh = mesh
    local blob = line.blob or lovr.data.newBlob(vtotal * 12 * 4)
    line.blob = blob

    local ptr = blob:getPointer()
    ffi.copy(ptr, vlist, vtotal * 12 * 4)
    mesh:setVertices(blob)
    ffi.copy(ptr, ilist, itotal * 4)
    mesh:setIndices(blob, 'u32')
    pass:draw(mesh)
  end
end

function DrawSet.gpu_mesh(pass)
  local fps = lovr.timer.getFPS()
  pass:text('FPS: '..fps, { 0, 2, 0})
  pass:line({ -10, 0, 0 }, { 10, 0, 0 })
  pass:line({ 0, 0, -10 }, { 0, 0, 10 })

  update_test_lines()
  for i, line in ipairs(Lines) do
    line.gpu_data = LineMesh.gpu_build(pass, line.points, 0.1, 8, nil, line.gpu_data)
    pass:mesh(line.gpu_data.vertex_buffer, line.gpu_data.index_buffer)
  end
end

function DrawSet.static_mesh(pass)
  local fps = lovr.timer.getFPS()
  pass:text('FPS: '..fps, { 0, 2, 0})
  pass:line({ -10, 0, 0 }, { 10, 0, 0 })
  pass:line({ 0, 0, -10 }, { 0, 0, 10 })

  if not Lines[1].points then
    update_test_lines()
  end
  for i, line in ipairs(Lines) do
    if not line.gpu_data then
      line.gpu_data = LineMesh.gpu_build(pass, line.points, 0.1, 8, nil, line.gpu_data)
    end
    pass:mesh(line.gpu_data.vertex_buffer, line.gpu_data.index_buffer)
  end
end