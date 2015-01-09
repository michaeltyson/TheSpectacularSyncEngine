//
//  SEMIDIClockSenderTests.m
//  Tests
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SEMIDIClockSender.h"

@interface SEMIDIClockSenderTestInterface : NSObject <SEMIDIClockSenderInterface> {
    uint64_t _lastTimestamp;
}
-(void)clear;
@property (nonatomic) NSArray * sentMessages;
@property (nonatomic, readonly) NSArray * sortedSentMessages;
@end

@interface SEMIDIClockSenderTests : XCTestCase

@end

@implementation SEMIDIClockSenderTests

-(void)testSimpleSend {
    double tempo = 125.0; // Works out at one MIDI tick per 0.2 seconds
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    
    SEMIDIClockSenderTestInterface * interface = [SEMIDIClockSenderTestInterface new];
    SEMIDIClockSender * sender = [[SEMIDIClockSender alloc] initWithInterface:interface];
    
    uint64_t setTempoTime = SECurrentTimeInHostTicks();
    sender.tempo = tempo;
    
    // Run for a short time
    NSTimeInterval firstRunInterval = 1.0;
    [NSThread sleepForTimeInterval:firstRunInterval];
    
    // Get sent messages, properly ordered
    NSArray * sentMessages = interface.sortedSentMessages;
    
    // Verify correct number of ticks
    XCTAssertEqualWithAccuracy(sentMessages.count, 1 + (SESecondsToHostTicks(firstRunInterval) / tickDuration), 20);
    
    // Verify ticks
    int i = 0;
    uint64_t time = setTempoTime;
    for ( NSData * packetData in sentMessages ) {
        const MIDIPacketList * packetList = packetData.bytes;
        
        XCTAssertEqual(packetList->packet[0].length, 1, @"Tick %d has wrong length", i);
        XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageClock, @"Tick %d has wrong type", i);
        XCTAssertEqualWithAccuracy(packetList->packet[0].timeStamp,
                                   time,
                                   SESecondsToHostTicks(1.0e-3),
                                   @"Tick %d has wrong time (%lf s %@)",
                                   i,
                                   SEHostTicksToSeconds(labs((long)packetList->packet[0].timeStamp - (long)time)),
                                   packetList->packet[0].timeStamp > time ? @"ahead" : @"behind");
        
        if ( packetList->packet[0].length != 1
            || labs(((long)packetList->packet[0].timeStamp - (long)time)) > SESecondsToHostTicks(1.0e-3)
            || packetList->packet[0].data[0] != SEMIDIMessageClock ) {
            break;
        }
        
        i++;
        time += tickDuration;
    }
    
    // Set the timeline position
    NSTimeInterval timelinePosition = 9.0; // In beats
    sender.timelinePosition = timelinePosition;
    
    // Verify we got the timeline position update
    const MIDIPacketList * packetList = [interface.sentMessages.lastObject bytes];
    XCTAssertEqual(packetList->packet[0].length, 3);
    XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageSongPosition);
    int beats = ((unsigned short)packetList->packet[0].data[2] << 7) | (unsigned short)packetList->packet[0].data[1];
    XCTAssertEqual(beats, timelinePosition * ((double)SEMIDITicksPerBeat / (double)SEMIDITicksPerSongPositionBeat));
    
    // Start
    uint64_t startTime = [sender startAtTime:0];
    
    // Verify we got the continue message
    packetList = [interface.sentMessages.lastObject bytes];
    XCTAssertEqual(packetList->packet[0].length, 1);
    XCTAssertEqual(packetList->packet[0].timeStamp, startTime - 1);
    XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageContinue);
    
    // Run for a short time
    NSTimeInterval secondRunInterval = 2.0;
    [NSThread sleepForTimeInterval:secondRunInterval];
    
    // Get sent messages, properly ordered
    sentMessages = interface.sortedSentMessages;
    
    // Find continue message
    for ( i=0; i<sentMessages.count; i++ ) {
        packetList = [sentMessages[i] bytes];
        if ( packetList->packet[0].data[0] == SEMIDIMessageContinue ) {
            break;
        }
    }
    
    XCTAssertNotEqual(i, sentMessages.count);
    
    i++;
    
    // Verify correct number of ticks following start
    XCTAssertEqualWithAccuracy(sentMessages.count - i, SESecondsToHostTicks(secondRunInterval) / tickDuration, 20);
    
    // Now verify ticks
    time = startTime;
    for ( int index=1 ; i < sentMessages.count-1; i++, time += tickDuration, index++ ) {
        const MIDIPacketList * packetList = [sentMessages[i] bytes];
        
        XCTAssertEqual(packetList->packet[0].length, 1, @"Tick %d has wrong length", index);
        XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageClock, @"Tick %d has wrong type", index);
        XCTAssertEqualWithAccuracy(packetList->packet[0].timeStamp,
                                   time,
                                   SESecondsToHostTicks(1.0e-9),
                                   @"Tick %d has wrong time (%lf s %@)",
                                   index,
                                   SEHostTicksToSeconds(labs((long)packetList->packet[0].timeStamp - (long)time)),
                                   packetList->packet[0].timeStamp > time ? @"ahead" : @"behind");
        
        if ( packetList->packet[0].length != 1
            || labs(((long)packetList->packet[0].timeStamp - (long)time)) > SESecondsToHostTicks(1.0e-9)
            || packetList->packet[0].data[0] != SEMIDIMessageClock ) {
            break;
        }
    }
    
    // Stop
    [sender stop];
    
    // Verify we got stop message
    packetList = [interface.sentMessages.lastObject bytes];
    XCTAssertEqual(packetList->packet[0].length, 1);
    XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageClockStop);
}

