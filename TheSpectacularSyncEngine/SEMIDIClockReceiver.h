//
//  SEMIDIClockReceiver.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#ifdef __cplusplus
extern "C" {
#endif

#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import "SECommon.h"

extern NSString * const SEMIDIClockReceiverDidStartTempoSyncNotification; ///< Notification sent on main thread when tempo sync messages start
extern NSString * const SEMIDIClockReceiverDidStopTempoSyncNotification;  ///< Notification sent on main thread when tempo sync messages stop
extern NSString * const SEMIDIClockReceiverDidStartNotification;        ///< Notification sent on main thread when remote clock started
extern NSString * const SEMIDIClockReceiverDidStopNotification;         ///< Notification sent on main thread when remote clock stopped
extern NSString * const SEMIDIClockReceiverDidLiveSeekNotification;     ///< Notification sent on main thread when remote clock changed timeline position while playing
extern NSString * const SEMIDIClockReceiverDidChangeTempoNotification;  ///< Notification sent on main thread when remote clock changed tempo

extern NSString * const SEMIDIClockReceiverTimestampKey;               ///< Notification userinfo key containing global timestamp, in host ticks, for event
extern NSString * const SEMIDIClockReceiverTempoKey;                   ///< Notification userinfo key containing tempo, in beats per minute
    
/*!
 * MIDI Clock Receiver
 *
 *  This class takes care of receiving MIDI clock messages. It lets your app
 *  behave as a MIDI clock slave, and includes support for live tempo and timeline
 *  changes.
 *
 *  To use it, initialise it, and then pass MIDI messages to it via the
 *  receivePacketList: method, or use the provided categories to work with other
 *  libraries.
 *
 *  Then, watch or poll for changes, either via the provided notifications or
 *  key-value observing the 'tempo' property, or by getting the current state
 *  using the provided Objective-C and C interfaces. Only the C interface should
 *  be used from the realtime audio thread, to avoid priority inversion and audio
 *  glitches.
 */
@interface SEMIDIClockReceiver : NSObject

/*!
 * Default initialiser
 */
-(instancetype)init;

/*!
 * Receive a packet list
 *
 *  Unless you are using one of the provided compatability classes, use
 *  this method to provide SEMIDIClockReceiver with incoming MIDI messages.
 *  Any non-clock-related messages will simply be ignored.
 *
 *  Note that you should take care to avoid holding locks or otherwise taking
 *  too much time on the thread that handles incoming MIDI signals, or you risk
 *  destabilizing the incoming signal.
 *
 * @param packetList The incoming MIDI packet list
 */
-(void)receivePacketList:(const MIDIPacketList *)packetList;

/*!
 * Reset
 *
 *  Resets the state of this class; you should do this when changing sources.
 */
-(void)reset;

/*!
 * Determine if the receiver is currently actively receiving tempo synchronisation messages
 *
 *  Use this C function from the realtime audio thread to determine if the receiver
 *  is currently receiving clock messages. Note that this only indicates whether the tempo
 *  is being actively synchronised, not whether the clock is running. To determine this,
 *  use SEMIDIClockReceiverIsClockRunning.
 *
 * @param receiver The receiver
 * @return Whether the tempo is actively being synchronized
 */
BOOL SEMIDIClockReceiverIsReceivingTempo(__unsafe_unretained SEMIDIClockReceiver * receiver);

/*!
 * Determine if the remote clock is currently running
 *
 *  Use this C function from the realtime audio thread to determine if the remote clock
 *  is currently running, and the timeline is advancing.
 *
 * @param receiver The receiver
 * @return Whether the clock is running, and the timeline is advancing
 */
BOOL SEMIDIClockReceiverIsClockRunning(__unsafe_unretained SEMIDIClockReceiver * receiver);

/*!
 * Get the current timeline position, in beats
 *
 *  Use this C function from the realtime audio thread to determine the timeline
 *  position, in beats (that is, quarter notes - use SEBeatsToSeconds to convert to 
 *  seconds, if necessary), for the given global timestamp.
 *
 * @param receiver The receiver
 * @param time The global timestamp to retrieve the corresponding timeline position for
 * @return The position in the remote timeline for the provided global timestamp, in beats 
 */
double SEMIDIClockReceiverGetTimelinePosition(__unsafe_unretained SEMIDIClockReceiver * receiver, uint64_t time);

/*!
 * Get the current timeline position, in beats
 *
 *  An Objective-C convenience method, equivalent to SEMIDIClockReceiverGetTimelinePosition.
 *  Do not use this method on the realtime audio thread.
 *
 * @param time The global timestamp to retrieve the corresponding timeline position for
 * @return The position in the remote timeline for the provided global timestamp, in beats
 */
-(double)timelinePositionForTime:(uint64_t)timeInHostTicksOrZero;

/*!
 * Get the current remote tempo
 *
 *  Use this C function from the realtime audio thread to determine the tempo.
 *
 * @param receiver The receiver
 * @return The remote tempo, in beats per minute
 */
double SEMIDIClockReceiverGetTempo(__unsafe_unretained SEMIDIClockReceiver * receiver);

/*!
 * The current tempo
 *
 *  This gives the current tempo, in beats per minute. This is an Objective-C convenience
 *  property equivalent to SEMIDIClockReceiverGetTempo; do not use this property on a realtime audio
 *  thread.
 *
 *  This property provides key-value observing updates.
 */
@property (nonatomic, readonly) double tempo;

/*!
 * Whether the receiver is currently receiving tempo synchronization messages
 *
 *  This is an Objective-C convenience property equivalent to SEMIDIClockReceiverIsReceivingTempo;
 *  do not use this property on a realtime audio thread.
 *
 *  This property provides key-value observing updates.
 */
@property (nonatomic, readonly) BOOL receivingTempo;

/*!
 * Whether the remote clock is currently running
 *
 *  This is an Objective-C convenience property equivalent to SEMIDIClockReceiverIsClockRunning;
 *  do not use this property on a realtime audio thread.
 *
 *  This property provides key-value observing updates.
 */
@property (nonatomic, readonly) BOOL clockRunning;

/*!
 * Error indication for the incoming clock signal
 *
 *  This property gives an indication of the stability of the incoming
 *  signal, represented by the relative standard deviation of the observed
 *  samples (as a percentage).
 *
 *  Some sample values, determined via experimentation:
 *
 *  - A value of 0% represents a perfectly stable signal.
 *  - A value greater than around 0.01% will result in problems syncing a tempo
 *    to greater than 2 decimal places of accuracy (in BPM).
 *  - A value greater than around 0.1% will result in problems syncing a tempo
 *    to greater than 1 decimal place of accuracy.
 *  - A value greater than around 5% will result in problems syncing a
 *    tempo to whole numbers.
 *
 *  Note that this class will automatically apply rounding to estimated
 *  tempo values to varying precision levels based on this error, in order
 *  to minimise oscillation in calculated tempo.
 */
@property (nonatomic, readonly) double error;

@end

#ifdef __cplusplus
}
#endif
