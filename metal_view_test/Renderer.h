//
//  Renderer.h
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#ifndef Renderer_h
#define Renderer_h

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import "ShaderTypes.h"

@interface Renderer : NSObject

- (nonnull instancetype)initWithMetalDevice:(nonnull id<MTLDevice>)device
                        drawablePixelFormat:(MTLPixelFormat)drawabklePixelFormat;

- (void)drawableResize:(CGSize)drawableSize;

- (void)frame_begin;
- (void)frame_end:(nonnull CAMetalLayer *)layer;

- (void)set_proj:(matrix_float4x4) proj;
- (void)set_view:(matrix_float4x4) view;
- (void)draw_quad:(matrix_float4x4) world;

@end

#endif /* Renderer_h */