-(void)testTempoChange {
    double firstTempo = 120.0;
    double secondTempo = 180.0;
    
    SEMIDIClockSenderTestInterface * interface = [SEMIDIClockSenderTestInterface new];
    SEMIDIClockSender * sender = [[SEMIDIClockSender alloc] initWithInterface:interface];
    
    sender.tempo = firstTempo;
    
    // Run for a little while
    NSTimeInterval firstRunInterval = 1.0;
    [NSThread sleepForTimeInterval:firstRunInterval];
    
    // Now change tempo
    sender.tempo = secondTempo;
    
    // Run for a little while longer
    NSTimeInterval secondRunInterval = 1.0;
    [NSThread sleepForTimeInterval:secondRunInterval];
    
    // Verify
    NSArray * sentMessages = interface.sortedSentMessages;
    
    uint64_t firstTempoTickDuration = SESecondsToHostTicks((60.0 / firstTempo) / SEMIDITicksPerBeat);
    uint64_t secondTempoTickDuration = SESecondsToHostTicks((60.0 / secondTempo) / SEMIDITicksPerBeat);
    
    XCTAssertEqualWithAccuracy(sentMessages.count, 1 + (SESecondsToHostTicks(firstRunInterval) / firstTempoTickDuration) + (SESecondsToHostTicks(secondRunInterval) / secondTempoTickDuration), 20);
    
    const MIDIPacketList * packetList = [sentMessages[0] bytes];
    XCTAssertEqual(packetList->numPackets, 1);
    uint64_t time = packetList->packet[0].timeStamp;
    
    int i;
    uint64_t lastTime = time;
    for ( i = 0; i < sentMessages.count-1; i++, lastTime = time, time += firstTempoTickDuration ) {
        packetList = [sentMessages[i] bytes];
        XCTAssertEqual(packetList->packet[0].length, 1, @"Tick %d has wrong length", i+1);
        XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageClock, @"Tick %d has wrong type", i+1);
        
        if ( labs((long)(packetList->packet[0].timeStamp - (long)lastTime) - (long)secondTempoTickDuration) < SESecondsToHostTicks(1.0e-8) ) {
            time = lastTime + secondTempoTickDuration;
            break;
        }
        
        XCTAssertEqualWithAccuracy(packetList->packet[0].timeStamp,
                                   time,
                                   SESecondsToHostTicks(1.0e-9),
                                   @"Tick %d has wrong time (%lf s %@)",
                                   i+1,
                                   SEHostTicksToSeconds(labs((long)packetList->packet[0].timeStamp - (long)time)),
                                   packetList->packet[0].timeStamp > time ? @"ahead" : @"behind");
        
        
        if ( packetList->packet[0].length != 1
            || labs((long)packetList->packet[0].timeStamp - (long)time) > SESecondsToHostTicks(1.0e-9)
            || packetList->packet[0].data[0] != SEMIDIMessageClock ) {
            break;
        }
    }
    
    int firstSegmentEnd = i;
    XCTAssertEqualWithAccuracy(i, 1 + (SESecondsToHostTicks(firstRunInterval) / firstTempoTickDuration), 20);
    
    // Tempo change from here
    
    for ( ; i < sentMessages.count-1; i++, time += secondTempoTickDuration ) {
        packetList = [sentMessages[i] bytes];
        XCTAssertEqual(packetList->packet[0].length, 1, @"Tick %d has wrong length", i);
        XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageClock, @"Tick %d has wrong type", i);
        XCTAssertEqualWithAccuracy(packetList->packet[0].timeStamp,
                                   time,
                                   SESecondsToHostTicks(1.0e-9),
                                   @"Tick %d has wrong time (%lf s %@)",
                                   i,
                                   SEHostTicksToSeconds(labs((long)packetList->packet[0].timeStamp - (long)time)),
                                   packetList->packet[0].timeStamp > time ? @"ahead" : @"behind");
        
        if ( packetList->packet[0].length != 1
            || labs((long)packetList->packet[0].timeStamp - (long)time) > SESecondsToHostTicks(1.0e-9)
            || packetList->packet[0].data[0] != SEMIDIMessageClock ) {
            break;
        }
    }
    
    XCTAssertEqualWithAccuracy(i - firstSegmentEnd, (SESecondsToHostTicks(secondRunInterval) / secondTempoTickDuration), 20);
}

