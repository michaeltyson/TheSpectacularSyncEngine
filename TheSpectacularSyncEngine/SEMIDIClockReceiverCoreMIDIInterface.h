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
#import "SEMIDIEndpoint.h"
    
/*!
 * Core MIDI utility class for SEMIDIClockReceiver
 *
 *  Use this utility class to provide a full Core MIDI implementation, if you
 *  do not have one already in place for your app, or to interface with your
 *  existing Core MIDI setup.
 *
 *  If you instantiate this class with the default initialiser, initWithReceiver:,
 *  it will automatically create Core MIDI ports and a virtual endpoint, named after
 *  your app's display name, for interaction with other apps.
 *
 *  If you have your own Core MIDI implementation already, use the
 *  initWithOutputPort:virtualSource: initialiser, which will stop this class
 *  creating its own port and endpoint, and allow it to use your existing ones. Then
 *  forward incoming MIDI messages to this class using the receivePacketList:fromEndpoint:
 *  method. Note that assigning a value to the source property will cause this
 *  class to automatically connect the source endpoint, using MIDIPortConnectSource,
 *  and disconnect any previously assigned sources using MIDIPortDisconnectSource.
 *
 *  Use the availableSources property to obtain a list of sources you can
 *  receive from (of type SEMIDIEndpoint). Select the source
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
 * Custom initialiser
 *
 *  If you already have your own MIDI setup, you may use this initialiser
 *  to prevent this class from creating its own port and Virtual MIDI endpoint.
 *  You must then modify your MIDI setup to forward all incoming message to this
 *  class.
 *
 * @param receiver The SEMIDIClockReceiver instance
 * @param inputPort The MIDI input port to use (as created by MIDIInputPortCreate)
 * @param virtualDestination The MIDI virtual destination to use (as created by MIDIDestinationCreate)
 */
-(instancetype)initWithReceiver:(SEMIDIClockReceiver*)receiver inputPort:(MIDIPortRef)inputPort virtualDestination:(MIDIEndpointRef)virtualDestination;

/*!
 * Receive a packet list, if not using the built-in MIDI implementation
 *
 *  If you are using this class with your own implementation, and have
 *  thus initialised it with initWithReceiver:inputPort:virtualDestination:,
 *  then you must use this method to forward incoming MIDI messages to this
 *  class. Pass the incoming packet list, as well as the originating
 *  MIDI endpoint (or zero to indicate the virtual MIDI destination).
 *
 *  Do not use this method if you initialised this class with the
 *  default initWithReceiver: initialiser.
 *
 * @param packetList The incoming MIDI packet list
 * @param endpoint The originating MIDI endpoint
 */
-(void)receivePacketList:(const MIDIPacketList *)packetList fromEndpoint:(MIDIEndpointRef)endpoint;

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
 * The list of available sources, an array of SEMIDIEndpoint
 *
 *  This property issues key-value observing notifications, when new sources
 *  become available, or existing sources become unavailable.
 */
@property (nonatomic, strong, readonly) NSArray *availableSources;

/*!
 * The source to receive from
 */
@property (nonatomic, strong) SEMIDIEndpoint *source;

@end

#ifdef __cplusplus
}
#endif
