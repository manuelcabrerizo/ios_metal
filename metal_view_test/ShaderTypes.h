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
} Vertex;

#endif /* ShaderTypes_h */
