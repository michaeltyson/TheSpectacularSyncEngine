//
//  SEMIDIClockSenderCoreMIDIInterface.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 1/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#ifdef __cplusplus
extern "C" {
#endif

#import "SEMIDIClockSender.h"
#import <CoreMIDI/CoreMIDI.h>

/*!
 * Core MIDI interface for SEMIDIClockSender
 *
 *  Use this utility class to provide a full Core MIDI implementation, if you
 *  do not have one already in place for your app, or to interface with your
 *  existing Core MIDI setup.
 *
 *  If you instantiate this class with the default initialiser, init, it will
 *  automatically create Core MIDI ports and a virtual endpoint, named after
 *  your app's display name, for interaction with other apps.
 *
 *  If you use the initWithOutputPort:virtualSource: initialiser, you can use
 *  your own Core MIDI port/endpoint, if you have an existing setup.
 *
 *  Either way, use the availableDestinations property to obtain a list of
 *  destinations you can send to (of type SEMIDIClockSenderCoreMIDIDestination).
 *  Select the destinations you wish to use, then assign them, within an array,
 *  to the destinations property to immediately begin sending.
 */
@interface SEMIDIClockSenderCoreMIDIInterface : NSObject <SEMIDIClockSenderInterface>

/*!
 * Default initialiser
 *
 *  This initialiser will create the Core MIDI ports necessary to
 *  provide a complete implementation, if you do not have one within
 *  your app.
 */
-(instancetype)init;

/*!
 * Initialise with existing ports
 *
 *  If you already have a Core MIDI implementation, you may use this
 *  initialiser to make this class use your existing ports.
 *
 * @param outputPort The MIDI output port to use (as created by MIDIOutputPortCreate)
 * @param virtualSource The MIDI virtual source to use (as created by MIDISourceCreate) - optional
 */
-(instancetype)initWithOutputPort:(MIDIPortRef)outputPort virtualSource:(MIDIEndpointRef)virtualSource;

/*!
 * The output port
 */
@property (nonatomic, readonly) MIDIPortRef outputPort;

/*!
 * The virtual source
 */
@property (nonatomic, readonly) MIDIEndpointRef virtualSource;

/*!
 * The list of available destinations, an array of SEMIDIClockSenderCoreMIDIDestination
 *
 *  This property issues key-value observing notifications, when new destinations
 *  become available, or existing destinations become unavailable.
 */
@property (nonatomic, strong, readonly) NSArray *availableDestinations;

/*!
 * The destinations to send to
 *
 *  This must be an array of SEMIDIClockSenderCoreMIDIDestination
 */
@property (copy) NSArray *destinations;

@end

/*!
 * MIDI destination utility class
 *
 *  This class represents a single Core MIDI destination
 */
@interface SEMIDIClockSenderCoreMIDIDestination : NSObject

/*!
 * The display name for the endpoint
 */
@property (nonatomic, strong, readonly) NSString * name;

/*!
 * The MIDI endpoint
 */
@property (nonatomic, readonly) MIDIEndpointRef endpoint;

@end

#ifdef __cplusplus
}
#endif
