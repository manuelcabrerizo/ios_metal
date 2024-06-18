//
//  Renderer.m
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#import<MetalKit/MetalKit.h>
#import "Renderer.h"

static const NSUInteger MaxFramesInFlight = 3;
static const uint32_t MaxQuadCount = 10000;
static const uint32_t MaxWBufferCount = 3;

static const Vertex QuadVertices[] = {
    // Pixel positions, Color coordinates
    { {  0.5,  -0.5 },  { 1.f, 0.f, 0.f }, {1, 1} },
    { { -0.5,  -0.5 },  { 0.f, 1.f, 0.f }, {0, 1} },
    { { -0.5,   0.5 },  { 0.f, 0.f, 1.f }, {0, 0} },

    { {  0.5,  -0.5 },  { 1.f, 0.f, 0.f }, {1, 1} },
    { { -0.5,   0.5 },  { 0.f, 0.f, 1.f }, {0, 0} },
    { {  0.5,   0.5 },  { 1.f, 0.f, 1.f }, {1, 0} }
};


@implementation Renderer
{
    dispatch_semaphore_t _inFlightSemaphore;
    NSUInteger _currentBuffer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    MTLRenderPassDescriptor *_clearScreenRenderDescriptor;

    id<MTLRenderPipelineState> _pipelineState;
    
    id<CAMetalDrawable> _currentDrawable;

    // instance renderer
    id<MTLBuffer> _vbuffer[MaxFramesInFlight];
    id<MTLBuffer>  _ubuffer[MaxFramesInFlight][MaxWBufferCount];
    uint32_t _quadCount;
    uint32_t _bufferIndex;
    
    id<MTLTexture> _texture[3];
    

    
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
        _clearScreenRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.2, 0.2, 0.2, 1);
                        
        id<MTLLibrary> shaderLib = [device newDefaultLibrary];
        if(!shaderLib) {
            NSLog(@"Error: couldnt create a default shader library");
            return nil;
        }
        
        id<MTLFunction> vertexProgram = [shaderLib newFunctionWithName:@"vertexShader"];
        if(!vertexProgram) {
            NSLog(@"Error: couldnt load vertex function from shader lib");
            return nil;
        }
        
        id<MTLFunction> fragmentProgram = [shaderLib newFunctionWithName:@"fragmentShader"];
        if(!fragmentProgram) {
            NSLog(@"Error: couldnt load fragment function from shader lib");
            return nil;
        }
        
        // create a pipeline state descriptor to create a compile pipeline state object
        MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.label = @"MyPipeline";
        pipelineDescriptor.vertexFunction = vertexProgram;
        pipelineDescriptor.fragmentFunction = fragmentProgram;
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        pipelineDescriptor.colorAttachments[0].blendingEnabled = true;
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        
        NSError *error;
        _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if(!_pipelineState) {
            NSLog(@"Error: Failed aquiring pipeline state: %@", error);
            return nil;
        }
        
        _quadCount = 0;
        _bufferIndex = 0;
        for(int i = 0; i < MaxFramesInFlight; i++) {
            _vbuffer[i] = [device newBufferWithBytes:&QuadVertices
                                              length:(sizeof(Vertex) * 6)
                                             options:MTLResourceStorageModeShared];
            
            for(int j = 0; j < MaxWBufferCount; j++) {
                _ubuffer[i][j] = [device newBufferWithLength:MaxQuadCount * sizeof(Uniform)
                                                  options:MTLResourceCPUCacheModeDefaultCache];
            }
        }
        
        
        // load textures using MetalKit
        MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:device];
        
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"link.png"  withExtension:nil];
        _texture[0] = [loader newTextureWithContentsOfURL:url options:nil error:&error];
        if(!_texture) {
            NSLog(@"Error loading texturec from %@: %@", url.absoluteString, error.localizedDescription);
            return nil;
        }
        
        url = [[NSBundle mainBundle] URLForResource:@"button_out.png"  withExtension:nil];
        _texture[1] = [loader newTextureWithContentsOfURL:url options:nil error:&error];
        if(!_texture) {
            NSLog(@"Error loading texturec from %@: %@", url.absoluteString, error.localizedDescription);
            return nil;
        }
        
        url = [[NSBundle mainBundle] URLForResource:@"button_in.png"  withExtension:nil];
        _texture[2] = [loader newTextureWithContentsOfURL:url options:nil error:&error];
        if(!_texture) {
            NSLog(@"Error loading texturec from %@: %@", url.absoluteString, error.localizedDescription);
            return nil;
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
    
    _currentDrawable = [layer nextDrawable];

    RenderBatch batch;
    batch.commandBuffer = [_commandQueue commandBuffer];
    _clearScreenRenderDescriptor.colorAttachments[0].texture = _currentDrawable.texture;
    batch.renderEncoder = [batch.commandBuffer renderCommandEncoderWithDescriptor:_clearScreenRenderDescriptor];
    
    [batch.renderEncoder setRenderPipelineState:_pipelineState];
    [batch.renderEncoder setVertexBuffer:_vbuffer[_currentBuffer] offset:0 atIndex:VertexInputIndexVertices];
    [batch.renderEncoder setVertexBytes:&_view length:sizeof(matrix_float4x4) atIndex:VertexInputIndexView];
    [batch.renderEncoder setVertexBytes:&_proj length:sizeof(matrix_float4x4) atIndex:VertexInputIndexProj];
    [batch.renderEncoder setFragmentTexture:_texture[0] atIndex:0];
    [batch.renderEncoder setFragmentTexture:_texture[1] atIndex:1];
    [batch.renderEncoder setFragmentTexture:_texture[2] atIndex:2];

    
    return batch;
}

- (void)frame_end:(RenderBatch *_Nonnull) batch {
    if(_quadCount > 0) {
        [batch->renderEncoder setVertexBuffer:_ubuffer[_currentBuffer][_bufferIndex]
                                       offset:0 atIndex:VertexInputIndexWorld];
        [batch->renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:_quadCount];
        _quadCount = 0;
    }
    
    [batch->renderEncoder endEncoding];
    [batch->commandBuffer presentDrawable:_currentDrawable];

    __block dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
    [batch->commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
         dispatch_semaphore_signal(block_semaphore);
    }];
    [batch->commandBuffer commit];
}


- (void)draw_quad:(matrix_float4x4) world
          texture:(uint32_t) textureId
            batch:(RenderBatch *_Nonnull) batch {
    
    if(_bufferIndex == MaxWBufferCount) {
        return;
    }
    
    Uniform *dst = _ubuffer[_currentBuffer][_bufferIndex].contents + (sizeof(Uniform) * _quadCount);
    memcpy(&dst->world, &world, sizeof(matrix_float4x4));
    dst->textureId = textureId;
    _quadCount++;
    
    if(_quadCount == MaxQuadCount) {
        [batch->renderEncoder setVertexBuffer:_ubuffer[_currentBuffer][_bufferIndex]
                                       offset:0 atIndex:VertexInputIndexWorld];

        [batch->renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle 
                                 vertexStart:0
                                 vertexCount:6
                               instanceCount:_quadCount];
        _quadCount = 0;
        _bufferIndex++;
    }
}

@end
