//
//  Renderer.m
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#import "Renderer.h"

static const NSUInteger MaxFramesInFlight = 3;
static const uint32_t MaxQuadCount = 10000;
static const uint32_t MaxWBufferCount = 3;

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
    MTLRenderPassDescriptor *_clearScreenRenderDescriptor;
    MTLRenderPassDescriptor *_loadScreenRenderDescriptor;

    id<MTLRenderPipelineState> _pipelineState;
    
    id<CAMetalDrawable> currentDrawable;

    // instance renderer
    id<MTLBuffer> _vbuffer[MaxFramesInFlight];
    id<MTLBuffer>  _wbuffer[MaxFramesInFlight][MaxWBufferCount];
    uint32_t _quadCount;
    uint32_t _bufferIndex;

    
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
        
        _clearScreenRenderDescriptor = [MTLRenderPassDescriptor new];
        _clearScreenRenderDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _clearScreenRenderDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _clearScreenRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 1, 1);
        
        _loadScreenRenderDescriptor = [MTLRenderPassDescriptor new];
        _loadScreenRenderDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
        _loadScreenRenderDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _loadScreenRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 1, 1);
                
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
        
        NSError *error;
        _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if(!_pipelineState) {
            NSLog(@"Error: Failed aquiring pipeline state: %@", error);
            return NULL;
        }
        
        _quadCount = 0;
        _bufferIndex = 0;
        for(int i = 0; i < MaxFramesInFlight; i++) {
            _vbuffer[i] = [device newBufferWithBytes:&QuadVertices
                                              length:(sizeof(Vertex) * 6)
                                             options:MTLResourceStorageModeShared];
            
            for(int j = 0; j < MaxWBufferCount; j++) {
                _wbuffer[i][j] = [device newBufferWithLength:MaxQuadCount * sizeof(matrix_float4x4)
                                                  options:MTLResourceCPUCacheModeDefaultCache];
            }
        }
    }
    return self;
}


- (void)drawableResize:(CGSize)drawableSize {
}

- (void)set_proj:(matrix_float4x4) proj {
    _proj = proj;
}
- (void)set_view:(matrix_float4x4) view {
    _view = view;
}


- (RenderBatch)frame_begin:(nonnull CAMetalLayer *)layer {
    // Wait to ensure only `MaxFramesInFlight` number of frames are getting processed
    // by any stage in the Metal pipeline (CPU, GPU, Metal, Drivers, etc.).
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
    // Iterate through the Metal buffers, and cycle back to the first when you've written to the last.
    _currentBuffer = (_currentBuffer + 1) % MaxFramesInFlight;
    _bufferIndex = 0;
    _quadCount = 0;
    
    currentDrawable = [layer nextDrawable];

    RenderBatch batch;
    batch.commandBuffer = [_commandQueue commandBuffer];
    _clearScreenRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
    batch.renderEncoder = [batch.commandBuffer renderCommandEncoderWithDescriptor:_clearScreenRenderDescriptor];
    
    [batch.renderEncoder setRenderPipelineState:_pipelineState];
    [batch.renderEncoder setVertexBuffer:_vbuffer[_currentBuffer] offset:0 atIndex:VertexInputIndexVertices];
    [batch.renderEncoder setVertexBytes:&_view length:sizeof(matrix_float4x4) atIndex:VertexInputIndexView];
    [batch.renderEncoder setVertexBytes:&_proj length:sizeof(matrix_float4x4) atIndex:VertexInputIndexProj];
    
    return batch;
}

- (void)frame_end:(RenderBatch *_Nonnull) batch {
    if(_quadCount > 0) {
        [batch->renderEncoder setVertexBuffer:_wbuffer[_currentBuffer][_bufferIndex]
                                       offset:0 atIndex:VertexInputIndexWorld];
        [batch->renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:_quadCount];
        _quadCount = 0;
    }
    
    [batch->renderEncoder endEncoding];
    [batch->commandBuffer presentDrawable:currentDrawable];

    __block dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
    [batch->commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
         dispatch_semaphore_signal(block_semaphore);
    }];
    [batch->commandBuffer commit];
}


- (void)draw_quad:(matrix_float4x4)world
            batch:(RenderBatch *_Nonnull)batch {
    
    if(_bufferIndex == MaxWBufferCount) {
        return;
    }
    
    matrix_float4x4 *dst = _wbuffer[_currentBuffer][_bufferIndex].contents + (sizeof(matrix_float4x4) * _quadCount);
    memcpy(dst, &world, sizeof(matrix_float4x4));
    _quadCount++;
    
    if(_quadCount == MaxQuadCount) {
        [batch->renderEncoder setVertexBuffer:_wbuffer[_currentBuffer][_bufferIndex]
                                      offset:0 atIndex:VertexInputIndexWorld];
        [batch->renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:_quadCount];
        _quadCount = 0;
        _bufferIndex++;
    }
}

@end
