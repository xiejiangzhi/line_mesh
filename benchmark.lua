-- require('jit.v').on('jit.trace')
-- jit.off()

if jit then
  print('lua version', _VERSION, jit and (' | '..jit.version) or '', 'jit '..(jit.status() and 'on' or 'off'))
else
  print('lua version', _VERSION)
end

local LineMesh
if _VERSION == 'Luau' then
  LineMesh = require './line_mesh'
else
  package.path = './?/init.lua;'..package.path
  LineMesh = require 'line_mesh'
end


local function test(name, fn)
  for i = 1, 3 do
    local st = os.clock()
    fn()
    local cost = (os.clock() - st) * 1000
    print(string.format("%s, cost: %.4f", name, cost))
    collectgarbage()
  end
end

do
  local ps = {}
  for i = 1, 100 do
    ps[#ps + 1] = { 1, math.sin(i * 0.05), 0 }
  end

  test('p100 x10000', function()
    for i = 1, 10000 do
      LineMesh.build(ps)
    end
  end)

  test('p100 x10000 output cdata', function()
    for i = 1, 10000 do
      LineMesh.build(ps, nil, nil, { output_type = 'cdata' })
    end
  end)
end

do
  local ps = {}
  for i = 1, 1000 do
    ps[#ps + 1] = { 1, math.sin(i * 0.05), 0 }
  end
  test('p1000 x1000', function()
    for i = 1, 1000 do
      LineMesh.build(ps)
    end
  end)

  test('p1000 x1000 seg:3', function()
    for i = 1, 1000 do
      LineMesh.build(ps, nil, 3)
    end
  end)
end

do
  local ps = { { 0, 0, 0 } }
  for i = 1, 1000 do
    local lp = ps[i]
    local ox, oy, oz = math.random() - 0.5, math.random() - 0.5, math.random() - 0.5
    ps[i + 1] = { lp[1] + ox, lp[2] + oy, lp[3] + oz }
  end
  test('p1000 x250 random', function()
    for i = 1, 250 do
      LineMesh.build(ps)
    end
  end)
end

do
  local ps = { { 0, 0, 0 } }
  for i = 1, 1000 do
    local lp = ps[i]
    local ox, oy, oz = math.random() - 0.5, math.random() * 0.5, math.random() - 0.5
    ps[i + 1] = { lp[1] + ox, lp[2] + oy, lp[3] + oz }
  end
  test('p1000 x250 random forward', function()
    for i = 1, 250 do
      LineMesh.build(ps)
    end
  end)
end
