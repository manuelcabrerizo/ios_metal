//
//  SoundSystem.h
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 17/06/2024.
//

#ifndef SoundSystem_h
#define SoundSystem_h

#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>

typedef int MacSoundHandle; 

typedef struct MacSoundStream {
    void *data;
    size_t size;
} MacSoundStream;

typedef struct MacSoundChannel {
    MacSoundStream stream;

    int sampleCount;
    int currentSample;

    int next;
    int prev;

    bool loop;
    bool playing;
} MacSoundChannel;

typedef struct MacSoundSystem {
    MacSoundChannel *channels;
    size_t channelBufferSize;
    int first;
    int firstFree;
    int channelsCount;
    int channelsUsed;
} MacSoundSystem;

void MacSoundSysInitialize(MacSoundSystem *soundSys, int maxChannels);
void MacSoundSysShutdown(MacSoundSystem *soundSys);
MacSoundHandle MacSoundSysAdd(MacSoundSystem *soundSys, MacSoundStream stream, bool playing, bool looping);
void MacSoundSysRemove(MacSoundSystem *soundSys, MacSoundHandle *outHandle);
void MacSoundSysPlay(MacSoundSystem *soundSys, MacSoundHandle handle);
void MacSoundSysPause(MacSoundSystem *soundSys, MacSoundHandle handle);
void MacSoundSysRestart(MacSoundSystem *soundSys, MacSoundHandle handle);

OSStatus CoreAudioCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
                           const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
                           UInt32 inNumberFrames, AudioBufferList *ioData);

#endif /* SoundSystem_h */
