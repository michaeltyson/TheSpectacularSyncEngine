//
//  SEMIDIClockSenderPGMidiInterface.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIClockSenderPGMidiInterface.h"

@implementation SEMIDIClockSenderPGMidiInterface

-(void)sendMIDIPacketList:(const MIDIPacketList *)packetList {
    for ( PGMidiDestination *destination in self.destinations ) {
        [destination sendPacketList:(MIDIPacketList*)packetList];
    }
}

@end
