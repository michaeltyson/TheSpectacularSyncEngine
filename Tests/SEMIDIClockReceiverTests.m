//
//  SEMIDIClockReceiverTests.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 1/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "SEMIDIClockReceiver.h"
#import <CoreMIDI/CoreMIDI.h>

// Gaussian random code
typedef struct {
    double mean;
    double stddev;
    double min;
    double max;
    BOOL hasSecond;
    double second;
} TPMCGaussianRandom;

static void TPMCGaussianRandomInit(TPMCGaussianRandom * gaussianRandom, double mean, double stddev, double min, double max) {
    memset(gaussianRandom, 0, sizeof(TPMCGaussianRandom));
    gaussianRandom->mean = mean;
    gaussianRandom->stddev = stddev;
    gaussianRandom->min = min;
    gaussianRandom->max = max;
}

static double TPMCGaussianRandomNext(TPMCGaussianRandom * gaussianRandom) {
    if( gaussianRandom->hasSecond ) {
        gaussianRandom->hasSecond = NO;
        return gaussianRandom->second;
    }
    
    float x1;
    float x2;
    float w;
    do {
        x1 = 2.0f * ((double)random() / (double)RAND_MAX) - 1.0f;
        x2 = 2.0f * ((double)random() / (double)RAND_MAX) - 1.0f;
        w = x1 * x1 + x2 * x2;
    }
    while ( w >= 1.0f );
    
    w = (float)sqrt( (-2.0f * (float)log( w ) ) / w );
    
    double first           = (x1 * w) * gaussianRandom->stddev + gaussianRandom->mean;
    gaussianRandom->second = (x2 * w) * gaussianRandom->stddev + gaussianRandom->mean;
    
    if ( first < gaussianRandom->min ) first = gaussianRandom->min;
    if ( first > gaussianRandom->max ) first = gaussianRandom->max;
    if ( gaussianRandom->second < gaussianRandom->min ) gaussianRandom->second = gaussianRandom->min;
    if ( gaussianRandom->second > gaussianRandom->max ) gaussianRandom->second = gaussianRandom->max;
    
    gaussianRandom->hasSecond = true;
    
    return first;
}

@interface SEMIDIClockReceiverObserver : NSObject
-(void)reset;
-(void)notification:(NSNotification*)notification;
@property (nonatomic) NSArray *observations;
@property (nonatomic) NSArray *notifications;
@end

@interface SEMIDIClockReceiverTests : XCTestCase
@property SEMIDIClockReceiver * receiver;
@property SEMIDIClockReceiverObserver * observer;
@end

@implementation SEMIDIClockReceiverTests

-(void)setUp {
    [super setUp];
    
    self.receiver = [SEMIDIClockReceiver new];
    
    self.observer = [SEMIDIClockReceiverObserver new];
    
    for ( NSString * key in @[ @"receivingTempo", @"clockRunning", @"tempo"] ) {
        [_receiver addObserver:_observer forKeyPath:key options:0 context:NULL];
    }
    for ( NSString * notification in @[ SEMIDIClockReceiverDidStartTempoSyncNotification,
                                        SEMIDIClockReceiverDidChangeTempoNotification,
                                        SEMIDIClockReceiverDidStopTempoSyncNotification,
                                        SEMIDIClockReceiverDidStartNotification,
                                        SEMIDIClockReceiverDidLiveSeekNotification,
                                        SEMIDIClockReceiverDidStopNotification ]) {
        [[NSNotificationCenter defaultCenter] addObserver:_observer selector:@selector(notification:) name:notification object:_receiver];
    }
}

-(void)tearDown {
    [super tearDown];
    
    [[NSNotificationCenter defaultCenter] removeObserver:_observer];
    for ( NSString * key in @[ @"receivingTempo", @"clockRunning", @"tempo"] ) {
        [_receiver removeObserver:_observer forKeyPath:key];
    }
    
    self.receiver = nil;
    self.observer = nil;
}

