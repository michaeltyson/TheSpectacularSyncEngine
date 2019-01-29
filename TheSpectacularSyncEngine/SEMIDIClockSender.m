//
//  SEMIDIClockSender.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIClockSender.h"
#import "SECommon.h"

static const int kTicksPerSendInterval                      = 4;      // Max MIDI ticks to send per interval
static const NSTimeInterval kFirstBeatSyncThreshold         = 1.0e-3; // Wait to send first beat if it's further away than this
static const NSTimeInterval kTickResyncThreshold            = 1.0e-6; // If tick is beyond this threshold out of sync, resync
static const double kThreadPriority                         = 0.8;    // Priority of the sender thread
static const int kMaxPendingMessages                        = 10;     // Size of pending message buffer

@interface SEMIDIClockSenderThread : NSThread
@property (nonatomic, weak) SEMIDIClockSender * sender;
@end

@interface SEMIDIClockSender () {
    double   _positionAtStart;
    MIDIPacketList _pendingMessages[kMaxPendingMessages];
}
@property (nonatomic, strong, readwrite) id<SEMIDIClockSenderInterface> senderInterface;
@property (nonatomic, strong) SEMIDIClockSenderThread *thread;
@property (nonatomic, readwrite) BOOL started;
@property (nonatomic) uint64_t nextTickTime;
@property (nonatomic) uint64_t timeBase;
@property (nonatomic) MIDIPacketList * pendingMessages;
@end

@implementation SEMIDIClockSender
@dynamic timelinePosition;
@dynamic pendingMessages;

-(instancetype)initWithInterface:(id<SEMIDIClockSenderInterface>)senderInterface {
    if ( !(self = [super init]) ) return nil;
    
    self.senderInterface = senderInterface;
    
    return self;
}

-(void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendSongPositionDelayed) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startThread) object:nil];
    if ( _thread ) {
        [_thread cancel];
        while ( !_thread.isFinished ) {
            [NSThread sleepForTimeInterval:0.01];
        }
    }
}

-(uint64_t)startAtTime:(uint64_t)startTime {
    NSAssert(_tempo != 0, @"You must provide a tempo first");
    return [self startOrSeekWithPosition:_positionAtStart atTime:startTime startClock:YES];
}

-(void)stop {
    @synchronized ( self ) {
        // Send stop message
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        unsigned char message[1] = { SEMIDIMessageClockStop };
        MIDIPacketListAdd(&packetList, sizeof(packetList), packet, SECurrentTimeInHostTicks(), sizeof(message), message);
        [_senderInterface sendMIDIPacketList:&packetList];
        
        self.started = NO;
    }
    
    if ( !_sendClockTicksWhileTimelineStopped && _thread ) {
        // Stop the thread
        [_thread cancel];
        self.thread = nil;
    }
}

-(uint64_t)setActiveTimelinePosition:(double)timelinePosition atTime:(uint64_t)applyTime {
    return [self startOrSeekWithPosition:timelinePosition atTime:applyTime startClock:NO];
}

-(double)timelinePositionForTime:(uint64_t)timestamp {
    return SEMIDIClockSenderGetTimelinePosition(self, timestamp);
}

double SEMIDIClockSenderGetTimelinePosition(__unsafe_unretained SEMIDIClockSender * THIS, uint64_t time) {
    if ( !THIS->_started ) {
        return THIS->_positionAtStart;
    }
    
    if ( !time ) {
        time = SECurrentTimeInHostTicks();
    }
    
    if ( time < THIS->_timeBase ) {
        return 0.0;
    }
    
    // Calculate offset from our time base, and convert to beats using current tempo
    return SEHostTicksToBeats(time - THIS->_timeBase, THIS->_tempo);
}

BOOL SEMIDIClockSenderIsStarted(__unsafe_unretained SEMIDIClockSender * THIS) {
    return THIS->_started;
}

-(void)setTimelinePosition:(double)timelinePosition {
    [self setActiveTimelinePosition:timelinePosition atTime:SECurrentTimeInHostTicks()];
}

-(double)timelinePosition {
    return [self timelinePositionForTime:0];
}

-(void)setTempo:(double)tempo {
    if ( _tempo == tempo ) {
        return;
    }
    
    if ( tempo == 0.0 && !_started ) {
        [self stop];
    }
    
    @synchronized ( self ) {
        if ( _timeBase ) {
            // Scale time base to new tempo, so our relative timeline position remains the same (as it is dependent on tempo)
            double ratio = _tempo / tempo;
            uint64_t now = SECurrentTimeInHostTicks();
            _timeBase = now - ((now - _timeBase) * ratio);
        }
        
        _tempo = tempo;
    }
    
    if ( _sendClockTicksWhileTimelineStopped ) {
        if ( tempo != 0.0 && !_thread ) {
            // Start the thread which will send out the ticks - in a moment, in case clock is started next
            [self performSelector:@selector(startThread) withObject:nil afterDelay:0.0];
        } else if ( tempo == 0.0 && _thread ) {
            // Stop the thread
            [_thread cancel];
            self.thread = nil;
        }
    }
}

