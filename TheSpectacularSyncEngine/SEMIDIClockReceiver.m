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
#endif

NSString * const SEMIDIClockReceiverDidStartTempoSyncNotification = @"SEMIDIClockReceiverDidStartTempoSyncNotification";
NSString * const SEMIDIClockReceiverDidStopTempoSyncNotification = @"SEMIDIClockReceiverDidStopTempoSyncNotification";
NSString * const SEMIDIClockReceiverDidStartNotification = @"SEMIDIClockReceiverDidStartNotification";
NSString * const SEMIDIClockReceiverDidStopNotification = @"SEMIDIClockReceiverDidStopNotification";
NSString * const SEMIDIClockReceiverDidLiveSeekNotification = @"SEMIDIClockReceiverDidLiveSeekNotification";
NSString * const SEMIDIClockReceiverDidChangeTempoNotification = @"SEMIDIClockReceiverDidChangeTempoNotification";

NSString * const SEMIDIClockReceiverTimestampKey = @"timestamp";
NSString * const SEMIDIClockReceiverTempoKey = @"tempo";

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
static const NSTimeInterval kMinimumOutlierThreshold = 1.0e-3; // Minimum threshold beyond which we consider a sample an outlier
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
} SEMIDIClockReceiverSampleBuffer;

typedef enum {
    SEMIDIClockReceiverActionNone,
    SEMIDIClockReceiverActionStart,
    SEMIDIClockReceiverActionContinue,
    SEMIDIClockReceiverActionSeek
} SEMIDIClockReceiverAction;

@interface SEMIDIClockReceiver () {
    int _tickCount;
    uint64_t _lastTick;
    uint64_t _timeBase;
    uint64_t _lastTickReceiveTime;
    BOOL _clockRunning;
    BOOL _receivingTempo;
    SEMIDIClockReceiverAction _primedAction;
    uint64_t _primedActionTimestamp;
    int _savedSongPosition;
    int _sampleCountSinceLastTempoUpdate;
    SEMIDIClockReceiverSampleBuffer _tickSampleBuffer;
    SEMIDIClockReceiverSampleBuffer _timeBaseSampleBuffer;
    double _error;
    struct { double min; double max; } _tempoHistory[kTempoHistoryLength];
    int _lastTempoHistoryBucket;
}
@property (nonatomic) NSTimer * timeout;
@end

@implementation SEMIDIClockReceiver
@dynamic receivingTempo;
@dynamic clockRunning;

-(instancetype)init {
    if ( !(self = [super init]) ) return nil;
    
    SEMIDIClockReceiverSampleBufferClear(&_tickSampleBuffer);
    SEMIDIClockReceiverSampleBufferClear(&_timeBaseSampleBuffer);
    for ( int i=0; i<kTempoHistoryLength; i++ ) { _tempoHistory[i].max = 0.0; _tempoHistory[i].min = DBL_MAX; }
    
    return self;
}

-(void)dealloc {
    if ( _timeout ) {
        [_timeout invalidate];
    }
}

