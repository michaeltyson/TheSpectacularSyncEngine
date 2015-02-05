//
//  SEMIDIClockReceiver.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIClockReceiver.h"
#import "SECommon.h"
#import <libkern/OSAtomic.h>

#ifdef DEBUG
// #define DEBUG_LOGGING
// #define DEBUG_ALL_MESSAGES
#endif

NSString * const SEMIDIClockReceiverDidStartTempoSyncNotification = @"SEMIDIClockReceiverDidStartTempoSyncNotification";
NSString * const SEMIDIClockReceiverDidStopTempoSyncNotification = @"SEMIDIClockReceiverDidStopTempoSyncNotification";
NSString * const SEMIDIClockReceiverDidStartNotification = @"SEMIDIClockReceiverDidStartNotification";
NSString * const SEMIDIClockReceiverDidStopNotification = @"SEMIDIClockReceiverDidStopNotification";
NSString * const SEMIDIClockReceiverDidLiveSeekNotification = @"SEMIDIClockReceiverDidLiveSeekNotification";
NSString * const SEMIDIClockReceiverDidChangeTempoNotification = @"SEMIDIClockReceiverDidChangeTempoNotification";

NSString * const SEMIDIClockReceiverTimestampKey = @"timestamp";
NSString * const SEMIDIClockReceiverTempoKey = @"tempo";

static const NSTimeInterval kIdlePollInterval        = 0.1;    // How often to poll on the main thread for events, while idle
static const NSTimeInterval kActivePollInterval      = 0.05;   // How often to poll on the main thread for events, while actively receiving
static const int kEventBufferSize                    = 10;     // Size of event buffer, used to notify main thread about events
static const int kSampleBufferSize                   = 96;     // Number of samples to keep at a time. A higher value runs the risk of a longer
                                                               // time to converge to new values; a lower value runs the risk of not converging to
                                                               // constant values.
static double kTempoChangeUpdateThreshold            = 1.0e-4; // Only issue tempo updates when change is greater than this
static const int kMinSamplesBeforeReportingTempo     = 15;     // Don't report tempo if we've seen less than this number of samples (unless clock running)
static const int kMinSamplesBetweenTempoUpdates      = 24;     // Don't issue a tempo update when within this number of samples of the last one
static const int kMinSamplesBeforeEvaluatingOutliers = 10;     // Min samples to observe before we can start identifying outlier samples
static const int kMinSamplesBeforeTrustingZeroStdDev = 3;      // Min samples to observe before we trust a zero standard deviation
static const double kOutlierThresholdRatio           = 3.5;    // Number of standard deviations beyond which we consider a sample an outlier
                                                               // A lower value lets us converge quickly to closer new values, but runs the risk of
                                                               // excluding useful samples in the presence of high jitter, causing convergence issues
static const NSTimeInterval kMinimumEarlyOutlierThreshold = 1.0e-3; // Minimum threshold beyond which we consider a sample an outlier, if we've seen less
                                                               // than kMinSamplesBeforeEvaluatingOutliers samples
static const int kOutliersBeforeReset                = 3;      // We need to see this many outliers before we reset to converge to the new value
static const int kMinSamplesBeforeStoringStandardDeviation = 24; // Min samples to observe before we can start storing standard deviation history
static const int kStandardDeviationHistorySamples    = 10;     // How many standard deviation history entries to keep
static const int kStandardDeviationHistoryEntryDuration = 24;  // How many samples each history item contains
static const double kTrustedStandardDeviation        = 1.0e-4; // Standard deviation beneath which we consider a source totally stable
static const int kMinSamplesBeforeRecordingTempoHistory = 13;  // Don't record tempo history if we've seen less than this number of (possibly unsteady) samples
static const int kTempoHistoryLength                 = 10;     // Number of historical 1-second tempo bounds samples to keep, for picking the optimal stable rounding
static const double kRoundingCoefficients[] = { 0.0001, 0.001, 0.01, 0.1, 0.5, 1.0 }; // Precisions to round to, depending on signal stability

typedef struct {
    uint64_t samples[kSampleBufferSize+1];
    int head;
    int tail;
    uint64_t accumulator;
    uint64_t standardDeviation;
    uint64_t mean;
    uint64_t outliers[kOutliersBeforeReset];
    int outlierCount;
    int seenSamples;
    int sampleCountSinceLastSignificantChange;
    BOOL significantChange;
    uint64_t standardDeviationHistory[kStandardDeviationHistorySamples];
} SESampleBuffer;

