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

@interface SEMIDIClockSenderThread : NSThread
@property (nonatomic, weak) SEMIDIClockSender * sender;
@end

@interface SEMIDIClockSender () {
    double   _positionAtStart;
    uint64_t _timeAdvanceAtStart;
}
@property (nonatomic, strong, readwrite) id<SEMIDIClockSenderInterface> senderInterface;
@property (nonatomic, strong) SEMIDIClockSenderThread *thread;
@property (nonatomic, readwrite) BOOL started;
@property (nonatomic) uint64_t nextTickTime;
@property (nonatomic) uint64_t timeBase;
@end

@implementation SEMIDIClockSender
@dynamic timelinePosition;

-(instancetype)initWithInterface:(id<SEMIDIClockSenderInterface>)senderInterface {
    if ( !(self = [super init]) ) return nil;
    
    self.senderInterface = senderInterface;
    
    return self;
}

-(void)dealloc {
    if ( _thread ) {
        [_thread cancel];
        while ( !_thread.isFinished ) {
            [NSThread sleepForTimeInterval:0.01];
        }
    }
}

-(uint64_t)startAtTime:(uint64_t)startTime {
    NSAssert(_tempo != 0, @"You must provide a tempo first");
    
    @synchronized ( self ) {
        if ( !startTime ) {
            // Determine next safe timestamp, based on next tick time.
            //
            // When sending clock ticks, this class sends a certain number of ticks in advance,
            // in order to overcome system congestion and latency. This means that at any point in
            // time, there are some ticks that have already been sent which correspond to a point
            // in the future.
            //
            // If the clock were to be started at a point before this future time, then these future
            // ticks will probably be at the wrong time. Given that the tick that immediately follows
            // the clock start message starts the clock running at the remote end, this may mean the
            // remote end is out of sync slightly, until the new correctly-timed ticks are received
            // and processed.
            //
            // To avoid the risk of this sync problem, we determine the time that corresponds to the
            // moment after the most recently sent advance tick.
            
            startTime = _tempo != 0.0 && _nextTickTime
                ? _nextTickTime
                : (SECurrentTimeInHostTicks() + SESecondsToHostTicks(1.0e-3) /* 1 ms, recommended by MIDI standard */);
            
            // Subtract the advance time, because we're going to add it later (as we would with a user-provided timestamp)
            startTime -= _timeAdvanceAtStart;
        }
        
        // Determine initial timeline position, factoring in any sync advance to account for sub-16th-note quantities
        double timelinePosition = _positionAtStart + SEHostTicksToBeats(_timeAdvanceAtStart, _tempo);
        
        // Set time base, calculated backwards from cued timeline position
        _timeBase = startTime - SEBeatsToHostTicks(_positionAtStart, _tempo) + _timeAdvanceAtStart;
        
        // Send start/continue message
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        unsigned char message[1] = { timelinePosition > 0.0 ? SEMIDIMessageContinue : SEMIDIMessageClockStart };
        MIDIPacketListAdd(&packetList, sizeof(packetList), packet, startTime - 1 /* force ordering immediately before tick */, sizeof(message), message);
        [_senderInterface sendMIDIPacketList:&packetList];
        
        // Prepare to send the next tick at the apply time, or the smallest multiple of the tick time past the apply time that is also past the current next tick time
        uint64_t nextTickTime = startTime + _timeAdvanceAtStart;
        uint64_t tickDuration = SESecondsToHostTicks((60.0 / _tempo) / SEMIDITicksPerBeat);
        if ( _nextTickTime > SESecondsToHostTicks(kTickResyncThreshold) && nextTickTime < _nextTickTime - SESecondsToHostTicks(kTickResyncThreshold) ) {
            uint64_t advance = tickDuration - ((_nextTickTime - nextTickTime) % tickDuration);
            if ( advance < SESecondsToHostTicks(kTickResyncThreshold) || tickDuration-advance < SESecondsToHostTicks(kTickResyncThreshold) ) {
                advance = 0;
            }
            nextTickTime = _nextTickTime + advance;
        }
        
        _nextTickTime = nextTickTime;
    }
    
    _positionAtStart = 0;
    _timeAdvanceAtStart = 0;
    self.started = YES;
    
    return startTime;
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
}