-(void)testReceive {
    uint64_t time = SECurrentTimeInHostTicks();
    uint64_t startTime = time;
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125 bpm
    double tempo = 125.0;
    int tickCount = 24;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify state change
    XCTAssertTrue(_receiver.receivingTempo);
    XCTAssertFalse(_receiver.clockRunning);
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    XCTAssertEqual([_receiver timelinePositionForTime:time], 0.0);
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertEqual(_observer.observations.count, 2);
    XCTAssertEqualObjects(_observer.observations[0], @"receivingTempo");
    XCTAssertEqualObjects(_observer.observations[1], @"tempo");
    XCTAssertEqual(_observer.notifications.count, 2);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[0]).name, SEMIDIClockReceiverDidStartTempoSyncNotification);
    XCTAssertLessThanOrEqual([((NSNotification*)_observer.notifications[0]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], startTime + tickDuration*4);
    XCTAssertGreaterThanOrEqual([((NSNotification*)_observer.notifications[0]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], startTime);
    XCTAssertEqual([((NSNotification*)_observer.notifications[0]).userInfo[SEMIDIClockReceiverTempoKey] doubleValue], tempo);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[1]).name, SEMIDIClockReceiverDidChangeTempoNotification);
    XCTAssertLessThanOrEqual([((NSNotification*)_observer.notifications[1]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], startTime + tickDuration*4);
    XCTAssertGreaterThanOrEqual([((NSNotification*)_observer.notifications[1]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], startTime);
    XCTAssertEqual([((NSNotification*)_observer.notifications[1]).userInfo[SEMIDIClockReceiverTempoKey] doubleValue], tempo);
    [_observer reset];
    
    // Send clock start
    uint64_t clockStartTime = time;
    MIDIPacket *packet = MIDIPacketListInit(packetList);
    Byte startMessage[] = { SEMIDIMessageClockStart };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time-1, sizeof(startMessage), startMessage);
    [_receiver receivePacketList:packetList];
    
    // Shouldn't get any notifications just yet
    XCTAssertFalse(_receiver.clockRunning);
    XCTAssertEqual([_receiver timelinePositionForTime:clockStartTime + SESecondsToHostTicks(2.0)], 0);
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertTrue(_observer.observations.count == 0);
    XCTAssertTrue(_observer.notifications.count == 0);
    
    // Send next tick to apply
    packet = MIDIPacketListInit(packetList);
    Byte tickMessage[] = { SEMIDIMessageClock };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
    [_receiver receivePacketList:packetList];
    
    // Verify state change
    XCTAssertTrue(_receiver.clockRunning);
    XCTAssertEqual([_receiver timelinePositionForTime:clockStartTime], 0);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:clockStartTime + SEBeatsToHostTicks(4.0, tempo)], 4.0, 1.0e-6);
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertEqual(_observer.observations.count, 1);
    XCTAssertEqualObjects(_observer.observations[0], @"clockRunning");
    XCTAssertEqual(_observer.notifications.count, 1);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[0]).name, SEMIDIClockReceiverDidStartNotification);
    XCTAssertEqual([((NSNotification*)_observer.notifications[0]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], clockStartTime);
    [_observer reset];
    
    // Send more ticks
    time += tickDuration;
    for ( int i=0; i<tickCount-1; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo and timeline correct, still
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:clockStartTime], 0, 1.0e-6);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:time], SEHostTicksToBeats(tickCount * tickDuration, tempo), 1.0e-6);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:clockStartTime + SEBeatsToHostTicks(4.0, tempo)], 4.0, 1.0e-6);
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Send position change
    double newPosition = 5.25;
    uint64_t newPositionChangeTime = time;
    packet = MIDIPacketListInit(packetList);
    int beats = round((newPosition * SEMIDITicksPerBeat) / (double)SEMIDITicksPerSongPositionBeat);
    Byte positionChangeMessage[] = { SEMIDIMessageSongPosition, beats & 0x7F, (beats >> 7) & 0x7F };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time-1, sizeof(positionChangeMessage), positionChangeMessage);
    [_receiver receivePacketList:packetList];
    
    // Should be no change yet
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:clockStartTime + SEBeatsToHostTicks(4.0, tempo)], 4.0, 1.0e-6);
    
    // Send next tick to apply
    packet = MIDIPacketListInit(packetList);
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
    [_receiver receivePacketList:packetList];
    
    // Verify state change
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:newPositionChangeTime], newPosition, 1.0e-6);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:newPositionChangeTime + SEBeatsToHostTicks(1, tempo)], newPosition + 1.0, 1.0e-6);
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertEqual(_observer.observations.count, 0);
    XCTAssertEqual(_observer.notifications.count, 1);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[0]).name, SEMIDIClockReceiverDidLiveSeekNotification);
    XCTAssertEqual([((NSNotification*)_observer.notifications[0]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], time);
    [_observer reset];
    
    // Send more ticks
    time += tickDuration;
    for ( int i=0; i<tickCount-1; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify timeline and tempo
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:newPositionChangeTime], newPosition, 1.0e-6);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:newPositionChangeTime + SEBeatsToHostTicks(1, tempo)], newPosition + 1.0, 1.0e-6);
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Send clock stop
    packet = MIDIPacketListInit(packetList);
    Byte stopMessage[] = { SEMIDIMessageClockStop };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(stopMessage), stopMessage);
    [_receiver receivePacketList:packetList];

    // Verify state change
    XCTAssertFalse(_receiver.clockRunning);
    XCTAssertTrue(_receiver.receivingTempo);
    double midiBeatsPerBeat = (double)SEMIDITicksPerBeat / (double)SEMIDITicksPerSongPositionBeat;
    double stoppedPosition = floor((newPosition + SEHostTicksToBeats(time - newPositionChangeTime, tempo)) * midiBeatsPerBeat) / midiBeatsPerBeat;
    XCTAssertEqual([_receiver timelinePositionForTime:time], stoppedPosition);
    XCTAssertEqual([_receiver timelinePositionForTime:time + SEBeatsToHostTicks(1, tempo)], stoppedPosition);
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertEqual(_observer.observations.count, 1);
    XCTAssertEqualObjects(_observer.observations[0], @"clockRunning");
    XCTAssertEqual(_observer.notifications.count, 1);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[0]).name, SEMIDIClockReceiverDidStopNotification);
    XCTAssertEqual([((NSNotification*)_observer.notifications[0]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], time);
}

