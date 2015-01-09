//
//  SEMIDIClockReceiverPGMidiInterface.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#ifdef __cplusplus
extern "C" {
#endif

#import "SEMIDIClockReceiver.h"
#import "PGMidi.h"

/*!
 * PGMidi compatibilty class
 *
 *  This class provides an interface between SEMIDIClockReceiver and PGMidi,
 *  functioning as a PGMidiSourceDelegate.
 *
 *  If you do not use PGMidi, exclude this file from your app's sources.
 *
 *  Found out more about PGMidi at https://github.com/petegoodliffe/PGMidi
 */
@interface SEMIDIClockReceiverPGMidiInterface : NSObject <PGMidiSourceDelegate>

/*!
 * Default initialiser
 *
 * @param receiver The SEMIDIClockReceiver instance
 */
-(instancetype)initWithReceiver:(SEMIDIClockReceiver*)receiver;

/*!
 * Source to receive from
 */
@property (nonatomic, strong) PGMidiSource *source;

/*!
 * The SEMIDIClockReceiver instance
 */
@property (nonatomic, strong, readonly) SEMIDIClockReceiver * receiver;

@end

#ifdef __cplusplus
}
#endif