-(uint64_t)setActiveTimelinePosition:(double)timelinePosition atTime:(uint64_t)applyTime {
    @synchronized ( self ) {
        uint64_t tickDuration = SESecondsToHostTicks((60.0 / _tempo) / SEMIDITicksPerBeat);
        uint64_t beatDuration = tickDuration * SEMIDITicksPerSongPositionBeat;
        
        if ( !applyTime ) {
            if ( _started && fmod(timelinePosition, (double)SEMIDITicksPerSongPositionBeat / (double)SEMIDITicksPerBeat) < 1.0e-5 ) {
                // The new position is very close to a MIDI Beat division, and we've been left to choose an apply time ourselves,
                // so we have the opportunity to pick an apply time that will result in a smooth on-the-beat transition.
                // Determine when the next MIDI tick is, in our current timeline, and use that as the apply time.
                uint64_t currentPosition = SECurrentTimeInHostTicks() - _timeBase;
                
                uint64_t timeUntilNextTick = tickDuration - (currentPosition % tickDuration);
                applyTime = _timeBase + currentPosition + timeUntilNextTick;
            } else {
                // Just use the current time
                applyTime = SECurrentTimeInHostTicks();
            }
        }

        // Calculate time base, and determine relative position in host ticks
        uint64_t timeBase = applyTime - SEBeatsToHostTicks(timelinePosition, _tempo);
        
        // Calculate sync advance to closest MIDI Beat (16th note)
        uint64_t syncAdvance = 0;
        uint64_t position = applyTime - timeBase;
        uint64_t modulus = position % beatDuration;
        uint64_t threshold = SESecondsToHostTicks(kFirstBeatSyncThreshold);
        if ( modulus > threshold && beatDuration - modulus > threshold ) {
            syncAdvance = beatDuration - modulus;
        }
        
        // Determine number of MIDI Beats to report
        double beatsToMIDIBeats = (double)SEMIDITicksPerBeat / (double)SEMIDITicksPerSongPositionBeat;
        int totalBeats = round((timelinePosition + SEHostTicksToBeats(syncAdvance, _tempo)) * beatsToMIDIBeats);
        
        if ( _started ) {
            // Update the timebase
            _timeBase = timeBase;
            
            // Prepare to send the next tick at the apply time, or the smallest multiple of the tick time past the apply time that is also past the current next tick time
            uint64_t nextTickTime = applyTime + syncAdvance;
            uint64_t tickDuration = SESecondsToHostTicks((60.0 / _tempo) / SEMIDITicksPerBeat);
            if ( nextTickTime < _nextTickTime - SESecondsToHostTicks(kTickResyncThreshold) ) {
                uint64_t advance = tickDuration - ((_nextTickTime - nextTickTime) % tickDuration);
                if ( advance < SESecondsToHostTicks(kTickResyncThreshold) || tickDuration-advance < SESecondsToHostTicks(kTickResyncThreshold) ) {
                    advance = 0;
                }
                nextTickTime = _nextTickTime + advance;
            }
            
            _nextTickTime = nextTickTime;
        } else {
            // Cue this position for when we start
            _positionAtStart = timelinePosition;
            _timeAdvanceAtStart = syncAdvance;
        }
        
        // Send song position
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        unsigned char positionMessage[3] = {SEMIDIMessageSongPosition, totalBeats & 0x7F, (totalBeats >> 7) & 0x7F};
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, applyTime + syncAdvance - 1 /* force ordering before tick */, sizeof(positionMessage), positionMessage);
        [_senderInterface sendMIDIPacketList:&packetList];
    }
    
    return applyTime;
}

-(double)activeTimelinePositionForTime:(uint64_t)timestamp {
    if ( !_started ) {
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

-(void)setTimelinePosition:(double)timelinePosition {
    [self setActiveTimelinePosition:timelinePosition atTime:0];
}

-(double)timelinePosition {
    return [self activeTimelinePositionForTime:0];
}

-(void)setTempo:(double)tempo {
    if ( _tempo == tempo ) {
        return;
    }
    
    NSAssert(!(tempo == 0.0 && _started), @"You must stop the clock before setting tempo to zero");
    
    @synchronized ( self ) {
        if ( _timeBase ) {
            // Scale time base to new tempo, so our relative timeline position remains the same (as it is dependent on tempo)
            double ratio = _tempo / tempo;
            uint64_t now = SECurrentTimeInHostTicks();
            _timeBase = now - ((now - _timeBase) * ratio);
        }
        
        _tempo = tempo;
    }
    
    if ( tempo != 0.0 && !_thread ) {
        // Start the thread which will send out the ticks
        self.thread = [SEMIDIClockSenderThread new];
        _thread.sender = self;
        [_thread start];
    } else if ( tempo == 0.0 && _thread ) {
        // Stop the thread
        [_thread cancel];
        self.thread = nil;
    }
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
            _sender.nextTickTime = [self sendTicksFromTime:_sender.nextTickTime toTime:now + (tickDuration * kTicksPerSendInterval)];
            
            // Wait half the duration of the ticks we just sent (to avoid running out of time; we'll skip the ticks we've already sent)
            nextSendTime = now + (tickDuration * kTicksPerSendInterval) / 2;
        }
        
        // Sleep
        mach_wait_until(nextSendTime);
    }
}

-(uint64_t)sendTicksFromTime:(uint64_t)start toTime:(uint64_t)end {
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
    
    // Send ticks for the time period from 'start', and up to (but not including) 'end'
    MIDIPacketList packetList;
    uint8_t message = SEMIDIMessageClock;
    uint64_t time = start;
    int count = 0;
    for ( count = 0; time < end; count++, time += tickDuration ) {
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
