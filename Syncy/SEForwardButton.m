//
//  SEForwardButton.m
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 5/02/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEForwardButton.h"
#import "SEGraphics.h"

@implementation SEForwardButton

-(void)drawRect:(CGRect)rect {
    [SEGraphics drawForwardWithFrame:self.bounds];
}

@end
