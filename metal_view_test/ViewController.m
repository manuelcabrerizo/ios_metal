//
//  ViewController.m
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#import "ViewController.h"
#import "Renderer.h"

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz) {
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis) {
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;

    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0},
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0},
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0},
        {                   0,                   0,                   0, 1}
    }};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ) {
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}



@implementation ViewController {
    Renderer *_renderer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    View *view = (View *)self.view;
    // Set the device for the layer so the layer can create drawable textures that can be rendered to
    // on this device.
    view.metalLayer.device = device;
    // Set this class as the delegate to receive resize and render callbacks.
    view.delegate = self;
    view.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    _renderer = [[Renderer alloc] initWithMetalDevice:device drawablePixelFormat:view.metalLayer.pixelFormat];
    
    float aspect = (float)view.bounds.size.width / (float)view.bounds.size.height;
    [_renderer set_proj:matrix_perspective_right_hand(65.0f * (M_PI / 180.0f), aspect, 0.1f, 200.0f)];
    [_renderer set_view:matrix4x4_translation(0.0, 0.0, -12.0)];
    
}

- (void)drawableResize:(CGSize)size {
    [_renderer drawableResize:size];
}

- (void)renderToMetalLayer:(nonnull CAMetalLayer *)layer {
    @autoreleasepool {
        RenderBatch batch = [_renderer frame_begin:layer];
        
        for(int i = -50; i < 50; i++) {
            matrix_float4x4 world = matrix4x4_translation(0, i*3, -20);
            [_renderer draw_quad:world batch:&batch];
        }
        
        [_renderer frame_end:&batch];
    }

}
@end
