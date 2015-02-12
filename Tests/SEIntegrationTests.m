//
//  SEIntegrationTests.m
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 31/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "SEMIDIClockReceiver.h"
#import "SEMIDIClockSender.h"
#import "SETestObserver.h"

@interface SEMIDIClockSenderPassthroughInterface : NSObject <SEMIDIClockSenderInterface>
@property (nonatomic) SEMIDIClockReceiver * receiver;
@end

@interface SEIntegrationTests : XCTestCase
@property (nonatomic) SEMIDIClockSender * sender;
@property (nonatomic) SEMIDIClockReceiver * receiver;
@property (nonatomic) SEMIDIClockSenderPassthroughInterface * interface;
@property (nonatomic) SETestObserver * observer;
@end

@implementation SEIntegrationTests

- (void)setUp {
    [super setUp];
    
    self.interface = [SEMIDIClockSenderPassthroughInterface new];
    self.sender = [[SEMIDIClockSender alloc] initWithInterface:_interface];
    self.receiver = [SEMIDIClockReceiver new];
    _interface.receiver = _receiver;
    
    self.observer = [SETestObserver new];
    
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

- (void)tearDown {
    [[NSNotificationCenter defaultCenter] removeObserver:_observer];
    for ( NSString * key in @[ @"receivingTempo", @"clockRunning", @"tempo"] ) {
        [_receiver removeObserver:_observer forKeyPath:key];
    }
    self.sender = nil;
    self.receiver = nil;
    self.interface = nil;
    self.observer = nil;
    [super tearDown];
}

- (void)testSimpleSync {
    _sender.tempo = 125;
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    
    XCTAssertTrue(_receiver.receivingTempo);
    XCTAssertEqual(_receiver.tempo, _sender.tempo);
    XCTAssertFalse(_receiver.clockRunning);
    XCTAssertEqual([_receiver timelinePositionForTime:SECurrentTimeInHostTicks()], 0);
    XCTAssertEqual(_observer.observations.count, 2);
    XCTAssertEqualObjects(_observer.observations[0], @"receivingTempo");
    XCTAssertEqualObjects(_observer.observations[1], @"tempo");
    XCTAssertEqual(_observer.notifications.count, 2);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[0]).name, SEMIDIClockReceiverDidStartTempoSyncNotification);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[1]).name, SEMIDIClockReceiverDidChangeTempoNotification);
    XCTAssertEqual([((NSNotification*)_observer.notifications[1]).userInfo[SEMIDIClockReceiverTempoKey] doubleValue], _sender.tempo);
    [_observer reset];
    
    uint64_t startTime = [_sender startAtTime:0];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    
    XCTAssertTrue(_receiver.clockRunning);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:startTime], 0, SESecondsToHostTicks(1.0e-6));
    XCTAssertEqual(_observer.observations.count, 1);
    XCTAssertEqualObjects(_observer.observations[0], @"clockRunning");
    XCTAssertEqual(_observer.notifications.count, 1);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[0]).name, SEMIDIClockReceiverDidStartNotification);
    XCTAssertEqual([((NSNotification*)_observer.notifications[0]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], startTime);
    [_observer reset];
    
    double newTimelinePosition = 16;
    uint64_t seekTime = [_sender setActiveTimelinePosition:newTimelinePosition atTime:0];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:seekTime], newTimelinePosition, 1.0e-6);
    XCTAssertEqual(_observer.observations.count, 0);
    XCTAssertEqual(_observer.notifications.count, 1);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[0]).name, SEMIDIClockReceiverDidLiveSeekNotification);
    XCTAssertEqual([((NSNotification*)_observer.notifications[0]).userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue], seekTime);
    
    XCTAssertEqual(_receiver.error, 0);
}

- (void)testStartWithoutPrecedingTempoTicks {
    uint64_t startTime = SECurrentTimeInHostTicks();
    _sender.tempo = 125;
    [_sender startAtTime:startTime];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    
    XCTAssertTrue(_receiver.clockRunning);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:startTime], 0, SESecondsToHostTicks(1.0e-6));
    XCTAssertEqual(_observer.observations.count, 3);
    XCTAssertEqualObjects(_observer.observations[0], @"receivingTempo");
    XCTAssertEqualObjects(_observer.observations[1], @"tempo");
    XCTAssertEqualObjects(_observer.observations[2], @"clockRunning");
    XCTAssertEqual(_observer.notifications.count, 3);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[0]).name, SEMIDIClockReceiverDidStartTempoSyncNotification);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[1]).name, SEMIDIClockReceiverDidChangeTempoNotification);
    XCTAssertEqualObjects(((NSNotification*)_observer.notifications[2]).name, SEMIDIClockReceiverDidStartNotification);
    
    XCTAssertEqual(_receiver.error, 0);
}

- (void)testStartWithOffset {
    _sender.tempo = 125;
    double initialTimelinePosition = 10;
    _sender.timelinePosition = initialTimelinePosition;
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    
    uint64_t startTime = [_sender startAtTime:0];
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    
    XCTAssertTrue(_receiver.clockRunning);
    XCTAssertEqualWithAccuracy([_receiver timelinePositionForTime:startTime], initialTimelinePosition, SESecondsToHostTicks(1.0e-6));
    
    XCTAssertEqual(_receiver.error, 0);
}

@end

@implementation SEMIDIClockSenderPassthroughInterface
-(void)sendMIDIPacketList:(const MIDIPacketList *)packetList {
    SEMIDIClockReceiverReceivePacketList(_receiver, packetList);
}
@end
