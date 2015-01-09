//
//  SEMIDISourcesTableViewController.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SEMIDIClockReceiverCoreMIDIInterface;

/*!
 * Core MIDI source table view controller
 *
 *  This view controller utility class gives an easy way to present to the
 *  user a list of available Core MIDI sources, for use with the
 *  SEMIDIClockReceiverCoreMIDIInterface utility class.
 */
@interface SEMIDISourcesTableViewController : UITableViewController
-(instancetype)init;

@property (nonatomic) SEMIDIClockReceiverCoreMIDIInterface *interface;
@end
