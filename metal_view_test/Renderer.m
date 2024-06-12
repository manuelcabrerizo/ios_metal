//
//  Renderer.m
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#import "Renderer.h"

static const MTLPixelFormat DepthPixelFormat = MTLPixelFormatDepth32Float;
static const NSUInteger MaxFramesInFlight = 3;
static const uint32_t MaxQuadCount = 4000;

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
    MTLRenderPassDescriptor *_loadScreenRenderDescriptor;

    id<MTLRenderPipelineState> _pipelineState;
    
    id<CAMetalDrawable> currentDrawable;

    // instance renderer
    id<MTLBuffer> _vbuffer[MaxFramesInFlight];
    
    id<MTLCommandBuffer> commandBuffer;
    id<MTLRenderCommandEncoder> renderEncoder;
    
    
    id<MTLBuffer>  _wbuffer[MaxFramesInFlight][3];
    uint32_t _quadCount[MaxFramesInFlight][3];
    dispatch_semaphore_t _wbuffer_semaphore;
    int _wbuffer_semaphore_index;
    
    matrix_float4x4 _proj;
    matrix_float4x4 _view;
}

- (nonnull instancetype)initWithMetalDevice:(nonnull id<MTLDevice>)device
                        drawablePixelFormat:(MTLPixelFormat)drawabklePixelFormat {
    
    self = [super init];
    if(self) {
        
        _inFlightSemaphore = dispatch_semaphore_create(MaxFramesInFlight);
        _wbuffer_semaphore = dispatch_semaphore_create(3);
        _wbuffer_semaphore_index = 0;
        _currentBuffer = 0;
        _device = device;
        _commandQueue = [_device newCommandQueue];
        
        _clearScreenRenderDescriptor = [MTLRenderPassDescriptor new];
        _clearScreenRenderDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _clearScreenRenderDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _clearScreenRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 1, 1);
        _clearScreenRenderDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        _clearScreenRenderDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
        _clearScreenRenderDescriptor.depthAttachment.clearDepth = 1.0;
        
        _loadScreenRenderDescriptor = [MTLRenderPassDescriptor new];
        _loadScreenRenderDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
        _loadScreenRenderDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _loadScreenRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 1, 1);
        _loadScreenRenderDescriptor.depthAttachment.loadAction = MTLLoadActionLoad;
        _loadScreenRenderDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
        _loadScreenRenderDescriptor.depthAttachment.clearDepth = 1.0;
                
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
            
            for(int j = 0; j < 3; j++) {
                _wbuffer[i][j] = [device newBufferWithLength:MaxQuadCount * sizeof(matrix_float4x4)
                                                     options:MTLResourceCPUCacheModeDefaultCache];
                _quadCount[j][i] = 0;
            }
            
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
    _loadScreenRenderDescriptor.depthAttachment.texture = _depthTarget;
}

- (void)set_proj:(matrix_float4x4) proj {
    _proj = proj;
}
- (void)set_view:(matrix_float4x4) view {
    _view = view;
}


- (void)frame_begin:(nonnull CAMetalLayer *)layer  {
    // Wait to ensure only `MaxFramesInFlight` number of frames are getting processed
    // by any stage in the Metal pipeline (CPU, GPU, Metal, Drivers, etc.).
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
    // Iterate through the Metal buffers, and cycle back to the first when you've written to the last.
    _currentBuffer = (_currentBuffer + 1) % MaxFramesInFlight;
    
    currentDrawable = [layer nextDrawable];
    if(!currentDrawable) {
        return;
    }
}

- (void)frame_end:(nonnull CAMetalLayer *)layer  {
    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:currentDrawable];

    __block dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
         dispatch_semaphore_signal(block_semaphore);
    }];
    
    [commandBuffer commit];
}

- (void)render_batch_begin:(RenderBatch *_Nonnull) batch
               first_batch:(bool) first {
    
    if(first) {
        commandBuffer = [_commandQueue commandBuffer];
        _clearScreenRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
        renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_clearScreenRenderDescriptor];
        batch->bufferIndex = [self get_free_wbuffer];
    }
    
    [renderEncoder setRenderPipelineState:_pipelineState];
    [renderEncoder setVertexBuffer:_vbuffer[_currentBuffer] offset:0 atIndex:VertexInputIndexVertices];
    [renderEncoder setVertexBytes:&_view length:sizeof(matrix_float4x4) atIndex:VertexInputIndexView];
    [renderEncoder setVertexBytes:&_proj length:sizeof(matrix_float4x4) atIndex:VertexInputIndexProj];
}

- (void)render_batch_end:(RenderBatch *_Nonnull) batch{
    [renderEncoder setVertexBuffer:_wbuffer[_currentBuffer][batch->bufferIndex]
                                  offset:0 atIndex:VertexInputIndexWorld];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:_quadCount[_currentBuffer][batch->bufferIndex]];
    [renderEncoder endEncoding];

    __block dispatch_semaphore_t block_wbuffer_semaphore = _wbuffer_semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
         dispatch_semaphore_signal(block_wbuffer_semaphore);
    }];
    
    [commandBuffer commit];
    
    _quadCount[_currentBuffer][batch->bufferIndex] = 0;

    commandBuffer = [_commandQueue commandBuffer];
    _loadScreenRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
    renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_loadScreenRenderDescriptor];
    [renderEncoder setRenderPipelineState:_pipelineState];
    [renderEncoder setVertexBuffer:_vbuffer[_currentBuffer] offset:0 atIndex:VertexInputIndexVertices];
    [renderEncoder setVertexBytes:&_view length:sizeof(matrix_float4x4) atIndex:VertexInputIndexView];
    [renderEncoder setVertexBytes:&_proj length:sizeof(matrix_float4x4) atIndex:VertexInputIndexProj];
}


- (int)get_free_wbuffer {
    dispatch_semaphore_wait(_wbuffer_semaphore, DISPATCH_TIME_FOREVER);
    int index = _wbuffer_semaphore_index;
    _wbuffer_semaphore_index = (_wbuffer_semaphore_index + 1) % 3;
    return  index;
}

- (void)draw_quad:(matrix_float4x4)world
            batch:(RenderBatch *_Nonnull)batch {
    
    if(_quadCount[_currentBuffer][batch->bufferIndex] == MaxQuadCount) {
        [self render_batch_end:batch];
        batch->bufferIndex = [self get_free_wbuffer];
    }
    
    matrix_float4x4 *dst = _wbuffer[_currentBuffer][batch->bufferIndex].contents + (sizeof(matrix_float4x4) * _quadCount[_currentBuffer][batch->bufferIndex]);
    memcpy(dst, &world, sizeof(matrix_float4x4));
    _quadCount[_currentBuffer][batch->bufferIndex]++;
    
}

@end
