//
//  Renderer.m
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#import "Renderer.h"

static const MTLPixelFormat DepthPixelFormat = MTLPixelFormatDepth32Float;
static const NSUInteger MaxFramesInFlight = 3;
static const uint32_t MaxQuadCount = 20000;

static const Vertex QuadVertices[] = {
    // Pixel positions, Color coordinates
    { {  1,  -1 },  { 1.f, 0.f, 0.f } },
    { { -1,  -1 },  { 0.f, 1.f, 0.f } },
    { { -1,   1 },  { 0.f, 0.f, 1.f } },

    { {  1,  -1 },  { 1.f, 0.f, 0.f } },
    { { -1,   1 },  { 0.f, 0.f, 1.f } },
    { {  1,   1 },  { 1.f, 0.f, 1.f } },
};


@implementation Renderer
{
    dispatch_semaphore_t _inFlightSemaphore;
    NSUInteger _currentBuffer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLTexture> _depthTarget;
    MTLRenderPassDescriptor *_clearScreenRenderDescriptor;
    id<MTLRenderPipelineState> _pipelineState;

    // instance renderer
    id<MTLBuffer> _vbuffer[MaxFramesInFlight];
    id<MTLBuffer>  _wbuffer[MaxFramesInFlight];
    uint32_t _quadCount;
    
    matrix_float4x4 _proj;
    matrix_float4x4 _view;
}

- (nonnull instancetype)initWithMetalDevice:(nonnull id<MTLDevice>)device
                        drawablePixelFormat:(MTLPixelFormat)drawabklePixelFormat {
    
    self = [super init];
    if(self) {
        
        _inFlightSemaphore = dispatch_semaphore_create(MaxFramesInFlight);
        _currentBuffer = 0;
        _device = device;
        _commandQueue = [_device newCommandQueue];
        _quadCount = 0;
        
        _clearScreenRenderDescriptor = [MTLRenderPassDescriptor new];
        _clearScreenRenderDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _clearScreenRenderDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _clearScreenRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 1, 1);
        _clearScreenRenderDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        _clearScreenRenderDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
        _clearScreenRenderDescriptor.depthAttachment.clearDepth = 1.0;
                
        id<MTLLibrary> shaderLib = [device newDefaultLibrary];
        if(!shaderLib) {
            NSLog(@"Error: couldnt create a default shader library");
            return NULL;
        }
        
        id<MTLFunction> vertexProgram = [shaderLib newFunctionWithName:@"vertexShader"];
        if(!vertexProgram) {
            NSLog(@"Error: couldnt load vertex function from shader lib");
            return NULL;
        }
        
        id<MTLFunction> fragmentProgram = [shaderLib newFunctionWithName:@"fragmentShader"];
        if(!fragmentProgram) {
            NSLog(@"Error: couldnt load fragment function from shader lib");
            return NULL;
        }
        
        // create a pipeline state descriptor to create a compile pipeline state object
        MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.label = @"MyPipeline";
        pipelineDescriptor.vertexFunction = vertexProgram;
        pipelineDescriptor.fragmentFunction = fragmentProgram;
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        pipelineDescriptor.depthAttachmentPixelFormat = DepthPixelFormat;
        
        NSError *error;
        _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if(!_pipelineState) {
            NSLog(@"Error: Failed aquiring pipeline state: %@", error);
            return NULL;
        }
        
        for(int i = 0; i < MaxFramesInFlight; i++) {

            _vbuffer[i] = [device newBufferWithBytes:&QuadVertices
                                              length:(sizeof(Vertex) * 6)
                                             options:MTLResourceStorageModeShared];
            
            _wbuffer[i] = [device newBufferWithLength:MaxQuadCount * sizeof(matrix_float4x4)
                                              options:MTLResourceCPUCacheModeDefaultCache];
        }
    }
    return self;
}


- (void)drawableResize:(CGSize)drawableSize {
    MTLTextureDescriptor *depthTargetDescriptor = [MTLTextureDescriptor new];
    depthTargetDescriptor.width       = drawableSize.width;
    depthTargetDescriptor.height      = drawableSize.height;
    depthTargetDescriptor.pixelFormat = DepthPixelFormat;
    depthTargetDescriptor.storageMode = MTLStorageModePrivate;
    depthTargetDescriptor.usage       = MTLTextureUsageRenderTarget;
    _depthTarget = [_device newTextureWithDescriptor:depthTargetDescriptor];
    _clearScreenRenderDescriptor.depthAttachment.texture = _depthTarget;
}

- (void)set_proj:(matrix_float4x4) proj {
    _proj = proj;
}
- (void)set_view:(matrix_float4x4) view {
    _view = view;
}


- (void)frame_begin {
    // Wait to ensure only `MaxFramesInFlight` number of frames are getting processed
    // by any stage in the Metal pipeline (CPU, GPU, Metal, Drivers, etc.).
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
    // Iterate through the Metal buffers, and cycle back to the first when you've written to the last.
    _currentBuffer = (_currentBuffer + 1) % MaxFramesInFlight;

}

- (void)frame_end:(nonnull CAMetalLayer *)layer  {
    
    id<CAMetalDrawable> currentDrawable = [layer nextDrawable];
    if(!currentDrawable) {
        return;
    }
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    _clearScreenRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_clearScreenRenderDescriptor];
    [renderEncoder setRenderPipelineState:_pipelineState];
    
    [renderEncoder setVertexBuffer:_vbuffer[_currentBuffer] offset:0 atIndex:VertexInputIndexVertices];
    [renderEncoder setVertexBuffer:_wbuffer[_currentBuffer] offset:0 atIndex:VertexInputIndexWorld];
    [renderEncoder setVertexBytes:&_view length:sizeof(matrix_float4x4) atIndex:VertexInputIndexView];
    [renderEncoder setVertexBytes:&_proj length:sizeof(matrix_float4x4) atIndex:VertexInputIndexProj];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:_quadCount];
    
    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:currentDrawable];
    
    __block dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         dispatch_semaphore_signal(block_semaphore);
     }];
    
    [commandBuffer commit];
    
    _quadCount = 0;
}

- (void)draw_quad:(matrix_float4x4) world {
    matrix_float4x4 *dst = _wbuffer[_currentBuffer].contents + (sizeof(matrix_float4x4) * _quadCount);
    memcpy(dst, &world, sizeof(matrix_float4x4));
    _quadCount++;
    
    NSAssert(_quadCount <= MaxQuadCount, @"Error: Max Quads exceeded!");
}

@end