-(uint64_t)startOrSeekWithPosition:(double)timelinePosition atTime:(uint64_t)applyTime startClock:(BOOL)start {
    @synchronized ( self ) {
        uint64_t tickDuration = SESecondsToHostTicks((60.0 / _tempo) / SEMIDITicksPerBeat);
        uint64_t MIDIBeatDuration = tickDuration * SEMIDITicksPerSongPositionBeat;
        double beatsToMIDIBeats = (double)SEMIDITicksPerBeat / (double)SEMIDITicksPerSongPositionBeat;
        uint64_t beatSyncThreshold = SESecondsToHostTicks(kFirstBeatSyncThreshold);
        
        if ( !_started && !start ) {
            // Cue this position for when we start
            _positionAtStart = timelinePosition;
            
            // Send song position in next run loop (delayed, in case we're just about to start the clock,
            // in which case we want to send the song position at the same timestamp
            [self performSelector:@selector(sendSongPositionDelayed) withObject:nil afterDelay:0];
            
            return applyTime;
        }
        
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendSongPositionDelayed) object:nil];
        
        if ( !applyTime ) {
            // We've been left to choose an apply time ourselves: choose the next tick time,
            // to give us the best chance of a smooth transition.
            applyTime = _nextTickTime ? _nextTickTime : SECurrentTimeInHostTicks();
        } else if ( _nextTickTime ) {
            // Find the next tick time after the given apply time
            uint64_t originalApplyTime = applyTime;
            if ( applyTime < _nextTickTime ) {
                applyTime = _nextTickTime;
            } else {
                uint64_t modulus = (applyTime - _nextTickTime) % tickDuration;
                if ( modulus > beatSyncThreshold && (tickDuration - modulus) > beatSyncThreshold ) {
                    applyTime += tickDuration - modulus;
                }
            }
            if ( applyTime > originalApplyTime ) {
                // Need to adjust the timeline position accordingly
                timelinePosition += SEHostTicksToBeats(applyTime - originalApplyTime, _tempo);
            }
        }
        
        // Calculate time base, and determine relative position in host ticks
        uint64_t timeBase = applyTime - SEBeatsToHostTicks(timelinePosition, _tempo);
        
        if ( _nextTickTime && applyTime <= (_nextTickTime-tickDuration) ) {
            // If our apply time is before the last tick we sent, we'll need to move up the timeline.
            // Work out when the next MIDI beat is, and use that as our apply time
            uint64_t latestPosition = _nextTickTime - timeBase;
            uint64_t timeUntilNextMIDIBeat = MIDIBeatDuration - (latestPosition % MIDIBeatDuration);
            applyTime = timeBase + latestPosition + timeUntilNextMIDIBeat;
            timelinePosition = SEHostTicksToBeats(applyTime - timeBase, _tempo);
        }
        
        // Calculate time, in our new timeline, to the closest MIDI Beat (16th note)
        uint64_t timeUntilNextMIDIBeat = 0;
        uint64_t position = applyTime - timeBase;
        uint64_t modulus = position % MIDIBeatDuration;
        if ( modulus > beatSyncThreshold && MIDIBeatDuration - modulus > beatSyncThreshold ) {
            timeUntilNextMIDIBeat = MIDIBeatDuration - modulus;
        }
        
        // Determine number of MIDI Beats to report
        int totalBeats = round((timelinePosition + SEHostTicksToBeats(timeUntilNextMIDIBeat, _tempo)) * beatsToMIDIBeats);
        
        if ( _started || totalBeats > 0 ) {
            // Send song position
            [self enqueueMessage:(unsigned char[3]){SEMIDIMessageSongPosition, totalBeats & 0x7F, (totalBeats >> 7) & 0x7F}
                          length:3
                            time:applyTime + timeUntilNextMIDIBeat - 1 /* force ordering before tick */];
        }
        
        if ( _started || start) {
            // Update the timebase
            _timeBase = timeBase;
        }
        
        if ( !_started && start ) {
            [self enqueueMessage:(unsigned char[1]){ totalBeats > 0.0 ? SEMIDIMessageContinue : SEMIDIMessageClockStart }
                          length:1
                            time:applyTime + timeUntilNextMIDIBeat - 1 /* force ordering before tick */];
            
            _positionAtStart = 0;
            self.started = YES;
            _nextTickTime = applyTime + timeUntilNextMIDIBeat;
            
            if ( !_thread ) {
                [self startThread];
            }
        }
    }
    
    return applyTime;
}