typedef enum {
    SEActionNone,
    SEActionStart,
    SEActionContinue,
    SEActionSeek
} SEAction;

typedef enum {
    SEEventTypeNone,
    SEEventTypeStart,
    SEEventTypeStop,
    SEEventTypeTempo,
    SEEventTypeSeek
} SEEventType;

typedef struct {
    SEEventType type;
    uint64_t timestamp;
} SEEvent;

@interface SEMIDIClockReceiver () {
    SEEvent _eventBuffer[kEventBufferSize];
    int _tickCount;
    uint64_t _lastTick;
    uint64_t _timeBase;
    uint64_t _lastTickReceiveTime;
    BOOL _clockRunning;
    BOOL _receivingTempo;
    SEAction _primedAction;
    uint64_t _primedActionTimestamp;
    int _savedSongPosition;
    int _sampleCountSinceLastTempoUpdate;
    SESampleBuffer _tickSampleBuffer;
    SESampleBuffer _timeBaseSampleBuffer;
    double _error;
    struct { double min; double max; } _tempoHistory[kTempoHistoryLength];
    int _lastTempoHistoryBucket;
}
@property (nonatomic) NSTimer * eventPollTimer;
@end

@implementation SEMIDIClockReceiver
@dynamic receivingTempo;
@dynamic clockRunning;

-(instancetype)init {
    if ( !(self = [super init]) ) return nil;
    
    SESampleBufferClear(&_tickSampleBuffer);
    SESampleBufferClear(&_timeBaseSampleBuffer);
    for ( int i=0; i<kTempoHistoryLength; i++ ) { _tempoHistory[i].max = 0.0; _tempoHistory[i].min = DBL_MAX; }
    self.eventPollTimer = [NSTimer scheduledTimerWithTimeInterval:kIdlePollInterval
                                                           target:[[SEWeakRetainingProxy alloc] initWithTarget:self]
                                                         selector:@selector(pollForEvents)
                                                         userInfo:nil
                                                          repeats:YES];
    
    return self;
}

-(void)dealloc {
    [_eventPollTimer invalidate];
}

