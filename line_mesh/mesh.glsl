layout(local_size_x = COMPUTE_SIZE, local_size_y = 1, local_size_z = 1) in;

struct PathNode {
  vec4 position; // .xyz = pos, .w = radius
  vec4 normal;   // .xyz = Bishop Frame Normal, .w = dist
  vec4 binormal; // .xyz = Bishop Frame Binormal, .w = miter scale
  vec4 color;
};

struct MeshVertex {
  vec3 VertexPosition;
  vec3 VertexNormal;
  vec2 VertexUV;
  vec4 VertexColor;
};

readonly buffer InputBuffer {
  PathNode pathNodes[];
};

writeonly buffer VertexBuffer {
  MeshVertex vertices[];
};

writeonly buffer IndexBuffer {
  uint indices[];
};

uniform uint NodesCount;
uniform uint Segments;
uniform float GlobalRadius;

void lovrmain() {
  uint nodeIdx = gl_GlobalInvocationID.x;
  if (nodeIdx >= NodesCount) return;

  vec3 center = pathNodes[nodeIdx].position.xyz;
  float r = GlobalRadius * pathNodes[nodeIdx].position.w;
  float miter_s = pathNodes[nodeIdx].binormal.w;

  vec3 N = pathNodes[nodeIdx].normal.xyz;
  vec3 B = pathNodes[nodeIdx].binormal.xyz;

  vec3 sdir;
  if (nodeIdx == 0 || nodeIdx == (NodesCount - 1)) {
    sdir = N;
  } else {
    vec3 in_dir = normalize(pathNodes[nodeIdx - 1].position.xyz - center);
    vec3 to_dir = normalize(pathNodes[nodeIdx + 1].position.xyz - center);
    sdir = normalize(in_dir + to_dir);
  }

  uint baseVertexIdx = nodeIdx * Segments;

  for (uint i = 0; i < Segments; i++) {
    float angle = (float(i) / float(Segments)) * 2.0 * PI;
    float cosA = cos(angle);
    float sinA = sin(angle);

    vec3 offsetDir = normalize(N * cosA + B * sinA) * r;
    offsetDir += sdir * dot(sdir, offsetDir) * (miter_s - 1.);
    vec3 worldPos = center + offsetDir;

    float dist_p = pathNodes[nodeIdx].normal.w / pathNodes[NodesCount - 1].normal.w;
    vec2 uv = vec2(dist_p, float(i) / float(Segments));

    uint vIdx = baseVertexIdx + i;
    vertices[vIdx].VertexPosition = vec3(worldPos);
    vertices[vIdx].VertexNormal   = vec3(offsetDir);
    vertices[vIdx].VertexUV       = vec2(uv);
    vertices[vIdx].VertexColor    = pathNodes[nodeIdx].color;
  }

  if (nodeIdx < NodesCount - 1) {
    uint nextBaseVertexIdx = (nodeIdx + 1) * Segments;
    uint baseIndexIdx = nodeIdx * Segments * 6;

    for (uint i = 0; i < Segments; i++) {
      uint nextI = (i + 1) % Segments;

      uint current_btm = baseVertexIdx + i;
      uint current_top = baseVertexIdx + nextI;
      uint next_btm    = nextBaseVertexIdx + i;
      uint next_top    = nextBaseVertexIdx + nextI;

      uint offset = baseIndexIdx + (i * 6);

      indices[offset + 0] = current_btm;
      indices[offset + 1] = current_top;
      indices[offset + 2] = next_btm;

      indices[offset + 3] = current_top;
      indices[offset + 4] = next_top;
      indices[offset + 5] = next_btm;
    }
  }
}