-(void)testPositionChange {
    double tempo = 120.0;
    
    SEMIDIClockSenderTestInterface * interface = [SEMIDIClockSenderTestInterface new];
    SEMIDIClockSender * sender = [[SEMIDIClockSender alloc] initWithInterface:interface];
    sender.tempo = tempo;
    
    // Run for a little while
    uint64_t time = [sender startAtTime:0];
    NSTimeInterval firstRunInterval = 1.0;
    [NSThread sleepForTimeInterval:firstRunInterval];
    
    // Now change timeline position
    NSTimeInterval secondTimelinePosition = 7;
    uint64_t secondTimelinePositionSetTime = [sender setActiveTimelinePosition:secondTimelinePosition atTime:0];
    
    // Run for a little while longer
    NSTimeInterval secondRunInterval = 0.5;
    [NSThread sleepForTimeInterval:secondRunInterval];
    
    // Change timeline position once more, but do so at an irregular number of beats
    NSTimeInterval thirdTimelinePosition = 8.1;
    uint64_t thirdTimelinePositionSetTime = [sender setActiveTimelinePosition:thirdTimelinePosition atTime:0];
    
    // Run for a little while longer
    NSTimeInterval thirdRunInterval = 0.5;
    [NSThread sleepForTimeInterval:thirdRunInterval];
    
    // Verify
    
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    uint64_t beatDuration = tickDuration * SEMIDITicksPerSongPositionBeat;
    
    NSArray *sentMessages = interface.sortedSentMessages;
    
    XCTAssertEqualWithAccuracy(sentMessages.count,
                               1 + (SESecondsToHostTicks(firstRunInterval) / tickDuration) + 2 + (SESecondsToHostTicks(secondRunInterval) / tickDuration) + 2 + (SESecondsToHostTicks(thirdRunInterval) / tickDuration), 20);
    
    // Find start
    int i;
    for ( i=0; i<sentMessages.count; i++ ) {
        const MIDIPacketList * packetList = [sentMessages[i] bytes];
        if ( packetList->packet[0].data[0] == SEMIDIMessageClockStart) {
            break;
        }
    }
    
    XCTAssertNotEqual(i, sentMessages.count);
    
    i++;
    
    for ( int index = 1; i < sentMessages.count-1; i++, time += tickDuration, index++ ) {
        const MIDIPacketList * packetList = [sentMessages[i] bytes];
        
        if ( packetList->packet[0].data[0] == SEMIDIMessageSongPosition ) {
            break;
        }
        
        XCTAssertEqual(packetList->packet[0].length, 1, @"Tick %d has wrong length", index);
        XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageClock, @"Tick %d has wrong type", index);
        XCTAssertEqualWithAccuracy(packetList->packet[0].timeStamp,
                                   time,
                                   SESecondsToHostTicks(1.0e-9),
                                   @"Tick %d has wrong time (%lf s %@)",
                                   index,
                                   SEHostTicksToSeconds(labs((long)packetList->packet[0].timeStamp - (long)time)),
                                   packetList->packet[0].timeStamp > time ? @"ahead" : @"behind");
        
        if ( packetList->packet[0].length != 1
            || labs((long)packetList->packet[0].timeStamp - (long)time) > SESecondsToHostTicks(1.0e-9)
            || packetList->packet[0].data[0] != SEMIDIMessageClock ) {
            break;
        }
    }
    
    int firstSegmentEnd = i;
    XCTAssertEqualWithAccuracy(i, 1 + (SESecondsToHostTicks(firstRunInterval) / tickDuration), 20);
    
    // Position change from here
    
    const MIDIPacketList * packetList = [sentMessages[i] bytes];
    const MIDIPacket * packet = &packetList->packet[0];
    
    XCTAssertEqual(packet->length, 3);
    XCTAssertEqual((SEMIDIMessage)packet->data[0], SEMIDIMessageSongPosition);
    int beats = ((unsigned short)packet->data[2] << 7) | (unsigned short)packet->data[1];
    int positionInBeats = (int)(SEBeatsToHostTicks(secondTimelinePosition, tempo) / beatDuration);
    XCTAssertEqual(beats, positionInBeats);
    XCTAssertEqual(packet->timeStamp, secondTimelinePositionSetTime-1);
    
    i++;
    
    for ( int index = 1; i < sentMessages.count-1; i++, time += tickDuration, index++ ) {
        packetList = [sentMessages[i] bytes];
        
        if ( packetList->packet[0].data[0] == SEMIDIMessageSongPosition ) {
            break;
        }
        
        XCTAssertEqual(packetList->packet[0].length, 1, @"Tick %d has wrong length", index);
        XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageClock, @"Tick %d has wrong type", index);
        XCTAssertEqualWithAccuracy(packetList->packet[0].timeStamp,
                                   time,
                                   SESecondsToHostTicks(1.0e-9),
                                   @"Tick %d has wrong time (%lf s %@)",
                                   index,
                                   SEHostTicksToSeconds(labs((long)packetList->packet[0].timeStamp - (long)time)),
                                   packetList->packet[0].timeStamp > time ? @"ahead" : @"behind");
        
        
        if ( packetList->packet[0].length != 1
            || labs((long)packetList->packet[0].timeStamp - (long)time) > SESecondsToHostTicks(1.0e-9)
            || packetList->packet[0].data[0] != SEMIDIMessageClock ) {
            break;
        }
    }
    
    XCTAssertEqualWithAccuracy(i - firstSegmentEnd, (SESecondsToHostTicks(secondRunInterval) / tickDuration), 20);
    
    // Second position change from here - verify that the song position was sent at the right time
    
    uint64_t beatOffset = beatDuration - (SEBeatsToHostTicks(thirdTimelinePosition, tempo) % beatDuration);
    uint64_t thirdChangeApplyTime = thirdTimelinePositionSetTime + beatOffset;
    
    packetList = [sentMessages[i] bytes];
    packet = &packetList->packet[0];
    
    XCTAssertEqual(packet->length, 3);
    XCTAssertEqual((SEMIDIMessage)packet->data[0], SEMIDIMessageSongPosition);
    XCTAssertEqual(packet->timeStamp, thirdChangeApplyTime - 1);
    beats = ((unsigned short)packet->data[2] << 7) | (unsigned short)packet->data[1];
    positionInBeats = ceil((double)SEBeatsToHostTicks(thirdTimelinePosition, tempo) / (double)beatDuration);
    XCTAssertEqual(beats, positionInBeats);
    
    int secondSegmentEnd = i;
    
    i++;
    BOOL foundNewTimeline;
    for ( int index = 1; i < sentMessages.count-1; i++, time += tickDuration, index++ ) {
        packetList = [sentMessages[i] bytes];
        
        if ( labs((long)packetList->packet[0].timeStamp - (long)time) > SESecondsToHostTicks(1.0e-8) ) {
            uint64_t sinceChange = labs((long)packetList->packet[0].timeStamp - (long)thirdChangeApplyTime);
            if ( (sinceChange % tickDuration) < SESecondsToHostTicks(1.0e-8) || (tickDuration - (sinceChange % tickDuration)) < SESecondsToHostTicks(1.0e-8) ) {
                // This tick is in the new timeline - carry on
                time = packetList->packet[0].timeStamp;
                foundNewTimeline = YES;
            }
        }
        
        XCTAssertEqual(packetList->packet[0].length, 1, @"Tick %d has wrong length", index);
        XCTAssertEqual((SEMIDIMessage)packetList->packet[0].data[0], SEMIDIMessageClock, @"Tick %d has wrong type", index);
        XCTAssertEqualWithAccuracy(packetList->packet[0].timeStamp,
                                   time,
                                   SESecondsToHostTicks(1.0e-9),
                                   @"Tick %d has wrong time (%lf s %@)",
                                   index,
                                   SEHostTicksToSeconds(labs((long)packetList->packet[0].timeStamp - (long)time)),
                                   packetList->packet[0].timeStamp > time ? @"ahead" : @"behind");
        
        
        if ( packetList->packet[0].length != 1
            || labs((long)packetList->packet[0].timeStamp - (long)time) > SESecondsToHostTicks(1.0e-9)
            || packetList->packet[0].data[0] != SEMIDIMessageClock ) {
            break;
        }
    }
    
    XCTAssertTrue(foundNewTimeline);
    
    XCTAssertEqualWithAccuracy(i - secondSegmentEnd, (SESecondsToHostTicks(thirdRunInterval) / tickDuration), 20);
}


