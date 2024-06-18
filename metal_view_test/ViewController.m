//
//  ViewController.m
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#import "ViewController.h"
#import "Renderer.h"

#import <AVFoundation/AVFoundation.h>


#include "SoundSystem.h"



typedef struct WaveFileHeader
{
	//the main chunk
	unsigned char m_szChunkID[4];
	unsigned int m_nChunkSize;
	unsigned char m_szFormat[4];

	//sub chunk 1 "fmt "
	unsigned char m_szSubChunk1ID[4];
	unsigned int m_nSubChunk1Size;
	unsigned short m_nAudioFormat;
	unsigned short m_nNumChannels;
	unsigned int m_nSampleRate;
	unsigned int m_nByteRate;
	unsigned short m_nBlockAlign;
	unsigned short m_nBitsPerSample;

	//sub chunk 2 "data"
	unsigned char m_szSubChunk2ID[4];
	unsigned int m_nSubChunk2Size;

	//then comes the data!
} WaveFileHeader;

MacSoundStream LoadWavFile(const char *szFileName) {

    FILE *file = fopen(szFileName, "rb");
    if(!file) {
        MacSoundStream zero = {};
        return zero;
    }
    // go to the end of the file
    fseek(file, 0, SEEK_END);
    // get the size of the file to alloc the memory we need
    long int fileSize = ftell(file);
    // go back to the start of the file
    fseek(file, 0, SEEK_SET);
    // alloc the memory
    unsigned char *wavData = (unsigned char *)malloc(fileSize + 1);
    memset(wavData, 0, fileSize + 1);
    // store the content of the file
    fread(wavData, fileSize, 1, file);
    wavData[fileSize] = '\0'; // null terminating string...
    fclose(file);

   
    WaveFileHeader *header = (WaveFileHeader *)wavData;
    void *data = (wavData + sizeof(WaveFileHeader)); 

    MacSoundStream stream;
    stream.data = data;
    stream.size = header->m_nSubChunk2Size;
    return stream;
}


#define PI 3.14159265359

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

OSStatus core_audio_callback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
                             UInt32 inNumberFrames, AudioBufferList *ioData) {

    return noErr;
}

const float MaxDistance = 16*4;

static MacSoundSystem sound_system;


@implementation ViewController {
    // the rederer
    Renderer *_renderer;
    // input handling    
    bool _is_touching;
    Vec2 s_pos;
    Vec2 c_pos;
    // hero data
    Vec2 hero_pos;
    float hero_rot;

    AUAudioUnit *_audio_unit;

    MacSoundHandle sound_handle;
    MacSoundStream stream;
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

    // Initialize the audio unit
    AudioComponentDescription defaultOutputDescription;
    defaultOutputDescription.componentType = kAudioUnitType_Output;
    defaultOutputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    defaultOutputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    defaultOutputDescription.componentFlags = 0;
    defaultOutputDescription.componentFlagsMask = 0;

    NSError *error = nil;
    _audio_unit = [[AUAudioUnit alloc] initWithComponentDescription:defaultOutputDescription error:&error];

    // init render callback struct for core audio
    _audio_unit.outputProvider = ^AUAudioUnitStatus(AudioUnitRenderActionFlags * _Nonnull actionFlags,
                                                    const AudioTimeStamp * _Nonnull timestamp,
                                                    AUAudioFrameCount frameCount,
                                                    NSInteger inputBusNumber,
                                                    AudioBufferList * _Nonnull inputData) {
        return CoreAudioCallback(&sound_system, actionFlags, timestamp, (UInt32)inputBusNumber, (UInt32)frameCount, inputData);
    };
    
    AudioStreamBasicDescription streamFormat;
    streamFormat.mSampleRate = 44100;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger; 
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerPacket = 2 * sizeof(short);
    streamFormat.mChannelsPerFrame = 2;
    streamFormat.mBitsPerChannel =  sizeof(short) * 8;
    streamFormat.mBytesPerFrame = 2 * sizeof(short);
    
    AVAudioFormat *audioFormat = [[AVAudioFormat alloc] initWithStreamDescription:&streamFormat];
    [_audio_unit.inputBusses[0] setFormat:audioFormat error:&error];

    // init audio
    MacSoundSysInitialize(&sound_system, 1024);

    // load our sound file
    NSString *soundPath = [[NSBundle mainBundle] pathForResource: [NSString stringWithUTF8String:"test"] ofType: @"wav"];
    if(soundPath != nil) {
        stream = LoadWavFile([soundPath UTF8String]);
        sound_handle = MacSoundSysAdd(&sound_system, stream, true, true);
    }
    else {
        stream.data = NULL;
        stream.size = 0;
        sound_handle = -1;
    }

    if(sound_handle > -1) {
        MacSoundSysPlay(&sound_system, sound_handle);
    }

    [_audio_unit allocateRenderResourcesAndReturnError:&error];
    if(error) {
        NSLog(@"Error allocating render resources: %@", error.localizedDescription);    
    }
    
    [_audio_unit startHardwareAndReturnError:&error];
    if (error) {
        NSLog(@"Error starting audio unit: %@", error);
        return;
    }


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
            s_pos.x = c_pos.x + dir.x * MaxDistance;
            s_pos.y = c_pos.y + dir.y * MaxDistance;
        }

        Vec2 move_dir = vec2_sub(c_pos, s_pos);
        move_dir.x /= MaxDistance;
        move_dir.y /= MaxDistance;
        float move_len = vec2_len(move_dir);
        if(move_len > 0.0) {
            if(move_len > 1.0) {
                move_dir = vec2_normalized(move_dir);
            }
            hero_pos.x += move_dir.x * 6;
            hero_pos.y += move_dir.y * 6;
            move_dir = vec2_normalized(move_dir);
            hero_rot = atan2(move_dir.y, move_dir.x);

        }
    }

    @autoreleasepool {
        RenderBatch batch = [_renderer frame_begin:layer];
        vector_float3 rot_axis = {0, 0, 1};
        matrix_float4x4 world = matrix_multiply(matrix4x4_translation(hero_pos.x, hero_pos.y, -20),matrix_multiply(matrix4x4_rotation(hero_rot - PI/2, rot_axis), matrix4x4_scale(16*4, 24*4, 1)));
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