void SEMIDIClockReceiverReceivePacketList(__unsafe_unretained SEMIDIClockReceiver * THIS, const MIDIPacketList * packetList) {
    const MIDIPacket *packet = &packetList->packet[0];
    for ( int index = 0; index < packetList->numPackets; index++, packet = MIDIPacketNext(packet) ) {

        MIDITimeStamp timestamp = packet->timeStamp;
        if ( !timestamp ) {
            timestamp = SECurrentTimeInHostTicks();
        }
        
        if ( packet->length == 0 ) {
            continue;
        }
        
#ifdef DEBUG_ALL_MESSAGES
        NSLog(@"%llu: %@",
              timestamp,
              packet->data[0] == SEMIDIMessageClockStart ? @"Start" :
              packet->data[0] == SEMIDIMessageClockStop ? @"Stop" :
              packet->data[0] == SEMIDIMessageContinue ? @"Continue" :
              packet->data[0] == SEMIDIMessageSongPosition ? @"Song Position" :
              packet->data[0] == SEMIDIMessageClock ? @"Clock" : @"Other message");
#endif
        
        switch ( packet->data[0] ) {
            case SEMIDIMessageClockStart:
            case SEMIDIMessageContinue: {
                if ( THIS->_timeBase || THIS->_primedAction == SEActionStart || THIS->_primedAction == SEActionContinue ) {
                    continue;
                }
                
                // Prepare to start/continue
                THIS->_primedAction = packet->data[0] == SEMIDIMessageClockStart ? SEActionStart : SEActionContinue;
                break;
            }
            case SEMIDIMessageClockStop: {
                if ( !THIS->_timeBase ) {
                    continue;
                }
                
                // Ensure ordering of memory updates, to avoid inconsistencies on other threads
                OSMemoryBarrier();
                
                // Stop
                THIS->_timeBase = 0;
                THIS->_tickCount = 0;
                THIS->_clockRunning = NO;
                
                SEMIDIClockReceiverPushEvent(THIS, SEEventTypeStop, timestamp);
                break;
            }
                
            case SEMIDIMessageSongPosition: {
                if ( packet->length < 3 ) {
                    continue;
                }
                
                // Record new song position
                THIS->_savedSongPosition = ((unsigned short)packet->data[2] << 7) | (unsigned short)packet->data[1];
                
                if ( THIS->_timeBase ) {
                    // Currently running; prepare to do a live seek
                    THIS->_primedAction = SEActionSeek;
                }
                break;
            }
                
            case SEMIDIMessageClock: {
                
                uint64_t previousTick = THIS->_lastTick;
                THIS->_lastTick = timestamp;
                THIS->_lastTickReceiveTime = SECurrentTimeInHostTicks();
                
                if ( !previousTick ) {
                    // No prior tick - don't do anything until the next one
                    if ( THIS->_primedAction ) {
                        // Remember the timestamp for a pending action
                        THIS->_primedActionTimestamp = timestamp;
                    }
                    break;
                }
                
                // Process any primed actions
                switch ( THIS->_primedAction ) {
                    case SEActionStart:
                    case SEActionContinue: {
                        if ( THIS->_primedAction == SEActionStart ) {
                            // Start from beginning of timeline
                            THIS->_savedSongPosition = 0;
                            THIS->_tickCount = 0;
                        } else {
                            // Continue from set song position
                            THIS->_tickCount = THIS->_savedSongPosition * SEMIDITicksPerSongPositionBeat;
                        }
                        THIS->_clockRunning = YES;
                        SESampleBufferClear(&THIS->_timeBaseSampleBuffer);
                        break;
                    }
                    case SEActionSeek: {
                        // Continue from set song position
                        THIS->_tickCount = THIS->_savedSongPosition * SEMIDITicksPerSongPositionBeat;
                        SESampleBufferClear(&THIS->_timeBaseSampleBuffer);
                        break;
                    }
                    case SEActionNone: {
                        if ( THIS->_clockRunning ) {
                            // No pending action; count ticks, in order to get timeline position
                            THIS->_tickCount++;
                            
                            // Remember last playback position
                            THIS->_savedSongPosition = THIS->_tickCount / SEMIDITicksPerSongPositionBeat;
                        }
                        break;
                    }
                }
                
                if ( THIS->_primedActionTimestamp ) {
                    // There's a prior tick we need to count
                    THIS->_tickCount++;
                }
                
                // Determine interval since last tick, and calculate corresponding tempo
                uint64_t interval = timestamp - previousTick;
                
                // Add to collected samples
                SESampleBufferIntegrateSample(&THIS->_tickSampleBuffer, interval);
                int samplesSinceChange = SESampleBufferSamplesSinceLastSignificantChange(&THIS->_tickSampleBuffer);
                
                // Determine source's relative standard deviation
                double relativeStandardDeviation = ((double)SESampleBufferStandardDeviation(&THIS->_tickSampleBuffer) / (double)interval) * 100.0;
                THIS->_error = relativeStandardDeviation;
                
                // Calculate true interval from samples, and convert to tempo
                interval = SESampleBufferCalculatedValue(&THIS->_tickSampleBuffer);
                double tempo = (double)SESecondsToHostTicks(60.0) / (double)(interval * SEMIDITicksPerBeat);
                
                // Update tempo history
                if ( SESampleBufferSignificantChangeHappened(&THIS->_tickSampleBuffer) ) {
                    // We just saw a significant change - clear the tempo history
                    for ( int i=0; i<kTempoHistoryLength; i++ ) { THIS->_tempoHistory[i].max = 0.0; THIS->_tempoHistory[i].min = DBL_MAX; }
                    
                } else if ( samplesSinceChange >= kMinSamplesBeforeRecordingTempoHistory ) {
                    // Add to history
                    uint64_t tempoHistoryBucketDuration = SESecondsToHostTicks(1.0);
                    int tempoHistoryBucket = (timestamp / tempoHistoryBucketDuration) % kTempoHistoryLength;
                    if ( tempoHistoryBucket != THIS->_lastTempoHistoryBucket ) {
                        // Clear this old bucket
                        THIS->_tempoHistory[tempoHistoryBucket].max = 0.0;
                        THIS->_tempoHistory[tempoHistoryBucket].min = DBL_MAX;
                        THIS->_lastTempoHistoryBucket = tempoHistoryBucket;
                    }
                    THIS->_tempoHistory[tempoHistoryBucket].max = MAX(tempo, THIS->_tempoHistory[tempoHistoryBucket].max);
                    THIS->_tempoHistory[tempoHistoryBucket].min = MIN(tempo, THIS->_tempoHistory[tempoHistoryBucket].min);
                }
                
                // Determine how much rounding to perform on tempo, to achieve a stable value
                int roundingCoefficient = 5;
                if ( relativeStandardDeviation <= kTrustedStandardDeviation
                        && SESampleBufferSamplesSeen(&THIS->_tickSampleBuffer) > kMinSamplesBeforeTrustingZeroStdDev ) {
                    
                    // We trust this source - just round to avoid minor floating-point errors
                    roundingCoefficient = 0;
                } else {
                    
                    // Untrusted source
                    if ( samplesSinceChange >= kMinSamplesBeforeReportingTempo ) {
                        // Only check history if we've got enough samples
                        roundingCoefficient = 0;
                        for ( ; roundingCoefficient < (sizeof(kRoundingCoefficients)/sizeof(double))-1; roundingCoefficient++ ) {
                            // For each rounding coefficient (starting small), compare the rounded tempo entries with each other.
                            // If, for a given rounding coefficient, the rounded tempo entries all match, then we'll round using this coefficient.
                            BOOL acceptableRounding = YES;
                            double comparisonValue = 0.0;
                            for ( int i=0; i<kTempoHistoryLength; i++ ) {
                                if ( THIS->_tempoHistory[i].max == 0.0 ) continue;
                                
                                if ( comparisonValue == 0.0 ) {
                                    // Use the first value we come to for comparison
                                    comparisonValue = round(THIS->_tempoHistory[i].max / kRoundingCoefficients[roundingCoefficient]) * kRoundingCoefficients[roundingCoefficient];
                                }
                                
                                // Compare the value bounds for this entry against our comparison value
                                double roundedMaxValue = round(THIS->_tempoHistory[i].max / kRoundingCoefficients[roundingCoefficient]) * kRoundingCoefficients[roundingCoefficient];
                                double roundedMinValue = round(THIS->_tempoHistory[i].min / kRoundingCoefficients[roundingCoefficient]) * kRoundingCoefficients[roundingCoefficient];
                                
                                if ( fabs(roundedMaxValue - comparisonValue) > 1.0e-5 || fabs(roundedMinValue - comparisonValue) > 1.0e-5 ) {
                                    // This rounding coefficient doesn't give us a stable result - move on
                                    acceptableRounding = NO;
                                    break;
                                }
                            }
                            
                            if ( acceptableRounding ) {
                                break;
                            }
                        }
                        
                    }
                }
                
                // Apply rounding
                tempo = round(tempo / kRoundingCoefficients[roundingCoefficient]) * kRoundingCoefficients[roundingCoefficient];
                
                THIS->_sampleCountSinceLastTempoUpdate++;
                
                if ( !THIS->_tempo || (fabs(THIS->_tempo - tempo) >= kTempoChangeUpdateThreshold) ) {
                    // A significant tempo change happened. Report it (with rate limiting)
                    BOOL reportUpdate = NO;
                    
                    if ( relativeStandardDeviation <= kTrustedStandardDeviation
                            && SESampleBufferSamplesSeen(&THIS->_tickSampleBuffer) > kMinSamplesBeforeTrustingZeroStdDev ) {
                        // Trust the source - it's very accurate - so report any change immediately
                        reportUpdate = YES;
                        
                    } else if ( (!THIS->_tempo && THIS->_clockRunning) || samplesSinceChange == kMinSamplesBeforeReportingTempo ) {
                        // Report when tempo is needed but absent, or shortly after we've seen a significant change
                        reportUpdate = YES;
                        
                    } else if ( THIS->_sampleCountSinceLastTempoUpdate > kMinSamplesBetweenTempoUpdates && samplesSinceChange >= kMinSamplesBeforeReportingTempo ) {
                        // Report every so often
                        reportUpdate = YES;
                    }
                    
                    if ( reportUpdate ) {
#ifdef DEBUG_LOGGING
                        NSLog(@"Tempo is now %lf (was %lf)", tempo, THIS->_tempo);
#endif
                        
                        THIS->_tempo = tempo;
                        THIS->_sampleCountSinceLastTempoUpdate = 0;
                        
                        SEMIDIClockReceiverPushEvent(THIS, SEEventTypeTempo, timestamp);
                    }
                }
                
                if ( THIS->_clockRunning && THIS->_tempo ) {
                    // Calculate new timebase
                    uint64_t timeBase = timestamp - SEBeatsToHostTicks((double)THIS->_tickCount / (double)SEMIDITicksPerBeat, THIS->_tempo);
                    
                    // Add to collected samples
                    SESampleBufferIntegrateSample(&THIS->_timeBaseSampleBuffer, timeBase);
                    
                    // Calculate true time base from samples
                    THIS->_timeBase = SESampleBufferCalculatedValue(&THIS->_timeBaseSampleBuffer);
                }
                
                if ( THIS->_primedAction ) {
                    // Finalise primed actions
                    uint64_t actionTimestamp = THIS->_primedActionTimestamp ? THIS->_primedActionTimestamp : timestamp;
                    switch ( THIS->_primedAction ) {
                        case SEActionStart:
                        case SEActionContinue: {
                            SEMIDIClockReceiverPushEvent(THIS, SEEventTypeStart, actionTimestamp);
                            break;
                        }
                        case SEActionSeek: {
                            SEMIDIClockReceiverPushEvent(THIS, SEEventTypeSeek, actionTimestamp);
                            break;
                        }
                        default: {
                            break;
                        }
                    }
                    
                    THIS->_primedAction = SEActionNone;
                    THIS->_primedActionTimestamp = 0;
                }
                
                break;
            }
        }
    }
}

