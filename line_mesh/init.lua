local M = {}

-- for debug
local _LVec3, LVec3, LQuat
if lovr then
  _LVec3 = Vec3
  LVec3 = function(x, y, z)
    if type(x) == 'table' then
      return _LVec3(x[1], x[2], x[3])
    else
      return _LVec3(x, y, z)
    end
  end
  LQuat = Quat
end

local Abs = math.abs
local Cos, Sin = math.cos, math.sin
local ACos = math.acos
local PI = math.pi

local ComputeGroupSize = 128
local ComputeShader
local BishopFrame

local Vec3, Quat
if _VERSION == 'Luau' then
  Vec3 = require('./line_mesh/vec3')
  Quat = require('./line_mesh/quat')
else
  local mdir = (...):gsub("%.init$", '')
  Vec3 = require(mdir..'.vec3')
  Quat = require(mdir..'.quat')

  if lovr then
    local glsl_path = mdir:gsub('%.', '/')..'/mesh.glsl'
    local glsl_code = lovr.filesystem.read(glsl_path):gsub('COMPUTE_SIZE', ComputeGroupSize)
    ComputeShader = lovr.graphics.newShader(glsl_code)
    BishopFrame = require(mdir..'.bishop_frame')
  end
end

-- for debug
if lovr then
  Vec3.to_lovr = function(v)
    return _LVec3.raw_new(v[1], v[2], v[3])
  end
  Quat.to_lovr = function(q)
    return LQuat.raw_new(q[1], q[2], q[3], q[4])
  end
end

local ok, ffi = pcall(require, 'ffi')
if not ok then
  ffi = nil
end

local LineMeshOutputVertex
if ffi then
  ffi.cdef[[
    typedef struct {
      float x, y, z;
      float nx, ny, nz;
      float u, v;
      float r, g, b, a;
    } LineMeshOutputVertex;
  ]]
  LineMeshOutputVertex = ffi.typeof('LineMeshOutputVertex')
end

-- debug_draw(pass_fn_name, ...args)
M.debug_draw = function(pass_fn_name, ...) end

local DefaultSeg = 5
local DefaultOpts = {}
local DefaultColor = { 1, 1, 1, 1 }

