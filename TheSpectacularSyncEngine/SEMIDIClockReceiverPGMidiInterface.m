//
//  SEMIDIClockReceiverPGMidiInterface.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIClockReceiverPGMidiInterface.h"

@interface SEMIDIClockReceiverPGMidiInterface ()
@property (nonatomic, readwrite) SEMIDIClockReceiver * receiver;
@end

@implementation SEMIDIClockReceiverPGMidiInterface

-(instancetype)initWithReceiver:(SEMIDIClockReceiver *)receiver {
    if ( !(self = [super init]) ) return nil;
    self.receiver = receiver;
    return self;
}

-(void)dealloc {
    self.source = nil;
}

-(void)setSource:(PGMidiSource*)source {
    if ( _source ) {
        [_source removeDelegate:self];
    }
    
    _source = source;
    [_receiver reset];
    
    if ( _source ) {
        [_source addDelegate:self];
    }
}

-(void)midiSource:(PGMidiSource *)input midiReceived:(const MIDIPacketList *)packetList {
    SEMIDIClockReceiverReceivePacketList(_receiver, packetList);
}

@end