-(void)testTempoChange {
    
    uint64_t time = SECurrentTimeInHostTicks();
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125 bpm
    double tempo = 125.0;
    int tickCount = 24;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Send some ticks at 180 bpm
    tempo = 180;
    tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    tickCount = 10;
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify new tempo correct
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
}


-(void)testTempoChangeWithTimeline {
    
    uint64_t time = SECurrentTimeInHostTicks();
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125 bpm
    double tempo = 125.0;
    int tickCount = 24;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Start clock
    MIDIPacket *packet = MIDIPacketListInit(packetList);
    Byte startMessage[] = { SEMIDIMessageClockStart };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time-1, sizeof(startMessage), startMessage);
    [_receiver receivePacketList:packetList];
    
    // Send more ticks
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify first position
    double firstPosition = (double)tickCount / (double)SEMIDITicksPerBeat;
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:time], firstPosition, 1.0e-6);
    
    // Change tempo
    tempo = 250;
    tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    tickCount = 24;
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify second position
    double secondPosition = firstPosition + ((double)tickCount / (double)SEMIDITicksPerBeat);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:time], secondPosition, 1.0e-6);
    
    // Verify new tempo correct
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
}

-(void)testNonIntegralPositionChange {
    
    uint64_t time = SECurrentTimeInHostTicks();
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125 bpm
    double tempo = 125.0;
    int tickCount = 24;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Start clock
    uint64_t clockStartTime = time;
    MIDIPacket *packet = MIDIPacketListInit(packetList);
    Byte startMessage[] = { SEMIDIMessageClockStart };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time-1, sizeof(startMessage), startMessage);
    [_receiver receivePacketList:packetList];
    
    // Send some more ticks
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo constant still
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Verify position
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:time], SEHostTicksToBeats(tickCount * tickDuration, tempo), 1.0e-6);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:clockStartTime + SEBeatsToHostTicks(1.0, tempo)], 1.0, 1.0e-6);
    
    // Send position change, for non-integral number of MIDI beats
    double newPosition = 5.21;
    uint64_t newPositionChangeTime = time;
    packet = MIDIPacketListInit(packetList);
    int beats = ceil((newPosition * SEMIDITicksPerBeat) / (double)SEMIDITicksPerSongPositionBeat);
    Byte positionChangeMessage[] = { SEMIDIMessageSongPosition, beats & 0x7F, (beats >> 7) & 0x7F };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time-1, sizeof(positionChangeMessage), positionChangeMessage);
    [_receiver receivePacketList:packetList];
    
    // Adjust next tick time to factor in non-integral amount
    uint64_t beatDuration = tickDuration * SEMIDITicksPerSongPositionBeat;
    uint64_t modulus = SEBeatsToHostTicks(newPosition, tempo) % beatDuration;
    uint64_t threshold = SESecondsToHostTicks(1.0e-6);
    if ( modulus > threshold && beatDuration - modulus > threshold ) {
        uint64_t beatOffset = beatDuration - modulus;
        time += beatOffset;
    }
    
    // Send some more ticks
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo constant still
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Verify position
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:newPositionChangeTime + SEBeatsToHostTicks(1.0, tempo)], newPosition + 1.0, 1.0e-6);
}