-(void)reset {
    [self willChangeValueForKey:@"receivingTempo"];
    _lastTick = 0;
    _lastTickReceiveTime = 0;
    _tickCount = 0;
    _receivingTempo = NO;
    _savedSongPosition = 0;
    _sampleCountSinceLastTempoUpdate = 0;
    SESampleBufferClear(&_tickSampleBuffer);
    SESampleBufferClear(&_timeBaseSampleBuffer);
    for ( int i=0; i<kTempoHistoryLength; i++ ) { _tempoHistory[i].max = 0.0; _tempoHistory[i].min = DBL_MAX; }
    [self didChangeValueForKey:@"receivingTempo"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStopTempoSyncNotification
                                                        object:self
                                                      userInfo:@{ SEMIDIClockReceiverTimestampKey: @(SECurrentTimeInHostTicks()) }];
    
    if ( _timeBase ) {
        [self willChangeValueForKey:@"clockRunning"];
        _timeBase = 0;
        _clockRunning = NO;
        [self didChangeValueForKey:@"clockRunning"];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStopNotification
                                                            object:self
                                                          userInfo:@{ SEMIDIClockReceiverTimestampKey: @(SECurrentTimeInHostTicks()) }];
    }
}

BOOL SEMIDIClockReceiverIsReceivingTempo(__unsafe_unretained SEMIDIClockReceiver * receiver) {
    return receiver->_lastTickReceiveTime && receiver->_lastTickReceiveTime >= SECurrentTimeInHostTicks() - SESecondsToHostTicks(0.5);
}

