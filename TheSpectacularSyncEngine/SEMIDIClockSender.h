//
//  SEMIDIClockSender.h
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

@protocol SEMIDIClockSenderInterface;

/*!
 * MIDI Clock Sender
 *
 *  This class takes care of sending MIDI clock messages. It lets your app
 *  behave as a MIDI clock master, and includes support for live tempo and timeline
 *  changes.
 *
 *  To use it, initialise it with an object that implements SEMIDIClockSenderInterface,
 *  used to send outgoing messages. Then provide a tempo via the tempo property, and 
 *  call startAtTime: to start the clock and begin advancing the timeline.
 *
 *  Optionally, but to achieve the best user experience, use the suggested 'apply
 *  time' timestamps returned from startAtTime: and setActiveTimelinePosition:atTime:
 *  and set the sendClockTicksWhileTimelineStopped property to YES. This will enable
 *  this class to send clock ticks prior to starting the timeline, which allows
 *  supporting receivers to sync to the local tempo well in advance of timeline start.
 *  This avoids tempo adjustments that are audible.
 *
 *  Note that, due to the general lack of acceptable support for Song Position and
 *  Continue messages in apps and some hardware, use of the timeline position facilities
 *  of this class may have no effect in receivers with a limited implementation.
 */
@interface SEMIDIClockSender : NSObject

/*!
 * Initialise
 *
 *  Create an instance of this class.
 *
 *  @param senderInterface The sender interface, used for transmitting messages
 */
-(instancetype)initWithInterface:(id<SEMIDIClockSenderInterface>)senderInterface;

/*!
 * Start clock
 *
 *  The clock will be started. Make sure you have provided a tempo first, via the
 *  tempo property.
 *
 *  If you are starting the clock anywhere but the beginning of your app's timeline,
 *  be sure to first assign a value to the timelinePosition property to cue playback
 *  position. Note that due to generally poor support of Song Position/Continue in
 *  receivers, this may have no effect, however.
 *
 *  Optionally, but to achieve the best user experience, use the suggested 'apply
 *  time' timestamps returned from this method and set the sendClockTicksWhileTimelineStopped
 *  property to YES. This will enable this class to send clock ticks prior to starting
 *  the timeline, which allows supporting receivers to sync to the local tempo well 
 *  in advance of timeline start. This avoids tempo adjustments that are audible.
 *
 * @param applyTime The global timestamp at which to start the clock, in host ticks,
 *      or zero. See mach_absolute_time, or SECurrentTimeInHostTicks
 * @return The timestamp at which the start will occur. If you have set the
 *      sendClockTicksWhileTimelineStopped property to YES, your app must wait until
 *      this time before starting the local clock.
 */
-(uint64_t)startAtTime:(uint64_t)applyTime;

/*!
 * Stop clock
 *
 *  The clock will be stopped. Clock ticks will continue to be sent, to maintain
 *  tempo sync.
 *
 *  After stopping, the sender will reset its timeline to zero, so that the next
 *  call to startAtTime: will begin at zero unless you assign a value to the 
 *  timelinePosition property first.
 */
-(void)stop;

/*!
 * Move in the timeline while clock is running
 *
 *  See also the documentation for the timelinePosition property.
 *
 *  This method will cause the sender to send the new timeline position, and is designed for
 *  use while the clock is running (not recommended by the MIDI standard, but sometimes
 *  unavoidable, such as while continuously looping over a region).
 *
 *  Note that due to generally poor support of Song Position/Continue in receivers, this may
 *  have no effect.
 *
 *  Optionally, but to achieve the best user experience, use the suggested 'apply
 *  time' timestamps returned from this method and set the sendClockTicksWhileTimelineStopped
 *  property to YES.
 *
 *  If the clock is not running when you call this method, it behaves identically to the
 *  assignment of the timelinePosition property.
 *
 * @param timelinePosition The new position in your app's timeline, in beats (that is, quarter 
 *      notes - use SESecondsToBeats to convert from seconds, if necessary)
 * @param applyTime The global timestamp at which to apply the timeline change, in host ticks
 *      or zero (recommended). See mach_absolute_time, or SECurrentTimeInHostTicks
 * @return The timestamp at which the position change will occur. If you have set the
 *      sendClockTicksWhileTimelineStopped property to YES, your app must wait until
 *      this time before seeking in the local timeline.
 */
-(uint64_t)setActiveTimelinePosition:(double)timelinePosition atTime:(uint64_t)applyTime;

