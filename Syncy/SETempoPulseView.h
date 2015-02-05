//
//  SETempoPulseView.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 6/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

@import UIKit;

@class SEMetronome;

IB_DESIGNABLE
@interface SETempoPulseView : UIView
@property (nonatomic) SEMetronome *metronome;
@property (nonatomic) BOOL indeterminate;
@end
