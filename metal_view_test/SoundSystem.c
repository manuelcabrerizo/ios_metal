//
//  SoundSystem.c
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 17/06/2024.
//

#include "SoundSystem.h"
#include <stdio.h>

#define MAX(a, b) ((a) >= (b) ? (a) : (b))
#define MIN(a, b) ((a) <= (b) ? (a) : (b))

void MacSoundSysInitialize(MacSoundSystem *soundSys, int maxChannels) {
    soundSys->channelsCount = maxChannels;
    soundSys->channelsUsed = 0;
    soundSys->channelBufferSize = maxChannels * sizeof(MacSoundChannel);
    
    //soundSys->channels = (MacSoundChannel *)mmap(0, soundSys->channelBufferSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    soundSys->channels = (MacSoundChannel *)malloc(soundSys->channelBufferSize);
    memset(soundSys->channels, 0, soundSys->channelBufferSize);
    
    soundSys->first = -1;
    soundSys->firstFree = 0;
    
    // Initialize the channels and free list
    for(int i = 0; i < maxChannels; i++) {
        MacSoundChannel *channel = soundSys->channels + i; 
        channel->stream.data = NULL;
        channel->stream.size = 0;
        channel->loop = false;
        channel->playing = false;
        if(i < (maxChannels - 1))
            channel->next = i + 1;
        else
            channel->next = -1;

        if(i == 0)
            channel->prev = -1;
        else
            channel->prev = i - 1;
    }
}

void MacSoundSysShutdown(MacSoundSystem *soundSys) {
    if(soundSys->channels) {
        //munmap(soundSys->channels, soundSys->channelBufferSize);
        free(soundSys->channels);
        soundSys->channels = NULL;
        soundSys->channelsUsed = 0;
    }
}

MacSoundHandle MacSoundSysAdd(MacSoundSystem *soundSys, MacSoundStream stream, bool playing, bool looping) {

    if((soundSys->channelsUsed + 1) > soundSys->channelsCount) {
        printf("Sound system full!!!");
        return -1;
    }

    // find a free channel
    MacSoundHandle handle = soundSys->firstFree;
    if(handle < 0 || handle >= soundSys->channelsCount) {
        printf("Invalid Sound Handle!!!");
        return -1;
    }

    MacSoundChannel *channel = soundSys->channels + handle; 
    // update the free list
    soundSys->firstFree = channel->next;

    // initialize tha channel
    channel->stream = stream;
    channel->loop = looping;
    channel->playing = playing;
    channel->sampleCount = (int)(stream.size / sizeof(int));
    channel->currentSample = 0;

    channel->next = soundSys->first;
    channel->prev = -1;
 
    // set it as the first element of the active channel list
    soundSys->first = handle;

    soundSys->channelsUsed++;

    // update the next channel prev to the incoming channel
    if(channel->next >= 0) {
        MacSoundChannel *nextChannel = soundSys->channels + channel->next;
        nextChannel->prev = handle;
    }
    
    return handle;
}

void MacSoundSysRemove(MacSoundSystem *soundSys, MacSoundHandle *outHandle) {
    MacSoundHandle handle = *outHandle;
    if(handle < 0 || handle >= soundSys->channelsCount) {
        printf("Invalid Sound Handle!!!");
        return;
    }
  
    // get the channel to remove
    MacSoundChannel *channel = soundSys->channels + handle;

    // remove this channel from the active list
    MacSoundChannel *prevChannel = soundSys->channels + channel->prev;
    MacSoundChannel *nextChannel = soundSys->channels + channel->next;
    prevChannel->next = channel->next;
    nextChannel->prev = channel->prev;

    // add this channel to the free list
    channel->prev = -1;
    channel->next = soundSys->firstFree;
    soundSys->firstFree = handle;
 
    soundSys->channelsUsed--;

    *outHandle = -1;

}

void MacSoundSysPlay(MacSoundSystem *soundSys, MacSoundHandle handle) {
    if(handle < 0 || handle >= soundSys->channelsCount) {
        printf("Invalid Sound Handle!!!");
        return;
    }

    MacSoundChannel *channel = soundSys->channels + handle;
    channel->playing = true;

}

void MacSoundSysPause(MacSoundSystem *soundSys, MacSoundHandle handle) {
    if(handle < 0 || handle >= soundSys->channelsCount) {
        printf("Invalid Sound Handle!!!");
        return;
    }

    MacSoundChannel *channel = soundSys->channels + handle;
    channel->playing = false;

}

void MacSoundSysRestart(MacSoundSystem *soundSys, MacSoundHandle handle) {
    if(handle < 0 || handle >= soundSys->channelsCount) {
        printf("Invalid Sound Handle!!!");
        return;
    }

    MacSoundChannel *channel = soundSys->channels + handle;
    channel->playing = false;
    channel->currentSample = 0;
}

// CoreAudio Callback
OSStatus CoreAudioCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
                           const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
                           UInt32 inNumberFrames, AudioBufferList *ioData) {

    MacSoundSystem *soundSys = (MacSoundSystem *)inRefCon;
    short *soundBuffer = (short *)ioData->mBuffers[0].mData;
    memset(soundBuffer, 0, sizeof(int) * inNumberFrames);
    
    if(soundSys->channels == NULL) return noErr;

    // go through the actived channels in the system and play the if the are playing
    MacSoundHandle handle = soundSys->first;
    while(handle != -1) {
        MacSoundChannel *channel = soundSys->channels + handle; 
        
        if(channel->playing) {
            int samplesLeft = channel->sampleCount - channel->currentSample;
            int samplesToStream = MIN(inNumberFrames, samplesLeft);

            short *dst = soundBuffer;
            short *src = (short *)((int *)channel->stream.data + channel->currentSample);

            // TODO: simd ...
            for (UInt32 i = 0; i < samplesToStream; i++) {
                int oldValue0 = (int)dst[0];
                int oldValue1 = (int)dst[1];

                int newValue0 = (int)src[0];
                int newValue1 = (int)src[1];

                int sum0 = oldValue0 + newValue0;
                int sum1 = oldValue1 + newValue1;

                dst[0] = (short)MAX(MIN(sum0, 32767), -32768);
                dst[1] = (short)MAX(MIN(sum1, 32767), -32768);

                dst += 2;
                src += 2;
            }

            if(channel->loop) {
                channel->currentSample = (channel->currentSample + samplesToStream) % channel->sampleCount;
            }
            else {
                channel->currentSample = channel->currentSample + samplesToStream;
                if(channel->currentSample >= channel->sampleCount) {
                    channel->currentSample = 0;
                    channel->playing = false;
                }
            }
        }

        handle = channel->next;
    }
    return noErr;
}
