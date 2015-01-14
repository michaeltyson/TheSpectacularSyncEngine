//
//  SEMIDINetworkMonitor.h
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 13/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <Foundation/Foundation.h>

/*!
 * Network monitor
 *
 *  The network monitor takes care of searching for MIDI network
 *  services, and presets a list of available hosts. This class is
 *  necessary as MIDINetworkSession's 'contacts' list appears to be
 *  non-functional, and doesn't provide discovery functionality.
 *
 *  This class is instantiated and managed automatically by the
 *  SEMIDIClockReceiverCoreMIDIInterface and
 *  SEMIDIClockSenderCoreMIDIInterface classes, and only operates
 *  if MIDINetworkSession's isEnabled property is YES. This class
 *  monitors that property, and will enable/disable itself accordingly.
 */
@interface SEMIDINetworkMonitor : NSObject

/*!
 * Get access to the singleton instance
 */
+(instancetype)sharedNetworkMonitor;

/*!
 * Available hosts; array of MIDINetworkHost
 */
@property (nonatomic, strong, readonly) NSSet * contacts;

@end