-(void)startThread {
    if ( !_thread ) {
        self.thread = [SEMIDIClockSenderThread new];
        _thread.sender = self;
        [_thread start];
    }
}

-(void)enqueueMessage:(const unsigned char*)message length:(int)length time:(MIDITimeStamp)timestamp {
    if ( _thread ) {
        // Enqueue message to be sent from sender thread, at the appropriate time
        for ( int i=0; i<kMaxPendingMessages; i++ ) {
            if ( _pendingMessages[i].numPackets == 0 ) {
                MIDIPacket *packet = MIDIPacketListInit(&_pendingMessages[i]);
                packet = MIDIPacketListAdd(&_pendingMessages[i], sizeof(_pendingMessages[i]), packet, timestamp, length, message);
                break;
            }
        }
    } else {
        // Send immediately
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, timestamp, length, message);
        [_senderInterface sendMIDIPacketList:&packetList];
    }
}

-(MIDIPacketList *)pendingMessages {
    return _pendingMessages;
}

-(void)sendSongPositionDelayed {
    double beatsToMIDIBeats = (double)SEMIDITicksPerBeat / (double)SEMIDITicksPerSongPositionBeat;
    int totalBeats = round(_positionAtStart * beatsToMIDIBeats);
    [self enqueueMessage:(unsigned char[3]){SEMIDIMessageSongPosition, totalBeats & 0x7F, (totalBeats >> 7) & 0x7F}
                  length:3
                    time:SECurrentTimeInHostTicks()];
}

@end

@implementation SEMIDIClockSenderThread

-(void)main {
    [NSThread setThreadPriority:kThreadPriority];
    
    while ( !self.isCancelled ) {
        uint64_t nextSendTime = 0;
        
        @synchronized ( _sender ) {
            uint64_t now = SECurrentTimeInHostTicks();
            
            if ( !_sender.nextTickTime ) {
                _sender.nextTickTime = now;
            }
            
            // Send the next batch of ticks
            uint64_t tickDuration = SESecondsToHostTicks((60.0 / _sender.tempo) / SEMIDITicksPerBeat);
            _sender.nextTickTime = [self sendFromTime:_sender.nextTickTime toTime:now + (tickDuration * kTicksPerSendInterval)];
            
            // Wait half the duration of the ticks we just sent (to avoid running out of time; we'll skip the ticks we've already sent)
            nextSendTime = now + (tickDuration * kTicksPerSendInterval) / 2;
        }
        
        // Sleep
        mach_wait_until(nextSendTime);
    }
    
    @synchronized ( _sender ) {
        _sender.nextTickTime = 0;
    }
}

-(uint64_t)sendFromTime:(uint64_t)start toTime:(uint64_t)end {
    if ( _sender.tempo == 0 ) {
        return start;
    }
    
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / _sender.tempo) / SEMIDITicksPerBeat);
    
    uint64_t timeBase = _sender.timeBase;
    if ( timeBase ) {
        // Calculate distance to next scheduled tick
        uint64_t position = start - timeBase;
        uint64_t modulus = position % tickDuration;
        uint64_t threshold = SESecondsToHostTicks(kTickResyncThreshold);
        if ( modulus > threshold && tickDuration - modulus > threshold ) {
            // Resync to the closest tick, to make sure it's a multiple of the tick duration away from the time base
            start = timeBase + round((double)position / (double)tickDuration) * tickDuration;
        }
    }
    
    MIDIPacketList * pendingMessages = _sender.pendingMessages;
    
    // Send messages for the time period from 'start', and up to (but not including) 'end'
    MIDIPacketList packetList;
    uint8_t message = SEMIDIMessageClock;
    uint64_t time = start;
    int count = 0;
    for ( count = 0; time < end; count++, time += tickDuration ) {
        // Dispatch pending messages
        for ( int i=0; i<kMaxPendingMessages; i++ ) {
            if ( pendingMessages[i].numPackets != 0 && pendingMessages[i].packet[0].timeStamp < time ) {
                [_sender.senderInterface sendMIDIPacketList:&pendingMessages[i]];
                pendingMessages[i].numPackets = 0;
            }
        }
        
        if ( time < start ) {
            // Skip ticks we've already sent
            continue;
        }
        
        // Send tick
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        MIDIPacketListAdd(&packetList, sizeof(packetList), packet, time, 1, &message);
        [_sender.senderInterface sendMIDIPacketList:&packetList];
    }
    
    // Return the time the next tick should be sent
    return time;
}

@end
