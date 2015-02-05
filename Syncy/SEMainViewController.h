//
//  SEMainViewController.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SEMetronome;
@class SEMIDIClockReceiver;
@class SEMIDIClockSender;
@class SEMIDIClockReceiverCoreMIDIInterface;
@class SETempoPulseView;

@interface SEMainViewController : UIViewController

-(IBAction)showSources:(id)sender;
-(IBAction)showDestinations:(id)sender;
-(IBAction)togglePlayPause:(id)sender;

@property (weak, nonatomic) IBOutlet UIButton *playPauseButton;
@property (weak, nonatomic) IBOutlet SETempoPulseView *tempoPulseView;
@property (weak, nonatomic) IBOutlet UILabel *tempoLabel;
@property (weak, nonatomic) IBOutlet UILabel *positionLabel;
@property (weak, nonatomic) IBOutlet UILabel *stabilityLabel;

@property (nonatomic) SEMetronome *metronome;
@property (nonatomic) SEMIDIClockSender *sender;
@property (nonatomic) SEMIDIClockReceiver *receiver;
@property (nonatomic) SEMIDIClockReceiverCoreMIDIInterface *receiverInterface;
@end

