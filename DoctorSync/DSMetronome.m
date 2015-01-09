//
//  DSMetronome.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "DSMetronome.h"
#import "SECommon.h"

NSString * const DSMetronomeDidStartNotification = @"DSMetronomeDidStartNotification";
NSString * const DSMetronomeDidStopNotification = @"DSMetronomeDidStopNotification";
NSString * const DSMetronomeDidChangeTimelineNotification = @"DSMetronomeDidChangeTimelineNotification";
NSString * const DSMetronomeDidChangeTempoNotification = @"DSMetronomeDidChangeTempoNotification";

NSString * const DSNotificationTimestampKey = @"timestamp";
NSString * const DSNotificationPositionKey = @"position";
NSString * const DSNotificationTempoKey = @"tempo";

static const double kMajorBeatFrequency = 800;
static const double kMinorBeatFrequency = 400;
static const NSTimeInterval kTickDuration = 0.1;
static const UInt32 kMicrofadeFrames = 64;

static const int kMaxTones = 2;

typedef struct {
    double frequency;
    float position;
    UInt32 offset;
    UInt32 duration;
    UInt32 remainingFrames;
} DSMetronomeTone;

@interface DSMetronome () {
    uint64_t _timeBase;
    double _positionAtStart;
    uint64_t _lastRenderEnd;
    DSMetronomeTone _tones[kMaxTones];
}
@end

@implementation DSMetronome
@dynamic started;

-(instancetype)init {
    if ( !(self = [super init]) ) return nil;
    
    _tempo = 120.0;
    
    return self;
}

-(void)startAtTime:(uint64_t)applyTime {
    [self willChangeValueForKey:@"started"];
    
    _timeBase = applyTime - SEBeatsToHostTicks(_positionAtStart, _tempo);
    _lastRenderEnd = _timeBase;
    
    [self didChangeValueForKey:@"started"];
    [[NSNotificationCenter defaultCenter] postNotificationName:DSMetronomeDidStartNotification
                                                        object:self
                                                      userInfo:@{ DSNotificationPositionKey: @(_positionAtStart),
                                                                  DSNotificationTempoKey: @(_tempo),
                                                                  DSNotificationTimestampKey: @(applyTime) }];
}

-(void)stop {
    [self willChangeValueForKey:@"started"];
    _timeBase = 0;
    _positionAtStart = 0;
    [self didChangeValueForKey:@"started"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:DSMetronomeDidStopNotification object:self];
}

-(BOOL)started {
    return _timeBase != 0;
}

-(void)setTimelinePosition:(double)timelinePosition atTime:(uint64_t)applyTime {
    if ( !_timeBase ) {
        _positionAtStart = timelinePosition;
    } else {
        _timeBase = applyTime - SEBeatsToHostTicks(timelinePosition, _tempo);
        _lastRenderEnd = _timeBase;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:DSMetronomeDidChangeTimelineNotification
                                                        object:self
                                                      userInfo:@{ DSNotificationPositionKey: @(timelinePosition),
                                                                  DSNotificationTimestampKey: @(applyTime) }];
}

-(double)timelinePositionForTime:(uint64_t)timestamp {
    if ( !_timeBase ) {
        return _positionAtStart;
    }
    
    if ( !timestamp ) {
        timestamp = SECurrentTimeInHostTicks();
    }
    
    if ( timestamp < _timeBase ) {
        return 0.0;
    }
    
    // Calculate offset from our time base, and convert to beats using current tempo
    return SEHostTicksToBeats(timestamp - _timeBase, _tempo);
}

-(void)setTempo:(double)tempo {
    if ( _timeBase ) {
        // Scale time base to new tempo, so our relative timeline position remains the same (as it is dependent on tempo)
        double ratio = _tempo / tempo;
        uint64_t now = SECurrentTimeInHostTicks();
        _timeBase = now - ((now - _timeBase) * ratio);
    }
    
    _tempo = tempo;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:DSMetronomeDidChangeTempoNotification
                                                        object:self
                                                      userInfo:@{ DSNotificationTempoKey: @(tempo) }];
}

-(DSAudioEngineRenderCallback)renderCallback {
    return render;
}