@end


@implementation SEMIDIClockSenderTestInterface
@dynamic sortedSentMessages;

-(instancetype)init {
    if ( !(self = [super init]) ) return nil;
    self.sentMessages = [NSMutableArray array];
    return self;
}

-(void)clear {
    @synchronized ( self ) {
        [(NSMutableArray*)_sentMessages removeAllObjects];
    }
}

-(void)sendMIDIPacketList:(const MIDIPacketList *)packetList {
    @synchronized ( self ) {
//        printf("%3lu / %llu:\t%x\t(%c %lfs)\n",
//               _sentMessages.count,
//               packetList->packet[0].timeStamp,
//               packetList->packet[0].data[0],
//               packetList->packet[0].timeStamp > _lastTimestamp ? '+' : '-',
//               SEHostTicksToSeconds(packetList->packet[0].timeStamp > _lastTimestamp
//                                            ? packetList->packet[0].timeStamp - _lastTimestamp
//                                            : _lastTimestamp - packetList->packet[0].timeStamp));
        
        if ( packetList->packet[0].timeStamp != 0 && packetList->packet[0].timeStamp < SECurrentTimeInHostTicks() - SESecondsToHostTicks(0.02) ) {
            NSLog(@"MIDI packet has old timestamp %llu (%lf), should be >= now, %llu (%lf)",
                  packetList->packet[0].timeStamp,
                  SEHostTicksToSeconds(packetList->packet[0].timeStamp),
                  SECurrentTimeInHostTicks(),
                  SECurrentTimeInSeconds());
        }
        
        _lastTimestamp = packetList->packet[0].timeStamp;
        [(NSMutableArray*)_sentMessages addObject:[NSData dataWithBytes:packetList length:sizeof(MIDIPacketList) + ((packetList->numPackets-1) * sizeof(MIDIPacket))]];
    }
}

-(NSArray *)sortedSentMessages {
    return [_sentMessages sortedArrayUsingComparator:^NSComparisonResult(NSData * obj1, NSData * obj2) {
        const MIDIPacketList * packetList1 = [obj1 bytes];
        const MIDIPacketList * packetList2 = [obj2 bytes];
        
        return packetList1->packet[0].timeStamp < packetList2->packet[0].timeStamp ? NSOrderedAscending :
               packetList1->packet[0].timeStamp > packetList2->packet[0].timeStamp ? NSOrderedDescending :
               NSOrderedSame;
    }];
}

@end