--[[
points: { { x, y, z }, p2, p3, ... }
opts.colors: { { r, g, b, a or 1 }, ... }, points colors, 1-1 map
opts.widths: { w1, w2, w3, ... }, points widths, 1-1 map
opts.closed: bool, link first point & last point. TODO impl
opts.output_type: optional, table or cdata, default is table. cdata pre vertex has 12 float numbers
opts.smooth: optional, default is true.

return vlist{{ x, y, z, nx, ny, nz, u, v, r, g, b, a }, ...}, ilist, line_len, vtotal, itotal
return vlist_float[vtotal*12], ilist_int[itotal], line_len, vtotal, itotal
]]
function M.build(_points, width, seg, opts)
  assert(#_points >= 2, 'points must >= 2')
  width = width or 0.1
  assert(width > 0, 'width must > 0')
  seg = seg or DefaultSeg
  assert(seg >= 3, 'segment must >= 3')

  opts = opts or DefaultOpts

  local points = {}
  for i, p in ipairs(_points) do
    points[i] = Vec3.new(p)
  end

  local vlist, ilist, next_vi, next_ii
  if opts.output_type == 'cdata' then
    assert(ffi, 'Cannot use cdata without luajit')
    local tv, ti = M.predirect_output_size(points, seg)
    vlist = ffi.new('LineMeshOutputVertex[?]', tv)
    ilist = ffi.new('uint32_t[?]', ti)
    next_vi, next_ii = 0, 0
  else
    vlist, ilist = {}, {}
    next_vi, next_ii = 1, 1
  end
  local line_len = 0
  for i = 2, #points do
    line_len = line_len + points[i]:distance(points[i - 1])
  end

  local colors = opts.colors
  local widths = opts.widths
  local is_closed = opts.closed and #points > 2

  local base_ps = {}
  for i = 1, seg do
    local phi = i / seg * PI * 2
    local x, y = Sin(phi), Cos(phi)
    base_ps[#base_ps + 1] = Vec3.raw_new(x, y, 0)
  end

  local gdata = {
    last_ps = {}, -- last point wrap points
    poly_idx = {},
    last_poly_idx = {},

    last_radius = nil,
    base_ps = base_ps,
    smooth = opts.smooth ~= false,
    seg = seg,

    output_type = opts.output_type,
    vlist = vlist, next_vi = next_vi,
    ilist = ilist, next_ii = next_ii,
  }

  local plen = 0
  local pinfo = { radius = width * 0.5, plen = 0, color = nil, idx = 0 }
  for i = 1, #points do
    local p1 = points[i - 1]
    local p2 = points[i]
    local p3 = points[i + 1]

    if is_closed then
      if not p1 then
        p1 = points[#points]
      end
      if not p3 then
        p3 = points[1]
      end
    end

    if p1 then
      plen = plen + p1:distance(p2)
    end
    pinfo.idx = i
    pinfo.radius = (widths and widths[i] or 1) * 0.5 * width
    pinfo.plen = plen / line_len
    pinfo.color = colors and colors[i] or DefaultColor

    if p1 and p3 then
      M._gen_3p_data(i, p1, p2, p3, pinfo, gdata)
    else
      M._gen_2p_data(i, p1, p2, p3, pinfo, gdata)
    end
  end

  if is_closed then
    local first_poly_idx = {}
    for i = 1, seg do
      first_poly_idx[#first_poly_idx + 1] = i
    end

    local dir = (points[#points] - points[1]):normalize()
    local bp
    if gdata.output_type == 'cdata' then
      local v = vlist[gdata.last_poly_idx[1] - 1]
      bp = Vec3.raw_new(v.x, v.y, v.z)
    else
      local v = vlist[gdata.last_poly_idx[1]]
      bp = Vec3.raw_new(v[1], v[2], v[3])
    end
    local best_tv, best_i = -2, 1
    for i = 1, seg do
      local tv
      if gdata.output_type == 'cdata' then
        local v = vlist[first_poly_idx[i] - 1]
        tv = dir:dot((bp - { v.x, v.y, v.z }):normalize())
      else
        local v = vlist[first_poly_idx[i]]
        tv = dir:dot((bp - { v[1], v[2], v[3] }):normalize())
      end
      if tv > best_tv then
        best_tv, best_i = tv, i
      end
    end
    for i = 1, best_i - 1 do
      first_poly_idx[seg] = table.remove(first_poly_idx, 1)
    end
    M._add_line_to_ilist(gdata, gdata.last_poly_idx, first_poly_idx)
  end


  local vtotal, itotal
  if gdata.output_type == 'cdata' then
    vtotal, itotal = gdata.next_vi, gdata.next_ii
  else
    vtotal, itotal = gdata.next_vi - 1, gdata.next_ii - 1
  end

  return vlist, ilist, line_len, vtotal, itotal
end

local NewBuffer = lovr and lovr.graphics.newBuffer
--[[
build by compute shader, auto update buffer
result = gpu_build(points, opts, last_result)

points: { { x, y, z }, p2, p3, ... }
width: default is 0.1
segments: default is 8
opts.colors: { { r, g, b, a or 1 }, ... }, points colors, 1-1 map
opts.widths: { w1, w2, w3, ... }, points widths, 1-1 map, multiple width
last_result: optional, automatic management and reuse buffers

return {
  mesh = mesh,
  vertex_buffer = vertex_buffer,
  index_buffer = index_buffer,
  vcount = n, icount = m, segments = s
}
]]
local DefaultGpuBuildOpts = { }
function M.gpu_build(pass, _points, width, segments, opts, last_result)
  assert(lovr, 'GPU build require Lovr env')
  assert(#_points >= 2, 'points must >= 2')

  segments = segments or 8
  assert(segments >= 3, 'segments must >= 3')

  opts = opts or DefaultGpuBuildOpts
  width = width or 0.1
  local colors = opts.colors
  local widths = opts.widths

  local points = {}
  for i, p in ipairs(_points) do
    points[i] = Vec3.raw_new(p[1], p[2],  p[3])
  end

  local ret = last_result or {}
  local bfdata = BishopFrame.calc(points)

  local input_buffer = ret.input_buffer
  if not input_buffer or input_buffer:getLength() < #bfdata then
    local input_format = ComputeShader:getBufferFormat('InputBuffer')
    input_buffer = NewBuffer(input_format, #bfdata)
    ret.input_buffer = input_buffer
  end

  local input_ptr = ffi.cast('float*', input_buffer:mapData())
  for i, v in ipairs(bfdata) do
    local r = (widths and widths[i] or 1) * width * 0.5
    local color = colors and colors[i] or DefaultColor
    local idx = (i - 1) * 16
    local pos, normal, binormal, mscale, dist = v[1], v[2], v[3], v[4], v[5]
    input_ptr[idx], input_ptr[idx + 1], input_ptr[idx + 2] = pos[1], pos[2], pos[3]
    input_ptr[idx + 3] = r
    input_ptr[idx + 4], input_ptr[idx + 5], input_ptr[idx + 6] = normal[1], normal[2], normal[3]
    input_ptr[idx + 7] = dist
    input_ptr[idx + 8], input_ptr[idx + 9], input_ptr[idx + 10] = binormal[1], binormal[2], binormal[3]
    input_ptr[idx + 11] = mscale
    input_ptr[idx + 12], input_ptr[idx + 13], input_ptr[idx + 14] = color[1], color[2], color[3]
    input_ptr[idx + 15] = color[4] or 1

    -- input_ptr[i] = {
    --   { v.pos[1], v.pos[2], v.pos[3], r },
    --   { v.normal[1], v.normal[2], v.normal[3], v.dist },
    --   { v.binormal[1], v.binormal[2], v.binormal[3], v.scale },
    --   color,
    -- }
  end
  -- local input_buffer = ret.input_buffer
  -- if not input_buffer or input_buffer:getLength() < #input_data then
  --   input_buffer = NewBuffer(input_format, input_data)
  -- else
  --   input_buffer:setData(input_data)
  -- end

  local mesh = ret.mesh
  local vcount = #points * segments
  local vertex_buffer = ret.vertex_buffer
  if not vertex_buffer or vertex_buffer:getLength() < vcount then
    local vertex_format = ComputeShader:getBufferFormat('VertexBuffer')
    vertex_buffer = NewBuffer(vertex_format, vcount)
    ret.vertex_buffer = vertex_buffer
    mesh = lovr.graphics.newMesh(vertex_buffer)
    ret.mesh = mesh
  end
  local icount_path = (#points - 1) * segments * 6
  -- path + close poly
  local icount = icount_path + (segments - 2) * 3 * 2
  local index_buffer = ret.index_buffer
  if not index_buffer or index_buffer:getLength() < icount then
    local index_format = ComputeShader:getBufferFormat('IndexBuffer')
    index_buffer = NewBuffer(index_format, icount)
    ret.index_buffer = index_buffer
    mesh:setIndexBuffer(index_buffer)
  end

  if ret.points_count ~= #points or ret.segments ~= segments then
    ret.vcount = vcount
    ret.icount = icount
    local edge_index = {}
    local end_si = vcount - segments
    for i = 3, segments do
      edge_index[#edge_index + 1] = 0
      edge_index[#edge_index + 1] = i - 1
      edge_index[#edge_index + 1] = i - 2

      edge_index[#edge_index + 1] = end_si
      edge_index[#edge_index + 1] = end_si + i - 2
      edge_index[#edge_index + 1] = end_si + i - 1
    end
    index_buffer:setData(edge_index, icount_path + 1)
    mesh:setDrawRange(1, icount)
  end

  pass:push('state')
  pass:setShader(ComputeShader)
  pass:send('InputBuffer', input_buffer)
  pass:send('VertexBuffer', vertex_buffer)
  pass:send('IndexBuffer', index_buffer)
  pass:send('NodesCount', #points)
  pass:send('Segments', segments)
  pass:send('GlobalRadius', 1)
  local n = math.ceil(#points / 64)
  pass:compute(n)
  pass:pop('state')

  if not mesh then
    mesh = lovr.graphics.newMesh(vertex_buffer)
    mesh:setIndexBuffer(index_buffer)
    ret.mesh = mesh
  end

  ret.points_count = #points
  ret.segments = segments

  return ret
end

-- The predicted result >= the final output size
-- return total_vertices, total_indexes
function M.predirect_output_size(points, seg)
  seg = seg or DefaultSeg
  local tv = 0
  local ti = 0
  for i, p2 in ipairs(points) do
    if i == 1 then
      tv = tv + seg * 2
      -- poly + smooth line
      ti = ti + (seg - 2) * 3 + seg * 6
    elseif i == #points then
      tv = tv + seg * 2
      -- prev line + smooth line + poly
      ti = ti + (seg - 2) * 3 + seg * 6 * 2
    else
      local p1 = points[i - 1]
      local p3 = points[i + 1]
      local dir21 = Vec3.normalize({ p1[1] - p2[1], p1[2] - p2[2], p1[3] - p2[3] })
      local dir23 = Vec3.normalize({ p3[1] - p2[1], p3[2] - p2[2], p3[3] - p2[2] })
      local line_dot = Vec3.dot(dir21, dir23)

      if line_dot < -0.5 then
        tv = tv + seg
        ti = ti + seg * 6
      else
        tv = tv + seg * 5
        -- prev line + cut 4tri + fill line + fill poly
        ti = ti + seg * 6 + 12 + (seg + 4) * 6 + (seg + 2) * 3
      end
    end
  end
  return tv, ti
end

------------------------

-- mid point, have p1 & p2 & p3
function M._gen_3p_data(pidx, p1, p2, p3, pinfo, gdata)
  local dir21 = (p1 - p2):normalize()
  local dir23 = (p3 - p2):normalize()
  local line_dot = dir21:dot(dir23)
  if line_dot < -1 then
    line_dot = -1
  elseif line_dot > 1 then
    line_dot = 1
  end

  local dir_v123 = dir21:clone():cross(dir23):normalize()
  local dir_mid_side
  local dir_mid
  if Abs(line_dot) > 0.99999 then
    if Abs(dir21:dot(Vec3.raw_new(0, 1, 0))) > 0.1 then
      dir_mid = Vec3.raw_new(0, 1, 0):cross(dir21):normalize()
    else
      dir_mid = Vec3.raw_new(1, 0, 0):cross(dir21):normalize()
    end
    dir_mid_side = dir23
  else
    dir_mid = (dir21 + dir23):normalize()
    dir_mid_side = dir_v123:clone():cross(dir_mid):normalize()
  end


  local angle = ACos(line_dot)
  local inner_ov = pinfo.radius / Sin(angle * 0.5)

  -- local p_inner = p2 + dir_mid * inner_ov
  -- M.debug_draw('setColor', 0.8, 0.8, 0)
  -- M.debug_draw('line', LVec3(p2), LVec3(p2 + dir_mid_side * 0.2))
  -- M.debug_draw('setColor', 0.5, 0.5, 0)
  -- M.debug_draw('sphere', LVec3(p_inner), 0.005)
  -- M.debug_draw('setColor', 1, 1, 1)

  local dir12 = -dir21

  if line_dot < -0.5 or not gdata.smooth then
    -- big angle, simple wrap point
    M._wrap_point_on_plane(p2, dir12, dir_mid_side, dir_mid, inner_ov, pinfo, gdata.poly_idx, gdata)
    M._add_line_to_ilist(gdata, gdata.last_poly_idx, gdata.poly_idx)
    gdata.last_poly_idx, gdata.poly_idx = gdata.poly_idx, gdata.last_poly_idx
  else
    -- sharp angle, smoothing
    M._wrap_point_on_plane(p2, dir12, dir_mid_side, dir_mid, inner_ov, pinfo, gdata.poly_idx, gdata)
    M._add_line_to_ilist(gdata, gdata.last_poly_idx, gdata.poly_idx)
    M._smooth_point_data(p1, p2, p3, pinfo, dir21, dir23, dir_mid, line_dot, gdata)
  end
end

-- head or tail
-- p1: prev point
-- p2: current point
-- p3: next point
-- p1 & p3 one is nil
function M._gen_2p_data(pidx, p1, p2, p3, pinfo, gdata)
  -- local dir = p1 and (p2 - p1):normalize() or (p3 - p2):normalize()

  local spinfo = { radius = pinfo.radius * 0.5, plen = pinfo.plen, color = pinfo.color }

  if p1 then
    local dir = (p2 - p1):normalize()
    -- M.debug_draw('setColor', 1, 1, 0)
    -- M.debug_draw('line', LVec3(p2), LVec3(p2 + dir * 0.5))
    -- M.debug_draw('setColor', 1, 1, 1)

    M._wrap_point(p2, dir, pinfo, gdata.poly_idx, gdata)
    M._add_line_to_ilist(gdata, gdata.last_poly_idx, gdata.poly_idx)
    gdata.last_poly_idx, gdata.poly_idx = gdata.poly_idx, gdata.last_poly_idx

    M._wrap_point(p2 + dir * pinfo.radius * 0.5, dir, spinfo, gdata.poly_idx, gdata)
    M._add_poly_to_ilist(gdata, gdata.poly_idx, pidx > 1)
    M._add_line_to_ilist(gdata, gdata.last_poly_idx, gdata.poly_idx)
    gdata.last_poly_idx, gdata.poly_idx = gdata.poly_idx, gdata.last_poly_idx
  else
    local dir = (p3 - p2):normalize()
    -- M.debug_draw('setColor', 1, 1, 0)
    -- M.debug_draw('line', LVec3(p2), LVec3(p2 + dir * 0.5))
    -- M.debug_draw('setColor', 1, 1, 1)

    M._wrap_point(p2 - dir * pinfo.radius * 0.5, dir, spinfo, gdata.poly_idx, gdata)
    M._add_poly_to_ilist(gdata, gdata.poly_idx, pidx > 1)
    gdata.last_poly_idx, gdata.poly_idx = gdata.poly_idx, gdata.last_poly_idx

    M._wrap_point(p2, dir, pinfo, gdata.poly_idx, gdata)
    M._add_line_to_ilist(gdata, gdata.last_poly_idx, gdata.poly_idx)
    gdata.last_poly_idx, gdata.poly_idx = gdata.poly_idx, gdata.last_poly_idx
  end
end

function M._wrap_point(point, dir, pinfo, out_poly_idx, gdata)
  local last_ps = gdata.last_ps
  local last_radius = gdata.last_radius or pinfo.radius

  local rot
  if not last_ps[1] then
    rot = Quat.new(dir)
  end
  local color = pinfo.color
  local scale = pinfo.radius / last_radius

  local vlist, next_vi = gdata.vlist, gdata.next_vi
  local ray_ov = dir * 10000
  for i = 1, gdata.seg do
    local lp = last_ps[i]
    local p
    if lp then
      p = M._ray_plane(lp - ray_ov, dir, point, dir)
      p = point + (p - point) * scale
      assert(p, "Failed to wrap point "..tostring(point))
    else
      p = point + rot * gdata.base_ps[i] * pinfo.radius
    end
    last_ps[i] = p

    -- local l = i / gdata.seg
    -- M.debug_draw('setColor', l, l, l)
    -- M.debug_draw('sphere', LVec3(lp), 0.005)

    local nrm = M._calc_normal(p, point, dir)
    if gdata.output_type == 'cdata' then
      vlist[next_vi] = LineMeshOutputVertex(
        p[1], p[2], p[3], nrm[1], nrm[2], nrm[3],
        pinfo.plen, (i - 1) / (gdata.seg - 1), color[1], color[2], color[3], color[4] or 1
      )
    else
      vlist[next_vi] = {
        p[1], p[2], p[3], nrm[1], nrm[2], nrm[3],
        pinfo.plen, (i - 1) / (gdata.seg - 1), color[1], color[2], color[3], color[4] or 1
      }
    end
    out_poly_idx[i] = next_vi
    next_vi = next_vi + 1
  end
  gdata.next_vi = next_vi
  gdata.last_radius = pinfo.radius
  -- M.debug_draw('setColor', 1, 1, 1)
  out_poly_idx[gdata.seg + 1] = nil
end

-- point
-- dir_src: direction from prev point to point
function M._wrap_point_on_plane(
  point, dir_src, plane_dir, dir_mid, inner_ov, pinfo, out_poly_idx, gdata
)
  local last_ps = gdata.last_ps
  local last_radius = gdata.last_radius or pinfo.radius
  local rot, scale
  if not last_ps[1] then
    rot = Quat.new(plane_dir)
    scale = inner_ov / pinfo.radius - 1
  else
    scale = pinfo.radius / last_radius
  end

  local color = pinfo.color
  local vlist, next_vi = gdata.vlist, gdata.next_vi
  local ray_ov = dir_src * 10000
  for i = 1, gdata.seg do
    local p
    local lp = last_ps[i]
    if lp then
      p = M._ray_plane(lp - ray_ov, dir_src, point, plane_dir)
      assert(p, 'Failed to wrap point '..tostring(point))
      p = point + (p - point) * scale
    else
      local bp = rot * (gdata.base_ps[i] * pinfo.radius)
      bp:add(dir_mid * (dir_mid:dot(bp) * scale))
      p = point + bp
    end
    last_ps[i] = p

    -- local l = i / gdata.seg
    -- M.debug_draw('setColor', l, l, l)
    -- M.debug_draw('sphere', LVec3(p), 0.005)

    local nrm = M._calc_normal(p, point, dir_src)
    if gdata.output_type == 'cdata' then
      vlist[next_vi] = LineMeshOutputVertex(
        p[1], p[2], p[3], nrm[1], nrm[2], nrm[3],
        pinfo.plen, (i - 1) / (gdata.seg - 1), color[1], color[2], color[3], color[4] or 1
      )
    else
      vlist[next_vi] = {
        p[1], p[2], p[3], nrm[1], nrm[2], nrm[3],
        pinfo.plen, (i - 1) / (gdata.seg - 1), color[1], color[2], color[3], color[4] or 1
      }
    end
    out_poly_idx[i] = next_vi
    next_vi = next_vi + 1
  end
  gdata.next_vi = next_vi
  gdata.last_radius = pinfo.radius
  out_poly_idx[gdata.seg + 1] = nil
end

function M._smooth_point_data(p1, p2, p3, pinfo, dir21, dir23, dir_mid, line_dot, gdata)
  -- NOTE don't mod gdata.next_xx before sync
  local vlist, ilist, next_vi, next_ii = gdata.vlist, gdata.ilist, gdata.next_vi, gdata.next_ii

  -- M.debug_draw('setColor', 0.5, 0.5, 0)
  -- M.debug_draw('line', LVec3(p2), LVec3(p2 + Vec3(dir_v123):cross(dir12) * 0.5))
  -- M.debug_draw('setColor', 0.5, 0, 0.5)
  -- M.debug_draw('setColor', 1, 1, 0)
  -- M.debug_draw('sphere', LVec3(cut_p), 0.005)
  -- M.debug_draw('setColor', 1, 1, 1)

  local next_ps = {}
  local next_add_data = {}
  local fill_poly = {}
  local fill_poly_next = {}
  local fill_cut_p1, fill_cut_p2
  local fill_insert_i = nil
  local fill_poly_uv_map = {}

  local lcolor = pinfo.color
  local cut_p = p2 - dir_mid * pinfo.radius * 0.6

  -- M.debug_draw('setColor', 0.3, 0.3, 0.3)

  -- mod wrap point to make smooth
  for i, p in ipairs(gdata.last_ps) do
    local cut_dist = (p - cut_p):dot(dir_mid)
    -- point that need to cut to plane(cut_p,dir_mid)
    if cut_dist < 0 then
      local prev_i = (i > 1) and (i - 1) or gdata.seg
      local next_i = (i < gdata.seg) and (i + 1) or 1
      local prev_p = gdata.last_ps[prev_i]
      local next_p = gdata.last_ps[next_i]

      local pv = vlist[gdata.poly_idx[i]]
      local uv_y
      if gdata.output_type == 'cdata' then
        uv_y = pv.v
      else
        uv_y = pv[8]
      end

      -- test poly(to prev point) intersection
      local prev_cut_p, len = M._ray_plane(p, (prev_p - p):normalize(), cut_p, dir_mid)
      if prev_cut_p and len < prev_p:distance(p) then
        -- M.debug_draw('setColor', 1, 0, 0)
        -- M.debug_draw('sphere', LVec3(prev_cut_p), 0.001)
        -- M.debug_draw('setColor', 1, 1, 1)
        local nrm = M._calc_normal(prev_cut_p, p2, dir21)
        -- TODO mix uv_y from prev_p to p to make better uv_y
        if gdata.output_type == 'cdata' then
          vlist[next_vi] = LineMeshOutputVertex(
            prev_cut_p[1],  prev_cut_p[2],  prev_cut_p[3], nrm[1], nrm[2], nrm[3],
            pinfo.plen, uv_y, lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
          )
        else
          vlist[next_vi] = {
            prev_cut_p[1],  prev_cut_p[2],  prev_cut_p[3], nrm[1], nrm[2], nrm[3],
            pinfo.plen, uv_y, lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
          }
        end
        ilist[next_ii] = next_vi
        ilist[next_ii + 1] = gdata.poly_idx[prev_i]
        ilist[next_ii + 2] = gdata.poly_idx[i]
        next_ii = next_ii + 3
        next_add_data[#next_add_data + 1] = { next_vi, prev_i, i }
        next_vi = next_vi + 1
        fill_cut_p1 = prev_cut_p
        fill_poly_uv_map[fill_cut_p1] = (i - 1) / (gdata.seg - 1)
      end

      -- test poly(to next point) intersection
      local next_cut_p, len = M._ray_plane(p, (next_p - p):normalize(), cut_p, dir_mid)
      if next_cut_p and len < next_p:distance(p) then
        -- M.debug_draw('setColor', 0, 0, 1)
        -- M.debug_draw('sphere', LVec3(next_cut_p), 0.001)
        -- M.debug_draw('setColor', 1, 1, 1)
        local nrm = M._calc_normal(next_cut_p, p2, dir23)
        -- TODO mix uv_y from next_p to p to make better uv_y
        if gdata.output_type == 'cdata' then
          vlist[next_vi] = LineMeshOutputVertex(
            next_cut_p[1],  next_cut_p[2], next_cut_p[3], nrm[1], nrm[2], nrm[3],
            pinfo.plen, uv_y, lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
          )
        else
          vlist[next_vi] = {
            next_cut_p[1],  next_cut_p[2], next_cut_p[3], nrm[1], nrm[2], nrm[3],
            pinfo.plen, uv_y, lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
          }
        end
        ilist[next_ii] = next_vi
        ilist[next_ii + 1] = gdata.poly_idx[i]
        ilist[next_ii + 2] = gdata.poly_idx[next_i]
        next_ii = next_ii + 3
        next_add_data[#next_add_data + 1] = { next_vi, i, next_i }
        next_vi = next_vi + 1
        fill_cut_p2 = next_cut_p
        fill_poly_uv_map[fill_cut_p2] = (i - 1) / (gdata.seg - 1)
      end

      -- M.debug_draw('setColor', 0, 1, 0)
      -- M.debug_draw('sphere', LVec3(p), 0.002)
      -- M.debug_draw('setColor', 1, 1, 1)

      -- move poly point to plane, dir: p2 -> p1
      local sp = M._ray_plane(p, dir21, cut_p, dir_mid) or p -- direct use p if point on plane,
      if gdata.output_type == 'cdata' then
        pv.x, pv.y, pv.z = sp[1], sp[2], sp[3]
      else
        pv[1], pv[2], pv[3] = sp[1], sp[2], sp[3]
      end

      -- local l = i / gdata.seg
      -- M.debug_draw('setColor', l, l, l)
      -- M.debug_draw('sphere', LVec3(sp), 0.001)
      -- M.debug_draw('setColor', 1, 1, 1)

      -- move poly point to plane, dir: p2 -> p3
      local np = M._ray_plane(p, dir23, cut_p, dir_mid) or p

      if fill_insert_i then
        table.insert(fill_poly, fill_insert_i, sp)
        table.insert(fill_poly_next, fill_insert_i, np)
        fill_insert_i = fill_insert_i + 1
      else
        fill_poly[#fill_poly + 1] = sp
        fill_poly_next[#fill_poly_next + 1] = np
      end
      fill_poly_uv_map[sp] = uv_y
      fill_poly_uv_map[np] = uv_y

      next_ps[#next_ps + 1] = np

      -- M.debug_draw('setColor', l, l, 0)
      -- M.debug_draw('sphere', LVec3(np), 0.001)
      -- M.debug_draw('setColor', 1, 1, 1)
    else
      next_ps[#next_ps + 1] = p
      fill_insert_i = fill_insert_i or 1
      -- if cut_dist <= 1e-6 then
      --   fill_poly[#fill_poly + 1] = p
      -- end
    end
  end
  -- M.debug_draw('setColor', 1, 1, 1)
  gdata.last_poly_idx, gdata.poly_idx = gdata.poly_idx, gdata.last_poly_idx

  if fill_poly[1]:distance(fill_cut_p1) <= fill_poly[1]:distance(fill_cut_p2) then
    table.insert(fill_poly, 1, fill_cut_p1)
    fill_poly[#fill_poly + 1] = fill_cut_p2
    for i = #fill_poly_next, 1, -1 do
      fill_poly[#fill_poly + 1] = fill_poly_next[i]
    end
  else
    table.insert(fill_poly, 1, fill_cut_p2)
    fill_poly[#fill_poly + 1] = fill_cut_p1
    for i = #fill_poly_next, 1, -1 do
      fill_poly[#fill_poly + 1] = fill_poly_next[i]
    end
  end
  -- check triangle normal
  local tri_normal = (fill_poly[2] - fill_poly[1]):cross(fill_poly[3] - fill_poly[1])
  if dir_mid:dot(tri_normal) < 0 then
    for i = 1, #fill_poly * 0.5 do
      local j = #fill_poly - i + 1
      fill_poly[i], fill_poly[j] = fill_poly[j], fill_poly[i]
    end
  end

  -- copy smmoth vertex for p2 to p3
  assert(#next_ps == #gdata.last_ps, 'invalid ps')
  gdata.last_ps = next_ps
  for i, p in ipairs(next_ps) do
    local nrm = M._calc_normal(p, p3, dir23)
    if gdata.output_type == 'cdata' then
      vlist[next_vi] = LineMeshOutputVertex(
        p[1], p[2], p[3], nrm[1], nrm[2], nrm[3],
        pinfo.plen, (i - 1) / (gdata.seg - 1), lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
      )
    else
      vlist[next_vi] = {
        p[1], p[2], p[3], nrm[1], nrm[2], nrm[3],
        pinfo.plen, (i - 1) / (gdata.seg - 1), lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
      }
    end
    gdata.poly_idx[i] = next_vi
    next_vi = next_vi + 1
  end
  for i, info in ipairs(next_add_data) do
    ilist[next_ii] = info[1]
    ilist[next_ii + 1] = gdata.poly_idx[info[3]]
    ilist[next_ii + 2] = gdata.poly_idx[info[2]]
    next_ii = next_ii + 3
  end
  gdata.poly_idx[gdata.seg + 1] = nil
  gdata.last_poly_idx, gdata.poly_idx = gdata.poly_idx, gdata.last_poly_idx

  local poly_idx = {}
  local poly2_idx = {}
  local poly2_dist = 0.2 + (line_dot + 0.6) / 3

  local total_fill_ps = #fill_poly
  local uv_move = math.floor(total_fill_ps * 0.5)
  for i, p in ipairs(fill_poly) do
    -- local l = i / #fill_poly
    -- M.debug_draw('setColor', 0.1, 0.1, l)
    -- M.debug_draw('sphere', LVec3(p), 0.001)

    local uv_y = fill_poly_uv_map[p] or 0
    local nrm = M._calc_normal(p, p3, dir23)
    if gdata.output_type == 'cdata' then
      vlist[next_vi] = LineMeshOutputVertex(
        p[1], p[2], p[3], nrm[1], nrm[2], nrm[3],
        pinfo.plen, uv_y, lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
      )
    else
      vlist[next_vi] = {
        p[1], p[2], p[3], nrm[1], nrm[2], nrm[3],
        pinfo.plen, uv_y, lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
      }
    end
    poly_idx[#poly_idx + 1] = next_vi
    next_vi = next_vi + 1

    if poly2_dist > 0.01 then
      local sp = cut_p + (p - cut_p) * 0.5 - dir_mid * (pinfo.radius * 0.4 * poly2_dist)
      -- M.debug_draw('setColor', l, 0.1, 0.1)
      -- M.debug_draw('sphere', LVec3(sp), 0.001)

      -- Find a far point and use the point's uv_y to smooth current point uv_y
      local mp_i = (i + uv_move - 1) % total_fill_ps + 1
      local mp = fill_poly[mp_i]
      local f = (sp - p):length() / (mp - p):length()
      local suv_y = uv_y * (1 - f) + (fill_poly_uv_map[mp] or 0) * f

      nrm = (sp - p2):normalize()
      -- local suv_y = uv_y +
      if gdata.output_type == 'cdata' then
        vlist[next_vi] = LineMeshOutputVertex(
          sp[1], sp[2], sp[3], nrm[1], nrm[2], nrm[3],
          pinfo.plen, suv_y, lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
        )
      else
        vlist[next_vi] = {
          sp[1], sp[2], sp[3], nrm[1], nrm[2], nrm[3],
          pinfo.plen, suv_y, lcolor[1], lcolor[2], lcolor[3], lcolor[4] or 1
        }
      end
      poly2_idx[#poly2_idx + 1] = next_vi
      next_vi = next_vi + 1
    end
  end
  -- M.debug_draw('setColor', 1, 1, 1)
  gdata.next_vi, gdata.next_ii = next_vi, next_ii

  if #poly2_idx > 0 then
    M._add_line_to_ilist(gdata, poly2_idx, poly_idx)
    M._add_poly_to_ilist(gdata, poly2_idx)
  else
    M._add_poly_to_ilist(gdata, poly_idx)
  end
end

function M._add_poly_to_ilist(gdata, poly_idx, revert)
  local sidx = poly_idx[1]
  local ilist, next_ii = gdata.ilist, gdata.next_ii
  for i = 3, #poly_idx do
    ilist[next_ii] = sidx
    if revert then
      ilist[next_ii + 1] = poly_idx[i-1]
      ilist[next_ii + 2] = poly_idx[i]
    else
      ilist[next_ii + 1] = poly_idx[i]
      ilist[next_ii + 2] = poly_idx[i-1]
    end
    next_ii = next_ii + 3
  end
  gdata.next_ii = next_ii
end

function M._add_line_to_ilist(gdata, poly1_idx, poly2_idx)
  local last_i = #poly1_idx
  local ilist, next_ii = gdata.ilist, gdata.next_ii
  for i = 1, #poly1_idx do
    local v1, v2, v3, v4 = poly1_idx[last_i], poly1_idx[i], poly2_idx[i], poly2_idx[last_i]
    ilist[next_ii] = v1
    ilist[next_ii + 1] = v2
    ilist[next_ii + 2] = v3
    ilist[next_ii + 3] = v1
    ilist[next_ii + 4] = v3
    ilist[next_ii + 5] = v4
    next_ii = next_ii + 6
    last_i = i
  end
  gdata.next_ii = next_ii
end

-- same as C's DBL_EPSILON
local DBL_EPSILON = 2.2204460492503131e-16

function M._ray_plane(ray_pos, ray_dir, plane_pos, plane_normal)
  local denom = plane_normal:dot(ray_dir)
  -- ray does not intersect plane
  if Abs(denom) < DBL_EPSILON then
    return false
  end
  -- distance of direction
  local d = plane_pos - ray_pos
  local t = d:dot(plane_normal) / denom
  if t < DBL_EPSILON then
    return false
  end
  -- Return collision point and distance from ray origin
  return ray_pos + ray_dir * t, t
end

function M._calc_normal(p, line_p, line_dir)
  local vp = line_p + line_dir * line_dir:dot(p - line_p)
  return (p - vp):normalize()
end

return M