BOOL SEMIDIClockReceiverIsClockRunning(__unsafe_unretained SEMIDIClockReceiver * receiver) {
    return receiver->_timeBase;
}

double SEMIDIClockReceiverGetTimelinePosition(__unsafe_unretained SEMIDIClockReceiver * receiver, uint64_t time) {
    if ( !time ) {
        time = SECurrentTimeInHostTicks();
    }
    uint64_t timeBase = receiver->_timeBase;
    double tempo = receiver->_tempo;
    double savedSongPosition = receiver->_savedSongPosition;

    double position;
    if ( !timeBase || !tempo ) {
        position = (double)savedSongPosition * ((double)SEMIDITicksPerSongPositionBeat / (double)SEMIDITicksPerBeat);
    } else {
        position = time > timeBase ? SEHostTicksToBeats(time - timeBase, tempo) : 0;
    }
    
    return position;
}

double SEMIDIClockReceiverGetTempo(__unsafe_unretained SEMIDIClockReceiver * receiver) {
    return receiver->_tempo;
}

-(double)timelinePositionForTime:(uint64_t)time {
    return SEMIDIClockReceiverGetTimelinePosition(self, time);
}

-(BOOL)receivingTempo {
    return SEMIDIClockReceiverIsReceivingTempo(self);
}

-(BOOL)clockRunning {
    return SEMIDIClockReceiverIsClockRunning(self);
}


