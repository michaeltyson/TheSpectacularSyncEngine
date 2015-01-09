//
//  DSPlayPauseButton.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "DSPlayPauseButton.h"
#import "DSGraphics.h"

@implementation DSPlayPauseButton

-(void)drawRect:(CGRect)rect {
    if ( self.selected ) {
        [DSGraphics drawPauseWithFrame:self.bounds];
    } else {
        [DSGraphics drawPlayWithFrame:self.bounds];
    }
}

@end
