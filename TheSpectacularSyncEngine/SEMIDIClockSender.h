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
 *  used to send outgoing messages, and provide a tempo via the tempo property. The sender
 *  will immediately begin sending ticks to sync the tempo. Optionally set the
 *  timelinePosition property to cue playback to a particular position in your app's 
 *  timeline. Call startAtTime: to start the clock and begin advancing the timeline.
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
 *  tempo property, ideally well in advance of starting the clock in order to provide
 *  ample time for convergence.
 *
 *  If you pass a zero timestamp (recommended), this method will determine the next safe
 *  timestamp for the start action, within the next few tens of milliseconds, and will
 *  return this timestamp to you. You should wait to start the timeline in your own app 
 *  until this time is reached, to ensure sync.
 *
 *  If you pass a non-zero timestamp that is within around a hundred milliseconds of the
 *  current time, you may experience some sync discrepancies for a little while after
 *  the remote clock is started. This is due to interference from scheduled ticks that
 *  this class has sent in advance, in order to overcome system congestion and latency.
 *
 *  If you are starting the clock anywhere but the beginning of your app's timeline,
 *  be sure to first assign a value to the timelinePosition property to cue playback
 *  position.
 *
 * @param applyTime The global timestamp at which to start the clock, in host ticks,
 *      or zero (recommended). See mach_absolute_time, or SECurrentTimeInHostTicks
 * @return The timestamp at which the start will occur. Your app should wait until this
 *      time before starting the local clock.
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
 *  It is recommended that you limit resolution to 16th notes (0.25). If you do so, and
 *  you provide a zero apply timestamp (recommended), then this method will automatically
 *  pick the soonest apply time that will result in a safe on-the-beat transition to the new
 *  position (within 1/24th of a beat).
 *
 *  Otherwise, specify an apply time in host ticks in order to precisely specify the global
 *  timestamp that corresponds to this timeline position change. The sender instance will 
 *  update the remote clock's position and offset the outgoing ticks to synchronize the change,
 *  but note that some short-term sync discrepancy may be experienced.
 *
 *  This method returns the apply time that you provided, or the one automatically determined.
 *  Your app should wait to update the timeline in your own app until this apply time is reached.
 *
 *  If the clock is not running when you call this method, it behaves identically to the
 *  assignment of the timelinePosition property.
 *
 * @param timelinePosition The new position in your app's timeline, in beats (that is, quarter 
 *      notes - use SESecondsToBeats to convert from seconds, if necessary)
 * @param applyTime The global timestamp at which to apply the timeline change, in host ticks
 *      or zero (recommended). See mach_absolute_time, or SECurrentTimeInHostTicks
 * @return The timestamp at which the position change will occur. Your app should wait until this
 *      time before changing the timeline position.
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
-(double)activeTimelinePositionForTime:(uint64_t)timestamp;

/*!
 * The current position in the timeline (in beats)
 *
 *  Use this property to cue playback to the given the timeline position, in beats 
 *  (that is, quarter notes - use SESecondsToBeats to convert from seconds, if necessary).
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
 *  Use this property to assign a new tempo; it will immediately be synced to the
 *  remote side by adjusting the rate at which clock ticks are transmitted.
 *
 *  Note that depending on the remote implementation, convergence to the new tempo
 *  may not be immediate, so it is recommended that you provide a tempo as far in
 *  advance of starting the clock as possible.
 *
 *  If you set this value to zero, the sender will cease sending clock messages.
 */
@property (nonatomic) double tempo;

/*!
 * Whether the clock has been started (read-only, key-value observable)
 */
@property (nonatomic, readonly) BOOL started;

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