-(void)testOutlierTolerance {
    
    uint64_t time = SECurrentTimeInHostTicks();
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125 bpm
    double tempo = 125.0;
    int tickCount = 24;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Send one outlier tick
    MIDIPacket *packet = MIDIPacketListInit(packetList);
    Byte tickMessage[] = { SEMIDIMessageClock };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time + (tickDuration * 0.25), sizeof(tickMessage), tickMessage);
    [_receiver receivePacketList:packetList];
    
    // Verify tempo constant still
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Send a few more ticks
    tickCount = 24;
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo constant still
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
}

-(void)testAbsentTimestampTolerance {
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125 bpm
    double tempo = 125.0;
    int tickCount = 48;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    uint64_t time = SECurrentTimeInHostTicks();
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, 0, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
        mach_wait_until(time + tickDuration);
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-6);
    
    // Verify not too many tempo updates
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertLessThanOrEqual(_observer.notifications.count, 3);
}

-(void)testNonIntegralTempo {
    uint64_t time = SECurrentTimeInHostTicks();
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125.31 bpm
    double tempo = 125.31;
    int tickCount = 24;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time, sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-6);
}

-(void)testJitterTempoToleranceIntegers {
    double standardDeviationPercent = 4.0;
    
    uint64_t time = SECurrentTimeInHostTicks();
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125 bpm, with random delays
    double tempo = 125.0;
    int tickCount = 24;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    TPMCGaussianRandom gauss;
    TPMCGaussianRandomInit(&gauss, 0, tickDuration * (standardDeviationPercent / 100.0), 0, DBL_MAX);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time + TPMCGaussianRandomNext(&gauss), sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
     XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Send more ticks
    tickCount = 72;
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time + TPMCGaussianRandomNext(&gauss), sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Verify not too many tempo updates
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertLessThanOrEqual(_observer.notifications.count, 3);
    [_observer reset];
    
    // Change tempo
    tempo = 160;
    tickCount = 16;
    tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    TPMCGaussianRandomInit(&gauss, 0, tickDuration * (standardDeviationPercent / 100.0), 0, DBL_MAX);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time + TPMCGaussianRandomNext(&gauss), sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify rapid approximate convergence to new tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 2);
    
    // More ticks
    tickCount = 48;
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time + TPMCGaussianRandomNext(&gauss), sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Verify not too many tempo updates
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertLessThanOrEqual(_observer.notifications.count, 2);
    [_observer reset];
}