/*!
 * Get the current timeline position
 *
 *  Use this method while the clock is running in order to provide a global timestamp, and
 *  accurately determine the timeline position at that time. If the clock is not running,
 *  the return value will be the same as the value of the timelinePosition property.
 *
 * @param timestamp The global timestamp to retrieve the corresponding timeline position for, 
 *      in host ticks. See mach_absolute_time, or SECurrentTimeInHostTicks
 * @return The position in your app's timeline, in beats, for the provided global timestamp
 */
-(double)timelinePositionForTime:(uint64_t)timestamp;

/*!
 * Get the current timeline position, in beats
 *
 *  Use this C function from the realtime audio thread to determine the timeline
 *  position, in beats (that is, quarter notes - use SEBeatsToSeconds to convert to
 *  seconds, if necessary), for the given global timestamp.
 *
 *  You may use this method to keep track of the timeline while rendering, if you
 *  do not already have your own internal clock system, and you are not currently
 *  receiving clock messages from an external source.
 *
 * @param sender The sender
 * @param time The global timestamp to retrieve the corresponding timeline position for
 * @return The position in the remote timeline for the provided global timestamp, in beats
 */
double SEMIDIClockSenderGetTimelinePosition(__unsafe_unretained SEMIDIClockSender * sender, uint64_t time);

/*!
 * The current position in the timeline (in beats)
 *
 *  Assign a value to this property to cue playback to the given the timeline position, in beats
 *  (that is, quarter notes - use SESecondsToBeats to convert from seconds, if necessary).
 *
 *  Note that due to generally poor support of Song Position/Continue in receivers, this may
 *  have no effect.
 *
 *  Important: The MIDI standard recommends that the timeline position only be changed while 
 *  the clock is stopped, to avoid sync problems. When the clock is stopped, setting this 
 *  property will cue the playback position for when the clock is started using startAtTime:.
 *
 *  However, changing timeline position only while the clock is stopped may not always be
 *  feasible, as is the case when continuously looping over a region. In this case, you should
 *  use the setActiveTimelinePosition:atTime: method to provide a global timestamp at which to
 *  apply the position change.
 *
 *  To determine the sender instance's timeline position while the clock is running, use
 *  activeTimelinePositionForTime:, in order to provide a global timestamp for which to retrieve
 *  the position.
 */
@property (nonatomic) double timelinePosition;

/*!
 * The current tempo (beats per minute)
 *
 *  Use this property to assign a tempo - be sure to assign a tempo prior to starting the
 *  clock.
 */
@property (nonatomic) double tempo;

/*!
 * Whether the clock has been started (read-only, key-value observable)
 */
@property (nonatomic, readonly) BOOL started;

/*!
 * Whether to send clock ticks while timeline is stopped (default: NO)
 *
 *  If you take particular care to apply start/seek actions at the apply
 *  timestamps provided by this class's startAtTime: and 
 *  setActiveTimelinePosition:atTime: methods, you may choose to set this
 *  property to YES to enable this class to send clock ticks while your
 *  timeline is stopped.
 *
 *  This allows receivers to sync to your app's tempo well in advance of a
 *  timeline start, for a smoother user experience.
 *
 *  Important note: If you are not taking steps to use this class's
 *  suggested apply timestamps, setting this property to YES will cause
 *  synchronisation discrepancies. Use with caution.
 */
@property (nonatomic) BOOL sendClockTicksWhileTimelineStopped;

/*!
 * The interface, passed during initialisation
 */
@property (nonatomic, strong, readonly) id<SEMIDIClockSenderInterface> senderInterface;

@end

/*!
 * Sender interface protocol
 *
 *  Implement this protocol (or use one of the provided classes that do so) to provide
 *  SEMIDIClockSender with the facility to send MIDI messages.
 */
@protocol SEMIDIClockSenderInterface <NSObject>

/*!
 * Send a MIDI packet list
 *
 *  Your object should transmit the given packet list to the required destinations.
 *
 *  This method may be called on different threads, but not concurrently: SEMIDIClockSender
 *  takes steps to avoid concurrent use of this method. However, you should take care of
 *  concurrency issues when making changes to this object (such as mutating a destinations 
 *  array). It's acceptable to use synchronization primitives (like @synchronize) for this.
 *
 * @param packetList The MIDI packet list to send
 */
-(void)sendMIDIPacketList:(const MIDIPacketList *)packetList;

@end

#ifdef __cplusplus
}
#endif
