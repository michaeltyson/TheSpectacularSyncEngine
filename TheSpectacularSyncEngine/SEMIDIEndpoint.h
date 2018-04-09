//
//  SEMIDIEndpoint.h
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 13/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>



/*!
 * MIDI endpoint utility class
 *
 *  This class represents a single Core MIDI endpoint
 */
@interface SEMIDIEndpoint : NSObject

/*!
 * Initialize
 */
-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint;

/*!
 * Initialize with a specific name to show to user rather than endpoint's name
 */
-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint name:(NSString*)name;

/*!
 * Perform endpoint-specific connection tasks
 */
-(void)connect;

/*!
 * Perform endpoint-specific disconnection tasks
 */
-(void)disconnect;

/*!
 * The MIDI endpoint
 */
@property (nonatomic, readonly) MIDIEndpointRef endpoint;

/*!
 * The display name for the endpoint
 */
@property (nonatomic, strong, readonly) NSString *name;

@end

/*!
 * Network MIDI endpoint
 */
@interface SEMIDINetworkEndpoint : SEMIDIEndpoint

/*!
 * Initialize
 */
-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint host:(MIDINetworkHost*)host;

/*!
 * The network host
 */
@property (nonatomic, strong) MIDINetworkHost *host;

/*!
 * Whether we're connected to the host
 */
@property (nonatomic, readonly) BOOL connected;

@end
