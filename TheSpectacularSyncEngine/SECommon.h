//
//  SECommon.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#ifndef SECommon_h
#define SECommon_h

#ifdef __cplusplus
extern "C" {
#endif

#import <Foundation/Foundation.h>
#import <mach/mach_time.h>

typedef enum {
    SEMIDIMessageSongPosition  = 0xF2,
    SEMIDIMessageClock         = 0xF8,
    SEMIDIMessageClockTick     = 0xF9,
    SEMIDIMessageClockStart    = 0xFA,
    SEMIDIMessageClockStop     = 0xFC,
    SEMIDIMessageContinue      = 0xFB,
} SEMIDIMessage;

#define SEMIDITicksPerBeat              24
#define SEMIDITicksPerSongPositionBeat  6

/*!
 * Get current global timestamp, in host ticks
 */
uint64_t SECurrentTimeInHostTicks();

/*!
 * Get current global timestamp, in seconds
 */
NSTimeInterval SECurrentTimeInSeconds();

/*!
 * Convert time in seconds to host ticks
 *
 * @param seconds The time in seconds
 * @return The time in host ticks
 */
uint64_t SESecondsToHostTicks(NSTimeInterval seconds);

/*!
 * Convert time in host ticks to seconds
 *
 * @param ticks The time in host ticks
 * @return The time in seconds
 */
NSTimeInterval SEHostTicksToSeconds(uint64_t ticks);

/*!
 * Convert seconds to beats (quarter notes)
 *
 * @param seconds The time in seconds
 * @param tempo The current tempo, in beats per minute
 * @return The time in beats for the given tempo
 */
double SESecondsToBeats(NSTimeInterval seconds, double tempo);

/*!
 * Convert beats (quarter notes) to seconds
 *
 * @param beats The time in beats
 * @param tempo The current tempo, in beats per minute
 * @return The time in seconds
 */
NSTimeInterval SEBeatsToSeconds(double beats, double tempo);

/*!
 * Convert host ticks to beats (quarter notes)
 *
 * @param ticks The time in host ticks
 * @param tempo The current tempo, in beats per minute
 * @return The time in beats for the given tempo
 */
double SEHostTicksToBeats(uint64_t ticks, double tempo);

/*!
 * Convert beats (quarter notes) to host ticks
 *
 * @param beats The time in beats
 * @param tempo The current tempo, in beats per minute
 * @return The time in host ticks
 */
uint64_t SEBeatsToHostTicks(double beats, double tempo);

/*!
 * Weak-retaining proxy for retain cycle-free use of NSTimer
 */
@interface SEWeakRetainingProxy : NSProxy
-(instancetype)initWithTarget:(id)target;
@property (nonatomic, weak) id target;
@end
    
#ifdef __cplusplus
}
#endif
    
#endif
