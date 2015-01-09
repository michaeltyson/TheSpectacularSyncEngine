//
//  DSMetronome.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

@import Foundation;
#import "DSAudioEngine.h"

extern NSString * const DSMetronomeDidStartNotification;
extern NSString * const DSMetronomeDidStopNotification;
extern NSString * const DSMetronomeDidChangeTimelineNotification;
extern NSString * const DSMetronomeDidChangeTempoNotification;

extern NSString * const DSNotificationTimestampKey;
extern NSString * const DSNotificationPositionKey;
extern NSString * const DSNotificationTempoKey;

@interface DSMetronome : NSObject <DSAudioEngineAudioProvider>

-(void)startAtTime:(uint64_t)applyTime;
-(void)stop;

-(void)setTimelinePosition:(double)timelinePosition atTime:(uint64_t)applyTime;
-(double)timelinePositionForTime:(uint64_t)timestamp;

@property (nonatomic) double tempo;
@property (nonatomic, readonly) BOOL started;

@end