-(void)receivePacketList:(const MIDIPacketList *)packetList {
    const MIDIPacket *packet = &packetList->packet[0];
    for ( int index = 0; index < packetList->numPackets; index++, packet = MIDIPacketNext(packet) ) {

        MIDITimeStamp timestamp = packet->timeStamp;
        if ( !timestamp ) {
            timestamp = SECurrentTimeInHostTicks();
        }
        
        if ( packet->length == 0 ) {
            continue;
        }
        
        switch ( packet->data[0] ) {
            case SEMIDIMessageClockStart:
            case SEMIDIMessageContinue: {
                if ( _timeBase || _primedAction == SEMIDIClockReceiverActionStart || _primedAction == SEMIDIClockReceiverActionContinue ) {
                    continue;
                }
                
                // Prepare to start/continue
                _primedAction = packet->data[0] == SEMIDIMessageClockStart ? SEMIDIClockReceiverActionStart : SEMIDIClockReceiverActionContinue;
                break;
            }
            case SEMIDIMessageClockStop: {
                if ( !_timeBase ) {
                    continue;
                }
                
                // Ensure ordering of memory updates, to avoid inconsistencies on other threads
                OSMemoryBarrier();
                
                // Stop
                _timeBase = 0;
                _tickCount = 0;
                _clockRunning = NO;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ( _timeout ) {
                        [_timeout invalidate];
                        self.timeout = nil;
                    }
                    [self willChangeValueForKey:@"clockRunning"];
                    [self didChangeValueForKey:@"clockRunning"];
                    [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStopNotification
                                                                        object:self
                                                                      userInfo:@{ SEMIDIClockReceiverTimestampKey: @(timestamp) }];
                });
                break;
            }
                
            case SEMIDIMessageSongPosition: {
                if ( packet->length < 3 ) {
                    continue;
                }
                
                // Record new song position
                _savedSongPosition = ((unsigned short)packet->data[2] << 7) | (unsigned short)packet->data[1];
                
                if ( _timeBase ) {
                    // Currently running; prepare to do a live seek
                    _primedAction = SEMIDIClockReceiverActionSeek;
                }
                break;
            }
                
            case SEMIDIMessageClock: {
                
                // Process any primed actions
                switch ( _primedAction ) {
                    case SEMIDIClockReceiverActionStart:
                    case SEMIDIClockReceiverActionContinue: {
                        if ( _primedAction == SEMIDIClockReceiverActionStart ) {
                            // Start from beginning of timeline
                            _savedSongPosition = 0;
                            _tickCount = 0;
                        } else {
                            // Continue from set song position
                            _tickCount = _savedSongPosition * SEMIDITicksPerSongPositionBeat;
                        }
                        _clockRunning = YES;
                        SEMIDIClockReceiverSampleBufferClear(&_timeBaseSampleBuffer);
                        break;
                    }
                    case SEMIDIClockReceiverActionSeek: {
                        // Continue from set song position
                        _tickCount = _savedSongPosition * SEMIDITicksPerSongPositionBeat;
                        SEMIDIClockReceiverSampleBufferClear(&_timeBaseSampleBuffer);
                        break;
                    }
                    case SEMIDIClockReceiverActionNone: {
                        if ( _clockRunning ) {
                            // No pending action; count ticks, in order to get timeline position
                            _tickCount++;
                            
                            // Remember last playback position
                            _savedSongPosition = _tickCount / SEMIDITicksPerSongPositionBeat;
                        }
                        break;
                    }
                }
                
                uint64_t previousTick = _lastTick;
                _lastTick = timestamp;
                _lastTickReceiveTime = SECurrentTimeInHostTicks();
                
                if ( previousTick ) {
                    
                    // Determine interval since last tick, and calculate corresponding tempo
                    uint64_t interval = timestamp - previousTick;
                    
                    // Add to collected samples
                    SEMIDIClockReceiverSampleBufferIntegrateSample(&_tickSampleBuffer, interval);
                    int samplesSinceChange = SEMIDIClockReceiverSampleBufferSamplesSinceLastSignificantChange(&_tickSampleBuffer);
                    
                    // Determine source's relative standard deviation
                    double relativeStandardDeviation = ((double)SEMIDIClockReceiverSampleBufferStandardDeviation(&_tickSampleBuffer) / (double)interval) * 100.0;
                    _error = relativeStandardDeviation;
                    
                    // Calculate true interval from samples, and convert to tempo
                    interval = SEMIDIClockReceiverSampleBufferCalculatedValue(&_tickSampleBuffer);
                    double tempo = (double)SESecondsToHostTicks(60.0) / (double)(interval * SEMIDITicksPerBeat);
                    
                    // Update tempo history
                    if ( SEMIDIClockReceiverSampleBufferSignificantChangeHappened(&_tickSampleBuffer) ) {
                        // We just saw a significant change - clear the tempo history
                        for ( int i=0; i<kTempoHistoryLength; i++ ) { _tempoHistory[i].max = 0.0; _tempoHistory[i].min = DBL_MAX; }
                        
                    } else if ( samplesSinceChange >= kMinSamplesBeforeRecordingTempoHistory ) {
                        // Add to history
                        uint64_t tempoHistoryBucketDuration = SESecondsToHostTicks(1.0);
                        int tempoHistoryBucket = (timestamp / tempoHistoryBucketDuration) % kTempoHistoryLength;
                        if ( tempoHistoryBucket != _lastTempoHistoryBucket ) {
                            // Clear this old bucket
                            _tempoHistory[tempoHistoryBucket].max = 0.0;
                            _tempoHistory[tempoHistoryBucket].min = DBL_MAX;
                            _lastTempoHistoryBucket = tempoHistoryBucket;
                        }
                        _tempoHistory[tempoHistoryBucket].max = MAX(tempo, _tempoHistory[tempoHistoryBucket].max);
                        _tempoHistory[tempoHistoryBucket].min = MIN(tempo, _tempoHistory[tempoHistoryBucket].min);
                    }
                    
                    // Determine how much rounding to perform on tempo, to achieve a stable value
                    int roundingCoefficient = 5;
                    if ( relativeStandardDeviation <= kTrustedStandardDeviation
                            && SEMIDIClockReceiverSampleBufferSamplesSeen(&_tickSampleBuffer) > kMinSamplesBeforeTrustingZeroStdDev ) {
                        
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
                                    if ( _tempoHistory[i].max == 0.0 ) continue;
                                    
                                    if ( comparisonValue == 0.0 ) {
                                        // Use the first value we come to for comparison
                                        comparisonValue = round(_tempoHistory[i].max / kRoundingCoefficients[roundingCoefficient]) * kRoundingCoefficients[roundingCoefficient];
                                    }
                                    
                                    // Compare the value bounds for this entry against our comparison value
                                    double roundedMaxValue = round(_tempoHistory[i].max / kRoundingCoefficients[roundingCoefficient]) * kRoundingCoefficients[roundingCoefficient];
                                    double roundedMinValue = round(_tempoHistory[i].min / kRoundingCoefficients[roundingCoefficient]) * kRoundingCoefficients[roundingCoefficient];
                                    
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
                    
                    _sampleCountSinceLastTempoUpdate++;
                    
                    if ( !_receivingTempo || !_tempo || (fabs(_tempo - tempo) >= kTempoChangeUpdateThreshold) ) {
                        // A significant tempo change happened. Report it (with rate limiting)
                        BOOL reportUpdate = NO;
                        
                        if ( relativeStandardDeviation <= kTrustedStandardDeviation
                                && SEMIDIClockReceiverSampleBufferSamplesSeen(&_tickSampleBuffer) > kMinSamplesBeforeTrustingZeroStdDev ) {
                            // Trust the source - it's very accurate - so report any change immediately
                            reportUpdate = YES;
                            
                        } else if ( (!_tempo && _clockRunning) || samplesSinceChange == kMinSamplesBeforeReportingTempo ) {
                            // Report when tempo is needed but absent, or shortly after we've seen a significant change
                            reportUpdate = YES;
                            
                        } else if ( _sampleCountSinceLastTempoUpdate > kMinSamplesBetweenTempoUpdates && samplesSinceChange >= kMinSamplesBeforeReportingTempo ) {
                            // Report every so often
                            reportUpdate = YES;
                        }
                        
                        if ( reportUpdate ) {
                            #ifdef DEBUG_LOGGING
                            NSLog(@"Tempo is now %lf (was %lf)", tempo, _tempo);
                            #endif
                            
                            _tempo = tempo;
                            _sampleCountSinceLastTempoUpdate = 0;
                            BOOL firstSample = !_receivingTempo;
                            _receivingTempo = YES;
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if ( firstSample ) {
                                    [self willChangeValueForKey:@"receivingTempo"];
                                    [self didChangeValueForKey:@"receivingTempo"];
                                    [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStartTempoSyncNotification
                                                                                        object:self
                                                                                      userInfo:@{ SEMIDIClockReceiverTempoKey: @(tempo),
                                                                                                  SEMIDIClockReceiverTimestampKey: @(timestamp) }];
                                }
                                [self willChangeValueForKey:@"tempo"];
                                [self didChangeValueForKey:@"tempo"];
                                [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidChangeTempoNotification
                                                                                    object:self
                                                                                  userInfo:@{ SEMIDIClockReceiverTempoKey: @(tempo),
                                                                                              SEMIDIClockReceiverTimestampKey: @(timestamp) }];
                            });
                        }
                    }
                }
                
                if ( _clockRunning && _tempo ) {
                    // Calculate new timebase
                    uint64_t timeBase = timestamp - SEBeatsToHostTicks((double)_tickCount / (double)SEMIDITicksPerBeat, _tempo);
                    
                    // Add to collected samples
                    SEMIDIClockReceiverSampleBufferIntegrateSample(&_timeBaseSampleBuffer, timeBase);
                    
                    // Calculate true time base from samples
                    _timeBase = SEMIDIClockReceiverSampleBufferCalculatedValue(&_timeBaseSampleBuffer);
                }
                
                if ( _primedAction ) {
                    // Finalise primed actions (as long as we've seen at least one tick interval)
                    if ( !previousTick ) {
                        // No tick interval seen - we'll process this action next tick, so remember the associated timestamp
                        _primedActionTimestamp = timestamp;
                    } else {
                        uint64_t actionTimestamp = _primedActionTimestamp ? _primedActionTimestamp : timestamp;
                        switch ( _primedAction ) {
                            case SEMIDIClockReceiverActionStart:
                            case SEMIDIClockReceiverActionContinue: {
                                
                                // Perform notifications
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [self willChangeValueForKey:@"clockRunning"];
                                    [self didChangeValueForKey:@"clockRunning"];
                                    
                                    [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidStartNotification
                                                                                        object:self
                                                                                      userInfo:@{ SEMIDIClockReceiverTimestampKey: @(actionTimestamp) }];
                                });
                                break;
                            }
                            case SEMIDIClockReceiverActionSeek: {
                                
                                // Perform notifications
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [[NSNotificationCenter defaultCenter] postNotificationName:SEMIDIClockReceiverDidLiveSeekNotification
                                                                                        object:self
                                                                                      userInfo:@{ SEMIDIClockReceiverTimestampKey: @(actionTimestamp) }];
                                });
                                
                                break;
                            }
                            default: {
                                break;
                            }
                        }
                        
                        _primedAction = SEMIDIClockReceiverActionNone;
                        _primedActionTimestamp = 0;
                    }
                }
                
                if ( !_timeout ) {
                    // Start timeout, used to report when we stop getting ticks
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ( !_timeout ) {
                            self.timeout = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                            target:[[SEWeakRetainingProxy alloc] initWithTarget:self]
                                                                          selector:@selector(checkTimeout:)
                                                                          userInfo:nil
                                                                           repeats:YES];
                        }
                    });
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
    SEMIDIClockReceiverSampleBufferClear(&_tickSampleBuffer);
    SEMIDIClockReceiverSampleBufferClear(&_timeBaseSampleBuffer);
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

