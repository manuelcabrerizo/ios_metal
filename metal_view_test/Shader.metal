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
    float2 uvs;
    uint textureId;
};

vertex RasterizerData
vertexShader(uint vertexID [[vertex_id]],
             uint instanceID [[instance_id]],
             constant Vertex *vertexArray [[buffer(VertexInputIndexVertices)]],
             constant Uniform *uniforms [[buffer(VertexInputIndexWorld)]],
             constant matrix_float4x4 &view  [[buffer(VertexInputIndexView)]],
             constant matrix_float4x4 &proj  [[buffer(VertexInputIndexProj)]]) {
    
    RasterizerData out;
    float4 position = float4(vertexArray[vertexID].position.xy, 0.0, 1.0f);
    out.position = proj * view * uniforms[instanceID].world * position;
    out.color = vertexArray[vertexID].color;
    out.uvs = vertexArray[vertexID].uvs;
    out.textureId = uniforms[instanceID].textureId;
    return out;
    
}

fragment float4
fragmentShader(RasterizerData in [[stage_in]],
               array<texture2d<float>, 3> textures [[texture(0)]]) {
    
    constexpr sampler defaultSampler;
    float4 color = textures[in.textureId].sample(defaultSampler, in.uvs);
    return color;
}


