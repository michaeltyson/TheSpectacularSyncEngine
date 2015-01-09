//
//  SEMIDIClockReceiverCoreMIDIInterface.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#ifdef __cplusplus
extern "C" {
#endif

#import "SEMIDIClockReceiver.h"
#import <CoreMIDI/CoreMIDI.h>
    
@class SEMIDIClockReceiverCoreMIDISource;
    
/*!
 * Core MIDI utility class for SEMIDIClockReceiver
 *
 *  Use this utility class to provide a full Core MIDI implementation, if you
 *  do not have one already in place for your app. This class will automatically
 *  create Core MIDI ports and a virtual endpoint, named after your app's display
 *  name, for interaction with other apps.
 *
 *  Note that unlike the Core MIDI utility class for SEMIDIClockSender, it's not
 *  possible to integrate this class with an existing Core MIDI setup, due to the
 *  limitations of the Core MIDI API. If you already have a Core MIDI setup you
 *  wish to use, then you will need to handle connectivity and MIDI message receive
 *  manually, then  pass MIDI messages via SEMIDIClockReceiver's receivePacketList:.
 *
 *  Use the availableSources property to obtain a list of sources you can
 *  receive from (of type SEMIDIClockReceiverCoreMIDISource). Select the source
 *  you wish to use, then assign it to the source property to immediately begin 
 *  listening. If the source property is nil, then this class will automatically
 *  receive from the virtual destination (used to receive messages from other apps,
 *  when they send to your app's virtual endpoint).
 */
@interface SEMIDIClockReceiverCoreMIDIInterface : NSObject

/*!
 * Default initialiser
 *
 *  This initialiser will create the Core MIDI ports necessary to
 *  provide a complete implementation, if you do not have one within
 *  your app.
 *
 * @param receiver The SEMIDIClockReceiver instance
 */
-(instancetype)initWithReceiver:(SEMIDIClockReceiver*)receiver;

/*!
 * The SEMIDIClockReceiver instance
 */
@property (nonatomic, strong, readonly) SEMIDIClockReceiver * receiver;

/*!
 * The input port
 */
@property (nonatomic, readonly) MIDIPortRef inputPort;

/*!
 * The virtual destination
 */
@property (nonatomic, readonly) MIDIEndpointRef virtualDestination;

/*!
 * The list of available sources, an array of SEMIDIClockReceiverCoreMIDISource
 *
 *  This property issues key-value observing notifications, when new sources
 *  become available, or existing sources become unavailable.
 */
@property (nonatomic, strong, readonly) NSArray *availableSources;

/*!
 * The source to receive from
 */
@property (nonatomic, copy) SEMIDIClockReceiverCoreMIDISource *source;

@end
    
/*!
 * MIDI source utility class
 *
 *  This class represents a single Core MIDI source
 */
@interface SEMIDIClockReceiverCoreMIDISource : NSObject

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