static void SEMIDIClockReceiverPushEvent(__unsafe_unretained SEMIDIClockReceiver * THIS, SEEventType type, uint64_t timestamp) {
    for ( int i=0; i<kEventBufferSize; i++ ) {
        if ( THIS->_eventBuffer[i].type == SEEventTypeNone ) {
            THIS->_eventBuffer[i].timestamp = timestamp;
            OSMemoryBarrier();
            THIS->_eventBuffer[i].type = type;
            break;
        }
    }
}

-(void)pollForEvents {
    for ( int i=0; i<kEventBufferSize; i++ ) {
        if ( _eventBuffer[i].type == SEEventTypeNone ) {
            continue;
        }
        
        switch ( _eventBuffer[i].type ) {
            case SEEventTypeStop:
                if ( fabs(_eventPollTimer.timeInterval - kIdlePollInterval) > DBL_EPSILON ) {
                    [_eventPollTimer invalidate];
                    self.eventPollTimer = [NSTimer scheduledTimerWithTimeInterval:kIdlePollInterval
                                                                           target:[[SEWeakRetainingProxy alloc] initWithTarget:self]
                                                                         selector:@selector(pollForEvents)
                                                                         userInfo:nil
                                                                          repeats:YES];
                }
                [self willChangeValueForKey:@"clockRunning"];
                [self didChangeValueForKey:@"clockRunning"];
                [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStopNotification
                                                                    object:self
                                                                  userInfo:@{ SEMIDIClockReceiverTimestampKey: @(_eventBuffer[i].timestamp) }];
                break;
            case SEEventTypeTempo:
                if ( !_receivingTempo ) {
                    if ( fabs(_eventPollTimer.timeInterval - kActivePollInterval) > DBL_EPSILON ) {
                        [_eventPollTimer invalidate];
                        self.eventPollTimer = [NSTimer scheduledTimerWithTimeInterval:kActivePollInterval
                                                                               target:[[SEWeakRetainingProxy alloc] initWithTarget:self]
                                                                             selector:@selector(pollForEvents)
                                                                             userInfo:nil
                                                                              repeats:YES];
                    }
                    
                    [self willChangeValueForKey:@"receivingTempo"];
                    _receivingTempo = YES;
                    [self didChangeValueForKey:@"receivingTempo"];
                    [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStartTempoSyncNotification
                                                                        object:self
                                                                      userInfo:@{ SEMIDIClockReceiverTempoKey: @(_tempo),
                                                                                  SEMIDIClockReceiverTimestampKey: @(_eventBuffer[i].timestamp) }];
                }
                [self willChangeValueForKey:@"tempo"];
                [self didChangeValueForKey:@"tempo"];
                [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidChangeTempoNotification
                                                                    object:self
                                                                  userInfo:@{ SEMIDIClockReceiverTempoKey: @(_tempo),
                                                                              SEMIDIClockReceiverTimestampKey: @(_eventBuffer[i].timestamp) }];
                break;
                
            case SEEventTypeStart:
                [self willChangeValueForKey:@"clockRunning"];
                [self didChangeValueForKey:@"clockRunning"];
                
                [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStartNotification
                                                                    object:self
                                                                  userInfo:@{ SEMIDIClockReceiverTimestampKey: @(_eventBuffer[i].timestamp) }];
                break;
                
            case SEEventTypeSeek:
                [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidLiveSeekNotification
                                                                    object:self
                                                                  userInfo:@{ SEMIDIClockReceiverTimestampKey: @(_eventBuffer[i].timestamp) }];
                break;
                
            default:
                break;
        }
        
        _eventBuffer[i].type = SEEventTypeNone;
    }
    
    if ( _lastTickReceiveTime && _lastTickReceiveTime < SECurrentTimeInHostTicks() - SESecondsToHostTicks(0.5) ) {
        
        // Timed out
        if ( fabs(_eventPollTimer.timeInterval - kIdlePollInterval) > DBL_EPSILON ) {
            [_eventPollTimer invalidate];
            self.eventPollTimer = [NSTimer scheduledTimerWithTimeInterval:kIdlePollInterval
                                                                   target:[[SEWeakRetainingProxy alloc] initWithTarget:self]
                                                                 selector:@selector(pollForEvents)
                                                                 userInfo:nil
                                                                  repeats:YES];
        }
        
        [self willChangeValueForKey:@"receivingTempo"];
        _tickCount = 0;
        _lastTick = 0;
        _lastTickReceiveTime = 0;
        _receivingTempo = NO;
        _sampleCountSinceLastTempoUpdate = 0;
        SESampleBufferClear(&_tickSampleBuffer);
        SESampleBufferClear(&_timeBaseSampleBuffer);
        for ( int i=0; i<kTempoHistoryLength; i++ ) { _tempoHistory[i].max = 0.0; _tempoHistory[i].min = DBL_MAX; }
        [self didChangeValueForKey:@"receivingTempo"];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStopTempoSyncNotification
                                                            object:self
                                                          userInfo:@{ SEMIDIClockReceiverTimestampKey: @(SECurrentTimeInHostTicks()) }];
        
        if ( _timeBase ) {
            [self willChangeValueForKey:@"clockRunning"];
            _timeBase = 0;
            _clockRunning = NO;
            [self didChangeValueForKey:@"clockRunning"];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStopNotification
                                                                object:self
                                                              userInfo:@{ SEMIDIClockReceiverTimestampKey: @(SECurrentTimeInHostTicks()) }];
        }
    }
}

