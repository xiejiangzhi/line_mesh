require('jit.v').on('jit.trace')

local LineMesh = require 'line_mesh.init'

local function test(name, fn)
  for i = 1, 3 do
    local st = os.clock()
    fn()
    local cost = (os.clock() - st) * 1000
    print(string.format("%s, cost: %.4f", name, cost))
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
end
