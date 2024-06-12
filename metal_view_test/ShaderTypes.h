//
//  ShaderTypes.h
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

typedef enum VertexInputIndex {
    VertexInputIndexVertices = 0,
    VertexInputIndexWorld = 1,
    VertexInputIndexView = 2,
    VertexInputIndexProj = 3
} VertexInputIndex;

typedef struct {
    vector_float2 position;
    vector_float3 color;
    vector_float2   uvs;
} Vertex;

typedef struct Uniform {
    matrix_float4x4 world;
    uint32_t textureId;
} Uniform;

#endif /* ShaderTypes_h */
