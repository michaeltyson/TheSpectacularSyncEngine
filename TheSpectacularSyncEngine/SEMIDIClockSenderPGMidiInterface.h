//
//  SEMIDIClockSenderPGMidiInterface.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#ifdef __cplusplus
extern "C" {
#endif

#import "SEMIDIClockSender.h"
#import "PGMidi.h"

/*!
 * PGMidi compatibilty class
 *
 *  This class provides an interface between SEMIDIClockSender and PGMidi,
 *  allowing you to send to PGMidiDestinations.
 *
 *  If you do not use PGMidi, exclude this file from your app's sources.
 *
 *  Found out more about PGMidi at https://github.com/petegoodliffe/PGMidi
 */
@interface SEMIDIClockSenderPGMidiInterface : NSObject <SEMIDIClockSenderInterface>

/*!
 * Destinations to send to
 *
 *  An array of PGMidiDestination
 */
@property (copy) NSArray *destinations;

@end

#ifdef __cplusplus
}
#endif
