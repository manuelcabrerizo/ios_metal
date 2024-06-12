//
//  ViewController.m
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#import "ViewController.h"
#import "Renderer.h"

matrix_float4x4 matrix4x4_scale(float sx, float sy, float sz) {
    return (matrix_float4x4) {{
        { sx,  0,  0,  0 },
        {  0, sy,  0,  0 },
        {  0,  0, sz,  0 },
        {  0,  0,  0,  1 }
    }};
}

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

matrix_float4x4 matrix_ortho(float l, float r, float b, float t, float n, float f) {
    return (matrix_float4x4) {{
        {2.0f / (r - l), 0, 0, 0},
        {0, 2.0f / (t - b), 0, 0},
        {0, 0, 1.0f / (f - n), 0},
        {(l + r) / (l - r), (t + b) / (b - t), n / (n - f), 1}
    }};
}

typedef struct Vec2 {
    float x;
    float y;
} Vec2;

Vec2 vec2_sub(Vec2 a, Vec2 b) {
    Vec2 result;
    result.x = a.x - b.x;
    result.y = a.y - b.y;
    return result;
}

Vec2 vec2_add(Vec2 a, Vec2 b) {
    Vec2 result;
    result.x = a.x + b.x;
    result.y = a.y + b.y;
    return result;
}

float vec2_dot(Vec2 a, Vec2 b) {
    return a.x * b.x + a.y * b.y;
}

float vec2_len(Vec2 v) {
    return sqrtf(vec2_dot(v, v));
}

Vec2 vec2_normalized(Vec2 v) {
    float len = vec2_len(v);
    if(len <= 0.0) {
        return v;
    }
    
    Vec2 result;
    result.x = v.x / len;
    result.y = v.y / len;
    return result;
    
}

const float MaxDistance = 16*4;

@implementation ViewController {
    Renderer *_renderer;
    
    bool _is_touching;
    Vec2 s_pos;
    Vec2 c_pos;
    
    Vec2 hero_pos;

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
    
    //float aspect = (float)view.bounds.size.width / (float)view.bounds.size.height;
    //[_renderer set_proj:matrix_perspective_right_hand(65.0f * (M_PI / 180.0f), aspect, 0.1f, 200.0f)];
    float hw = (float)view.bounds.size.width * 0.5f;
    float hh = (float)view.bounds.size.height * 0.5f;
    [_renderer set_proj:matrix_ortho(-hw, hw, -hh, hh, 0, -100.0f)];
    //[_renderer set_proj:matrix_identity_float4x4];
    [_renderer set_view:matrix4x4_translation(0, 0, 0)];
    
    _is_touching = false;


    
}

- (void)drawableResize:(CGSize)size {
    [_renderer drawableResize:size];
}

- (void)renderToMetalLayer:(nonnull CAMetalLayer *)layer {

    if(_is_touching) {
        Vec2 diff = vec2_sub(s_pos, c_pos);
        float len = vec2_len(diff);
        if(len > MaxDistance) {
            Vec2 dir = vec2_normalized(diff);
            float t = MaxDistance;
            s_pos.x = (1.0 - t) * c_pos.x + t * (c_pos.x + dir.x);
            s_pos.y = (1.0 - t) * c_pos.y + t * (c_pos.y + dir.y);
        }

        Vec2 dir = vec2_normalized(vec2_sub(c_pos, s_pos));
        hero_pos.x += dir.x * 6;
        hero_pos.y += dir.y * 6;
    }

    @autoreleasepool {
        RenderBatch batch = [_renderer frame_begin:layer];
        
        matrix_float4x4 world = matrix_multiply(matrix4x4_translation(hero_pos.x, hero_pos.y, -20), matrix4x4_scale(16*4, 24*4, 1));
        [_renderer draw_quad:world texture:0 batch:&batch];
        
        if(_is_touching) {
                    
            world = matrix_multiply(matrix4x4_translation(s_pos.x, s_pos.y, -20), matrix4x4_scale(32*4, 32*4, 1));
            [_renderer draw_quad:world texture:1 batch:&batch];
            
            world = matrix_multiply(matrix4x4_translation(c_pos.x, c_pos.y, -20), matrix4x4_scale(16*4, 16*4, 1));
            [_renderer draw_quad:world texture:2 batch:&batch];
        }
        
        [_renderer frame_end:&batch];
    }
}


- (void) touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.allObjects[0];
    _is_touching = true;
    CGPoint location = [touch locationInView:self.view];
    s_pos.x = location.x;
    s_pos.y = location.y;
    c_pos = s_pos;
    
    s_pos.x /= (float)self.view.bounds.size.width;
    s_pos.y /= (float)self.view.bounds.size.height;
    s_pos.x -= 0.5f;
    s_pos.y -= 0.5f;
    s_pos.x *= (float)self.view.bounds.size.width;
    s_pos.y *= -(float)self.view.bounds.size.height;
    
    c_pos.x /= (float)self.view.bounds.size.width;
    c_pos.y /= (float)self.view.bounds.size.height;
    c_pos.x -= 0.5f;
    c_pos.y -= 0.5f;
    c_pos.x *= (float)self.view.bounds.size.width;
    c_pos.y *= -(float)self.view.bounds.size.height;
    
}

- (void) touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.allObjects[0];
    CGPoint location = [touch locationInView:self.view];
    c_pos.x = location.x;
    c_pos.y = location.y;
    
    c_pos.x /= (float)self.view.bounds.size.width;
    c_pos.y /= (float)self.view.bounds.size.height;
    c_pos.x -= 0.5f;
    c_pos.y -= 0.5f;
    c_pos.x *= (float)self.view.bounds.size.width;
    c_pos.y *= -(float)self.view.bounds.size.height;
}

- (void) touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _is_touching = false;
}

@end
