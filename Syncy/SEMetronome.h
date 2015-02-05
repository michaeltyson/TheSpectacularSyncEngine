//
//  SEMetronome.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

@import Foundation;
#import "SEAudioEngine.h"

extern NSString * const SEMetronomeDidStartNotification;
extern NSString * const SEMetronomeDidStopNotification;
extern NSString * const SEMetronomeDidChangeTimelineNotification;
extern NSString * const SEMetronomeDidChangeTempoNotification;

extern NSString * const SENotificationTimestampKey;
extern NSString * const SENotificationPositionKey;
extern NSString * const SENotificationTempoKey;

@interface SEMetronome : NSObject <SEAudioEngineAudioProvider>

-(void)startAtTime:(uint64_t)applyTime;
-(void)stop;

-(void)setTimelinePosition:(double)timelinePosition atTime:(uint64_t)applyTime;
-(double)timelinePositionForTime:(uint64_t)timestamp;

@property (nonatomic) double tempo;
@property (nonatomic, readonly) BOOL started;

@end