-(void)testJitterTempoToleranceOneDecimalPlace {
    // Try a 1-decimal-place tempo, with moderate error
    double tempo = 120.6;
    int tickCount = 96;
    double standardDeviationPercent = 0.09;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    TPMCGaussianRandom gauss;
    TPMCGaussianRandomInit(&gauss, 0, tickDuration * (standardDeviationPercent / 100.0), 0, DBL_MAX);
    uint64_t time = SECurrentTimeInHostTicks();
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, time + TPMCGaussianRandomNext(&gauss), sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:&packetList];
    }
    
    // Verify tempo, rounded to closest 0.1
    XCTAssertEqualWithAccuracy(_receiver.tempo, round(tempo / 0.1) * 0.1, 1.0e-9);
    
    // Verify not too many tempo updates
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertLessThanOrEqual(_observer.notifications.count, 3);
    [_observer reset];
}

-(void)testJitterTempoToleranceTwoDecimalPlaces {
    // Try a 2-decimal place tempo, with small error
    double tempo = 156.23;
    int tickCount = 96;
    double standardDeviationPercent = 0.009;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    TPMCGaussianRandom gauss;
    TPMCGaussianRandomInit(&gauss, 0, tickDuration * (standardDeviationPercent / 100.0), 0, DBL_MAX);
    uint64_t time = SECurrentTimeInHostTicks();
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, time + TPMCGaussianRandomNext(&gauss), sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:&packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Verify not too many tempo updates
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertLessThanOrEqual(_observer.notifications.count, 2);
    [_observer reset];
}

-(void)testJitterTimelineTolerance {
    double standardDeviationPercent = 4.0;
    
    uint64_t time = SECurrentTimeInHostTicks();
    char packetListSpace[sizeof(MIDIPacketList) + sizeof(MIDIPacket)];
    MIDIPacketList *packetList = (MIDIPacketList*)packetListSpace;
    
    // Send some ticks, for 125 bpm, with random delays
    double tempo = 125.0;
    int tickCount = 24;
    uint64_t tickDuration = SESecondsToHostTicks((60.0 / tempo) / SEMIDITicksPerBeat);
    TPMCGaussianRandom gauss;
    TPMCGaussianRandomInit(&gauss, 0, tickDuration * (standardDeviationPercent / 100.0), 0, DBL_MAX);
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time + TPMCGaussianRandomNext(&gauss), sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify tempo
    XCTAssertEqualWithAccuracy(_receiver.tempo, tempo, 1.0e-9);
    
    // Start clock
    uint64_t clockStartTime = time;
    MIDIPacket *packet = MIDIPacketListInit(packetList);
    Byte startMessage[] = { SEMIDIMessageClockStart };
    packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time-1, sizeof(startMessage), startMessage);
    [_receiver receivePacketList:packetList];
    
    // Send more ticks
    tickCount = 72;
    for ( int i=0; i<tickCount; i++, time += tickDuration ) {
        MIDIPacket *packet = MIDIPacketListInit(packetList);
        Byte tickMessage[] = { SEMIDIMessageClock };
        packet = MIDIPacketListAdd(packetList, sizeof(packetListSpace), packet, time + TPMCGaussianRandomNext(&gauss), sizeof(tickMessage), tickMessage);
        [_receiver receivePacketList:packetList];
    }
    
    // Verify timeline position
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:clockStartTime], 0, 1.0e-9);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:time], (double)tickCount / (double)SEMIDITicksPerBeat, 1.0e-3);
    

}

@end

@implementation SEMIDIClockReceiverObserver

-(instancetype)init {
    if ( !(self = [super init]) ) return nil;
    
    self.observations = [NSMutableArray array];
    self.notifications = [NSMutableArray array];
    
    return self;
}

-(void)reset {
    [(NSMutableArray*)_notifications removeAllObjects];
    [(NSMutableArray*)_observations removeAllObjects];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [(NSMutableArray*)_observations addObject:keyPath];
}

-(void)notification:(NSNotification*)notification {
    [(NSMutableArray*)_notifications addObject:notification];
}

@end