static void render(__unsafe_unretained DSMetronome * THIS, const AudioTimeStamp *time, AudioBufferList *ioData, UInt32 inNumberFrames) {
    
    // Calculate relevant position, in beats at current tempo
    uint64_t timeBase = THIS->_timeBase;
    double tempo = THIS->_tempo;
    double lastBufferPosition = THIS->_lastRenderEnd < timeBase ? -SEHostTicksToBeats(timeBase - THIS->_lastRenderEnd, tempo) : SEHostTicksToBeats(THIS->_lastRenderEnd - timeBase, tempo);
    double bufferStartPosition = time->mHostTime < timeBase ? -SEHostTicksToBeats(timeBase - time->mHostTime, tempo) : SEHostTicksToBeats(time->mHostTime - timeBase, tempo);
    uint64_t endTimestamp = time->mHostTime + SESecondsToHostTicks(inNumberFrames / 44100.0);
    double bufferEndPosition = endTimestamp < timeBase ? -SEHostTicksToBeats(timeBase - endTimestamp, tempo) : SEHostTicksToBeats(endTimestamp - timeBase, tempo);
    
    if ( timeBase && bufferEndPosition > 0.0 ) {
        // First catch up on any missed buffers
        if ( bufferStartPosition > lastBufferPosition && bufferStartPosition-lastBufferPosition < 0.5 ) {
            double offsetUnused;
            BOOL major;
            if ( findBeatBoundary(lastBufferPosition, bufferStartPosition, &offsetUnused, &major) ) {
                addTone(THIS, major ? kMajorBeatFrequency : kMinorBeatFrequency, kTickDuration * 44100.0, 0);
            }
        }
        
        // Now fill in any new tone in this buffer
        double offset;
        BOOL major;
        if ( findBeatBoundary(bufferStartPosition, bufferEndPosition, &offset, &major) ) {
            addTone(THIS, major ? kMajorBeatFrequency : kMinorBeatFrequency, kTickDuration * 44100.0, offset);
        }
    }
    
    // Render tones
    for ( int i=0; i<kMaxTones; i++ ) {
        if ( THIS->_tones[i].frequency != 0.0 ) {
            renderTone(&THIS->_tones[i], ioData, inNumberFrames);
        }
    }
    
    THIS->_lastRenderEnd = time->mHostTime + SESecondsToHostTicks(inNumberFrames / 44100.0);
}

static BOOL findBeatBoundary(double start, double end, double *outOffset, BOOL *outIsMajor) {
    if ( floor(start) != floor(end) || fmod(start, 1.0) < 1.0e-5 ) {
        // We straddle a boundary
        *outOffset = fmod(start, 1.0) < 1.0e-5 ? 0.0 : ceil(start) - start;
        *outIsMajor = fmod(ceil(start), 4.0) < 1.0e-5;
        return YES;
    } else {
        return NO;
    }
}

static void addTone(__unsafe_unretained DSMetronome * THIS, double frequency, UInt32 duration, UInt32 offset) {
    for ( int i=0; i<kMaxTones; i++ ) {
        if ( !THIS->_tones[i].frequency ) {
            THIS->_tones[i] = (DSMetronomeTone) {
                .frequency = frequency,
                .duration = duration,
                .remainingFrames = duration,
                .offset = offset,
                .position = 0
            };
        }
    }
}

static void renderTone(DSMetronomeTone * tone, AudioBufferList *ioData, UInt32 inNumberFrames) {
    float oscillatorRate = tone->frequency / 44100.0;
    int i = 0;
    for ( ; tone->offset > 0; i++, tone->offset-- );
    for ( ; tone->offset == 0 && i<inNumberFrames && tone->remainingFrames > 0; i++, tone->remainingFrames-- ) {
        float x = tone->position;
        x *= x; x -= 1.0; x *= x; x -= 0.5; x *= 0.4;
        tone->position += oscillatorRate;
        if ( tone->position > 1.0 ) tone->position -= 2.0;
        
        float gain = tone->remainingFrames >= tone->duration - kMicrofadeFrames
                        ? (float)(tone->duration - tone->remainingFrames) / (float)kMicrofadeFrames
                        : tone->remainingFrames <= kMicrofadeFrames
                            ? (float)tone->remainingFrames / (float)kMicrofadeFrames
                            : 1.0;
        
        ((float*)ioData->mBuffers[0].mData)[i] += x * gain;
        ((float*)ioData->mBuffers[1].mData)[i] += x * gain;
    }
    
    if ( !tone->remainingFrames ) {
        memset(tone, 0, sizeof(DSMetronomeTone));
    }
}

@end
