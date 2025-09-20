local LineMesh = require 'line_mesh'

-- { { pass_fn_name, ...args }, ... }
local debug_draws = {}
local Meshes = {}

local function add_line(points, radius, seg, opts)
  local nopts = { debug_draws = debug_draws }
  if opts then
    for k, v in pairs(opts) do
      nopts[k] = v
    end
  end
  local st = os.clock()
  local ok, vlist, ilist, len = xpcall(LineMesh.build, function(err)
    print(err)
    print(debug.traceback())
  end, points, radius, seg, nopts)
  local cost = (os.clock() - st) * 1000
  print(string.format('add line, points: %i, cost: %.4f ms', #points, cost))

  if ok then
    local mesh = lovr.graphics.newMesh({
      { name = 'VertexPosition', type = 'vec3' },
      { name = 'VertexNormal', type = 'vec3' },
      { name = 'VertexUV', type = 'vec2' },
      { name = 'VertexColor', type = 'color' },
    }, #vlist)
    mesh:setVertices(vlist)
    mesh:setIndices(ilist)
    Meshes[#Meshes + 1] = { mesh, points }
  else
    Meshes[#Meshes + 1] = { nil, points }
  end
end

add_line({
  Vec3(0.2, 0.2, 0),
  Vec3(1, 1, -1),
}, 0.2, 8, {
  colors = { { 1, 0, 0 }, { 0, 0, 1 } }
})

add_line({
  Vec3(1, 0.2, 0),
  Vec3(2, 0.2, 0),
  Vec3(2, 2, 0),
  Vec3(2, 2, 2),
  Vec3(2, 2.5, 0),
  Vec3(1.9, 2.5, 2),
  -- Vec3(1.899, 2.5, 1.9), -- bad point
}, nil, 6, {
  closed = true
})

do
  add_line({
    Vec3(1, 0.2, 0.5),
    Vec3(1.5, 0.2, 1),
    Vec3(1, .2, 1.5),
    Vec3(0.5, .2, 1),
  }, nil, 8, {
    closed = true
  })

  local ps = {}
  for i = 1, 32 do
    local phi = i / 32 * math.pi * 2
    local x, y = math.cos(phi) * 0.25, math.sin(phi) * 0.25
    ps[#ps + 1] = Vec3(1 + x, 0.2, 1 + y)
  end
  add_line(ps, 0.05, 8, { closed = true })

  local s = 0.1
  add_line({
    Vec3(1, 0.2, 1 - s),
    Vec3(1 + s, 0.2, 1),
    Vec3(1, .2, 1 + s),
    Vec3(1 - s, .2, 1),
  }, 0.05, 8, {
    closed = true
  })
end

do
  local ps = {}
  for i = 0, 100 do
    local z = i * 0.05
    ps[#ps + 1] = Vec3(
      -0.5 + math.sin(z * math.pi * 3) * 0.5,
      0.2 + (i >= 50 and ((i - 50) * 0.05) or 0),
      1 + -z
    )
  end
  add_line(ps)
end

do
  add_line({
    Vec3(0, 0.2, 2),
    Vec3(1, 0.7, 2),
    Vec3(2, 0.3, 2),
    Vec3(3, 0.5, 2),
  }, nil, 10, {
    colors = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 1, 1 } },
    widths = { 0.05, 0.2, 0.02, 0.5 }
  })
end


local shader = lovr.graphics.newShader([[
vec4 lovrmain() {
  return DefaultPosition;
}
]], [[
vec4 lovrmain() {
  vec4 col = DefaultColor;
  col.rgb *= UV.x * Normal;
  col.rgb = vec3(sin(UV.x * 100.) * 0.5 + 0.5, sin(UV.y * 10) * 0.5 + 0.5, 0.5);
  // col.rgb = Normal;
  return col;
}
]])

local function draw_debug_data(pass)
  for i, mesh_info in ipairs(Meshes) do
    for j, p in ipairs(mesh_info[2]) do
      pass:sphere(p, 0.01)
      pass:text(tostring(j), p + vec3(0, 0.1, 0), 0.05)
    end
  end

  for i, debug_draw in ipairs(debug_draws) do
    pass[debug_draw[1]](pass, unpack(debug_draw, 2, debug_draw.n))
  end
end


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

  -- draw_debug_data(pass)

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

  pass:setFaceCull('back')
  pass:setColor(1, 1, 1, 0.35)
  for i, mesh_info in ipairs(Meshes) do
    if i == 2 then
      pass:setShader(shader)
    else
      pass:setShader('unlit')
    end
    if mesh_info[1] then
      pass:draw(mesh_info[1])
    end
  end
end

function lovr.keypressed(key)
  if key == 'space' then
    Paused = not Paused
  end
end
