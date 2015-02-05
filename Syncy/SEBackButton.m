//
//  SEBackButton.m
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 5/02/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEBackButton.h"
#import "SEGraphics.h"

@implementation SEBackButton

-(void)drawRect:(CGRect)rect {
    [SEGraphics drawBackWithFrame:self.bounds];
}

@end
