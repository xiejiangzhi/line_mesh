Line Mesh
===========

![demo](./demo.png)

Generate a mesh from a path line formed by connecting 3D points

NOTE: The current version has not been optimized, so generation should be relatively slow.

**Key Features**:

* Simple smoothing of sharp corners
* Support for setting color and radius for each point
* Support for closed paths
* Support UV


**TODO**:

* Fix UV for sharp point
* Supports append point to path


## Use

```lua
local points = { { 1, 0, 0 }, { 1, 1, 1 }, { 1, 0, 1 } }
local width = 0.1
local seg = 8
-- vlist: { { x, y, z, nx, ny, nz, u, v, r, g, b, a }, ... }
local vlist, ilist, len = LineMesh.build(points, width, seg)

-- closed path
local vlist, ilist, len = LineMesh.build(points, wdtih, seg, { closed = true })

-- other
local vlist, ilist, len = LineMesh.build(points, wdtih, seg, {
  colors = { { r, g, b, a }, p2_rgb_or_rgba, p3_rgba }, -- set color for each point
  widths = { 0.1, 0.2, 0.1 }, -- set width for each point
  closed = true,
})
```

More see main.lua


## Known issues

* When angles are too sharp (approaching overlap), the generated mesh may overlap. (demo rand points 551)
* When the distance between points is too close (less than the line radius) and the angle is relatively sharp, the generated mesh may overlap.
