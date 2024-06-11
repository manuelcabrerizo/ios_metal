//
//  Shader.metal
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

#include "ShaderTypes.h"

struct RasterizerData {
    float4 position [[position]];
    float3 color;
};

vertex RasterizerData
vertexShader(uint vertexID [[vertex_id]],
             uint instanceID [[instance_id]],
             constant Vertex *vertexArray [[buffer(VertexInputIndexVertices)]],
             constant matrix_float4x4 *worldArray [[buffer(VertexInputIndexWorld)]],
             constant matrix_float4x4 &view  [[buffer(VertexInputIndexView)]],
             constant matrix_float4x4 &proj  [[buffer(VertexInputIndexProj)]]) {
    
    RasterizerData out;
    float4 position = float4(vertexArray[vertexID].position.xy, 0.0, 1.0f);
    out.position = proj * view * worldArray[instanceID] * position;
    out.color = vertexArray[vertexID].color;
    return out;
    
}

fragment float4
fragmentShader(RasterizerData in [[stage_in]]) {
    return float4(in.color, 1.0);
}


