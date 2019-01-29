//
//  SEAudioEngine.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEAudioEngine.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "SECommon.h"

#define checkResult(result,operation) (_checkResult((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&result);
        return NO;
    }
    return YES;
}


@interface SEAudioEngine () {
    AudioUnit _audioUnit;
    SEAudioEngineRenderCallback _providerRenderCallback;
    uint64_t _outputLatency;
}
@property (nonatomic, strong) id<SEAudioEngineAudioProvider> provider;
@property (nonatomic, strong) NSArray * observerTokens;
@end


@implementation SEAudioEngine

-(instancetype)initWithAudioProvider:(id<SEAudioEngineAudioProvider>)provider {
    if ( !(self = [super init]) ) return nil;
    
    self.provider = provider;
    _providerRenderCallback = provider.renderCallback;
    
    [self setupAudioSystem];
    
    return self;
}

-(void)dealloc {
    [self teardownAudioSystem];
}

-(void)setupAudioSystem {
    
    NSError *error = nil;
    
    if ( ![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error] ) {
        NSLog(@"Couldn't set audio session category: %@", error);
    }
    
    if ( ![[AVAudioSession sharedInstance] setPreferredIOBufferDuration:(256.0/44100.0) error:&error] ) {
        NSLog(@"Couldn't set preferred buffer duration: %@", error);
    }
    
    if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
        NSLog(@"Couldn't set audio session active: %@", error);
    }
    
    // Create the audio unit
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_RemoteIO,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0
    };
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    checkResult(AudioComponentInstanceNew(inputComponent, &_audioUnit), "AudioComponentInstanceNew");
    
    // Set the stream formats
    AudioStreamBasicDescription clientFormat = [SEAudioEngine nonInterleavedFloatStereoAudioDescription];
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &clientFormat, sizeof(clientFormat)),
                "kAudioUnitProperty_StreamFormat");
    
    // Set the render callback
    AURenderCallbackStruct rcbs = { .inputProc = audioUnitRenderCallback, .inputProcRefCon = (__bridge void *)(self) };
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &rcbs, sizeof(rcbs)),
                "kAudioUnitProperty_SetRenderCallback");
    
    UInt32 framesPerSlice = 4096;
    checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &framesPerSlice, sizeof(framesPerSlice)),
                "AudioUnitSetProperty(kAudioUnitProperty_MaximumFramesPerSlice");
    
    // Initialize the audio unit
    checkResult(AudioUnitInitialize(_audioUnit), "AudioUnitInitialize");
    
    NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
    self.observerTokens = @[
        // Watch for session interruptions
        [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
            NSInteger type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
            if ( type == AVAudioSessionInterruptionTypeBegan ) {
                [self stop];
            } else {
                if ( ![self start] ) {
                    // Work around an iOS 7 audio interruption bug
                    [self teardownAudioSystem];
                    [self setupAudioSystem];
                    [self start];
                }
            }
        }],
        // Watch for route changes
        [nc addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
            _outputLatency = SESecondsToHostTicks([AVAudioSession sharedInstance].outputLatency);
        }]
    ];
}

-(void)teardownAudioSystem {
    if ( _audioUnit ) {
        checkResult(AudioComponentInstanceDispose(_audioUnit), "AudioComponentInstanceDispose");
        _audioUnit = NULL;
    }
    
    if ( self.observerTokens ) {
        for ( id token in self.observerTokens ) {
            [[NSNotificationCenter defaultCenter] removeObserver:token];
        }
        self.observerTokens = nil;
    }
}

-(BOOL)stop {
    checkResult(AudioOutputUnitStop(_audioUnit), "AudioOutputUnitStop");
    [[AVAudioSession sharedInstance] setActive:NO error:NULL];
    return YES;
}

-(BOOL)start {
    NSError *error = nil;
    if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
        NSLog(@"Couldn't activate audio session: %@", error);
        return NO;
    }
    
    _outputLatency = SESecondsToHostTicks([AVAudioSession sharedInstance].outputLatency);
    
    if ( !checkResult(AudioOutputUnitStart(_audioUnit), "AudioOutputUnitStart") ) {
        return NO;
    }
    
    return YES;
}

+ (AudioStreamBasicDescription)nonInterleavedFloatStereoAudioDescription {
    AudioStreamBasicDescription audioDescription;
    memset(&audioDescription, 0, sizeof(audioDescription));
    audioDescription.mFormatID          = kAudioFormatLinearPCM;
    audioDescription.mFormatFlags       = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    audioDescription.mChannelsPerFrame  = 2;
    audioDescription.mBytesPerPacket    = sizeof(float);
    audioDescription.mFramesPerPacket   = 1;
    audioDescription.mBytesPerFrame     = sizeof(float);
    audioDescription.mBitsPerChannel    = 8 * sizeof(float);
    audioDescription.mSampleRate        = 44100.0;
    return audioDescription;
}

static OSStatus audioUnitRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    
    for ( int i=0; i<ioData->mNumberBuffers; i++ ) {
        memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
    }
    
    __unsafe_unretained SEAudioEngine *THIS = (__bridge SEAudioEngine*)inRefCon;
    AudioTimeStamp timestamp = *inTimeStamp;
    timestamp.mHostTime += THIS->_outputLatency;
    THIS->_providerRenderCallback(THIS->_provider, &timestamp, ioData, inNumberFrames);
    
    return noErr;
}

@end
