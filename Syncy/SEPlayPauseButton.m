//
//  SEPlayPauseButton.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEPlayPauseButton.h"
#import "SEGraphics.h"

@implementation SEPlayPauseButton

-(void)drawRect:(CGRect)rect {
    if ( self.selected ) {
        [SEGraphics drawPauseWithFrame:self.bounds];
    } else {
        [SEGraphics drawPlayWithFrame:self.bounds];
    }
}

@end
