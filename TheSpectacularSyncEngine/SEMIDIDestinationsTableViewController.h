//
//  SEMIDIDestinationsTableViewController.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SEMIDIClockSenderCoreMIDIInterface;

/*!
 * Core MIDI destination table view controller
 *
 *  This view controller utility class gives an easy way to present to the
 *  user a list of available Core MIDI destinations, for use with the
 *  SEMIDIClockSenderCoreMIDIInterface utility class.
 */
@interface SEMIDIDestinationsTableViewController : UITableViewController
-(instancetype)init;

@property (nonatomic) SEMIDIClockSenderCoreMIDIInterface *interface;
@end