#pragma mark - Ring buffer utilities

static void SESampleBufferIntegrateSample(SESampleBuffer *buffer, uint64_t sample) {
    
    // First determine if sample is an outlier. We identify outliers for two purposes: to allow for adjustments in
    // timeline position independent of tempo change (which necessitate one tick with a correction interval that appears
    // as an outlier), and to identify consecutive outliers which represent a new value, so we can converge faster upon that.
    
    BOOL outlier = NO;
    if ( SESampleBufferFillCount(buffer) < kMinSamplesBeforeEvaluatingOutliers ) {
        
        // Not enough samples seen yet
        outlier = NO;
        
    } else {
        
        // It's an outlier if it's outside our threshold past the observed average
        uint64_t outlierThreshold = kOutlierThresholdRatio * buffer->standardDeviation;
        if ( buffer->seenSamples < kMinSamplesBeforeEvaluatingOutliers && outlierThreshold < SESecondsToHostTicks(kMinimumEarlyOutlierThreshold) ) {
            outlierThreshold = SESecondsToHostTicks(kMinimumEarlyOutlierThreshold);
        }
        outlier = sample > buffer->mean + outlierThreshold
                    || sample < (buffer->mean < outlierThreshold ? 0 : buffer->mean - outlierThreshold);
        
        // Make sure other outliers we've seen lie on the same side of the current range
        if ( outlier && buffer->outlierCount > 0 ) {
            BOOL greaterThanRange = sample > buffer->mean + outlierThreshold;
            for ( int i=0; i<buffer->outlierCount; i++ ) {
                if ( greaterThanRange == (buffer->outliers[i] < buffer->mean + outlierThreshold) ) {
                    // This outlier is on the other side of the range, which means we're not looking at
                    // outliers representing a new value, but outlying normal samples. We can safely integrate
                    // these now, as given that there's more than one, it also doesn't represent a timeline
                    // adjustment.
                    outlier = NO;
                    for ( int i=0; i<buffer->outlierCount; i++ ) {
                        _SESampleBufferAddSampleToBuffer(buffer, buffer->outliers[i]);
                    }
                    buffer->outlierCount = 0;
                }
            }
        }
    }
    
    if ( outlier ) {
        // Handle outliers
        buffer->outliers[buffer->outlierCount++] = sample;
        
        if ( buffer->outlierCount == kOutliersBeforeReset ) {
            // Reset our sample buffer
            buffer->head = buffer->tail = 0;
            buffer->accumulator = 0;
            buffer->standardDeviation = 0;
            buffer->sampleCountSinceLastSignificantChange = 0;
            buffer->significantChange = YES;
            
            // Add the outliers
            for ( int i=0; i<buffer->outlierCount; i++ ) {
                _SESampleBufferAddSampleToBuffer(buffer, buffer->outliers[i]);
            }
            
            buffer->outlierCount = 0;
        } else {
            // Ignore outlier for now
        }
    } else {
        // Not an outlier: integrate this sample
        _SESampleBufferAddSampleToBuffer(buffer, sample);
        
        if ( buffer->outlierCount != 0 ) {
            // Ignore any outliers we saw
            buffer->outlierCount = 0;
        }
    }
    
#ifdef DEBUG_LOGGING
    // Diagnosis logging
    if ( sample < 1e9 ) {
        // Tick interval
        NSLog(@"%@%llu (%0.3lf BPM), avg %llu (%0.3lf BPM), stddev %llu (%0.2lf%%)",
              outlier ? @"outlier " : @"",
              sample,
              SESecondsToHostTicks(60.0) / ((double)sample * SEMIDITicksPerBeat),
              buffer->mean,
              SESecondsToHostTicks(60.0) / ((double)buffer->mean * SEMIDITicksPerBeat),
              buffer->standardDeviation,
              ((double)buffer->standardDeviation / (double)buffer->mean) * 100.0);
    } else {
        // Absolute timestamp
        NSLog(@"%@%llu (%lfs), avg %llu (%lfs), stddev %llu (%lfs, %0.2lf%%)",
              outlier ? @"outlier " : @"",
              sample,
              SEHostTicksToSeconds(sample),
              buffer->mean,
              SEHostTicksToSeconds(buffer->mean),
              buffer->standardDeviation,
              SEHostTicksToSeconds(buffer->standardDeviation),
              ((double)buffer->standardDeviation / (double)buffer->mean) * 0.5 * 100.0);
    }
#endif

}