-(void)checkTimeout:(NSTimer*)timer {
    if ( _lastTickReceiveTime && _lastTickReceiveTime < SECurrentTimeInHostTicks() - SESecondsToHostTicks(0.5) ) {
        
        // Timed out
        [_timeout invalidate];
        self.timeout = nil;
        
        [self willChangeValueForKey:@"receivingTempo"];
        _tickCount = 0;
        _lastTick = 0;
        _lastTickReceiveTime = 0;
        _receivingTempo = NO;
        _sampleCountSinceLastTempoUpdate = 0;
        SEMIDIClockReceiverSampleBufferClear(&_tickSampleBuffer);
        SEMIDIClockReceiverSampleBufferClear(&_timeBaseSampleBuffer);
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

static void SEMIDIClockReceiverSampleBufferIntegrateSample(SEMIDIClockReceiverSampleBuffer *buffer, uint64_t sample) {
    
    // First determine if sample is an outlier. We identify outliers for two purposes: to allow for adjustments in
    // timeline position independent of tempo change (which necessitate one tick with a correction interval that appears
    // as an outlier), and to identify consecutive outliers which represent a new value, so we can converge faster upon that.
    
    BOOL outlier = NO;
    if ( SEMIDIClockReceiverSampleBufferFillCount(buffer) < kMinSamplesBeforeEvaluatingOutliers ) {
        
        // Not enough samples seen yet
        outlier = NO;
        
    } else {
        
        // It's an outlier if it's outside our threshold past the observed average
        uint64_t outlierThreshold = MAX(kOutlierThresholdRatio * buffer->standardDeviation, SESecondsToHostTicks(kMinimumOutlierThreshold));
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
                        _SEMIDIClockReceiverSampleBufferAddSampleToBuffer(buffer, buffer->outliers[i]);
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
                _SEMIDIClockReceiverSampleBufferAddSampleToBuffer(buffer, buffer->outliers[i]);
            }
            
            buffer->outlierCount = 0;
        } else {
            // Ignore outlier for now
        }
    } else {
        // Not an outlier: integrate this sample
        _SEMIDIClockReceiverSampleBufferAddSampleToBuffer(buffer, sample);
        
        if ( buffer->outlierCount != 0 ) {
            // Ignore any outliers we saw
            buffer->outlierCount = 0;
        }
    }
    
    #ifdef DEBUG_LOGGING
    // Diagnosis logging
    if ( sample < 1e8 ) {
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

static uint64_t SEMIDIClockReceiverSampleBufferCalculatedValue(SEMIDIClockReceiverSampleBuffer *buffer) {
    return buffer->mean;
}

static uint64_t SEMIDIClockReceiverSampleBufferStandardDeviation(SEMIDIClockReceiverSampleBuffer *buffer) {
    if ( buffer->seenSamples <= kMinSamplesBeforeStoringStandardDeviation ) {
        return buffer->standardDeviation;
    }
    uint64_t max = 0;
    for ( int i=0; i<kStandardDeviationHistorySamples; i++ ) {
        max = MAX(max, buffer->standardDeviationHistory[i]);
    }
    return max;
}

static int SEMIDIClockReceiverSampleBufferSamplesSeen(SEMIDIClockReceiverSampleBuffer *buffer) {
    return buffer->seenSamples;
}

static int SEMIDIClockReceiverSampleBufferSamplesSinceLastSignificantChange(SEMIDIClockReceiverSampleBuffer *buffer) {
    return buffer->sampleCountSinceLastSignificantChange;
}

static BOOL SEMIDIClockReceiverSampleBufferSignificantChangeHappened(SEMIDIClockReceiverSampleBuffer *buffer) {
    BOOL significantChange = buffer->significantChange;
    buffer->significantChange = NO;
    return significantChange;
}

static void SEMIDIClockReceiverSampleBufferClear(SEMIDIClockReceiverSampleBuffer *buffer) {
    memset(buffer, 0, sizeof(SEMIDIClockReceiverSampleBuffer));
}

static int SEMIDIClockReceiverSampleBufferFillCount(SEMIDIClockReceiverSampleBuffer *buffer) {
    return buffer->head >= buffer->tail
        ? buffer->head - buffer->tail
        : (buffer->head + kSampleBufferSize) - buffer->tail;
}

static void _SEMIDIClockReceiverSampleBufferAddSampleToBuffer(SEMIDIClockReceiverSampleBuffer *buffer, uint64_t sample) {
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
    buffer->mean = buffer->accumulator / SEMIDIClockReceiverSampleBufferFillCount(buffer);
    
    // Calculate new standard deviation
    uint64_t sum = 0;
    for ( int i=buffer->tail; i != buffer->head; i = (i+1) % kSampleBufferSize ) {
        uint64_t absDifference = buffer->samples[i] > buffer->mean ? buffer->samples[i] - buffer->mean : buffer->mean - buffer->samples[i];
        sum += absDifference*absDifference;
    }
    buffer->standardDeviation = sqrt((double)sum / (double)SEMIDIClockReceiverSampleBufferFillCount(buffer));
    
    if ( buffer->sampleCountSinceLastSignificantChange > kMinSamplesBeforeStoringStandardDeviation ) {
        int standardDeviationHistoryBucket = (buffer->sampleCountSinceLastSignificantChange / kStandardDeviationHistoryEntryDuration) % kStandardDeviationHistorySamples;
        if ( buffer->sampleCountSinceLastSignificantChange % kStandardDeviationHistoryEntryDuration == 0 ) {
            buffer->standardDeviationHistory[standardDeviationHistoryBucket] = 0;
        }
        buffer->standardDeviationHistory[standardDeviationHistoryBucket] = MAX(buffer->standardDeviationHistory[standardDeviationHistoryBucket], buffer->standardDeviation);
    }
}

@end