static uint64_t SESampleBufferCalculatedValue(SESampleBuffer *buffer) {
    return buffer->mean;
}

static uint64_t SESampleBufferStandardDeviation(SESampleBuffer *buffer) {
    if ( buffer->seenSamples <= kMinSamplesBeforeStoringStandardDeviation ) {
        return buffer->standardDeviation;
    }
    uint64_t max = 0;
    for ( int i=0; i<kStandardDeviationHistorySamples; i++ ) {
        max = MAX(max, buffer->standardDeviationHistory[i]);
    }
    return max;
}

static int SESampleBufferSamplesSeen(SESampleBuffer *buffer) {
    return buffer->seenSamples;
}

static int SESampleBufferSamplesSinceLastSignificantChange(SESampleBuffer *buffer) {
    return buffer->sampleCountSinceLastSignificantChange;
}

static BOOL SESampleBufferSignificantChangeHappened(SESampleBuffer *buffer) {
    BOOL significantChange = buffer->significantChange;
    buffer->significantChange = NO;
    return significantChange;
}

static void SESampleBufferClear(SESampleBuffer *buffer) {
    memset(buffer, 0, sizeof(SESampleBuffer));
}

static int SESampleBufferFillCount(SESampleBuffer *buffer) {
    return buffer->head >= buffer->tail
        ? buffer->head - buffer->tail
        : (buffer->head + kSampleBufferSize) - buffer->tail;
}

static void _SESampleBufferAddSampleToBuffer(SESampleBuffer *buffer, uint64_t sample) {
    if ( (buffer->head + 1) % kSampleBufferSize == buffer->tail ) {
        // Buffer is full, slide along: factor out last sample
        buffer->accumulator -= buffer->samples[buffer->tail];
        
        // Move up tail
        buffer->tail = (buffer->tail + 1) % kSampleBufferSize;
    }
    
    // Add new sample, move up head
    buffer->samples[buffer->head] = sample;
    buffer->head = (buffer->head + 1) % kSampleBufferSize;
    buffer->sampleCountSinceLastSignificantChange++;
    buffer->seenSamples++;
    
    // Integrate new value
    buffer->accumulator += sample;
    
    // Calculate new mean
    buffer->mean = buffer->accumulator / SESampleBufferFillCount(buffer);
    
    // Calculate new standard deviation
    uint64_t sum = 0;
    for ( int i=buffer->tail; i != buffer->head; i = (i+1) % kSampleBufferSize ) {
        uint64_t absDifference = buffer->samples[i] > buffer->mean ? buffer->samples[i] - buffer->mean : buffer->mean - buffer->samples[i];
        sum += absDifference*absDifference;
    }
    buffer->standardDeviation = sqrt((double)sum / (double)SESampleBufferFillCount(buffer));
    
    if ( buffer->sampleCountSinceLastSignificantChange > kMinSamplesBeforeStoringStandardDeviation ) {
        int standardDeviationHistoryBucket = (buffer->sampleCountSinceLastSignificantChange / kStandardDeviationHistoryEntryDuration) % kStandardDeviationHistorySamples;
        if ( buffer->sampleCountSinceLastSignificantChange % kStandardDeviationHistoryEntryDuration == 0 ) {
            buffer->standardDeviationHistory[standardDeviationHistoryBucket] = 0;
        }
        buffer->standardDeviationHistory[standardDeviationHistoryBucket] = MAX(buffer->standardDeviationHistory[standardDeviationHistoryBucket], buffer->standardDeviation);
    }
}

@end
