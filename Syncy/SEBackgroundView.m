//
//  SEBackgroundView.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 1/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEBackgroundView.h"
#import "SEGraphics.h"

@implementation SEBackgroundView

-(void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGGradientRef radialGradient = [SEGraphics backgroundGradient].CGGradient;
    UIBezierPath* backgroundPath = [UIBezierPath bezierPathWithRect: CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height)];
    CGContextSaveGState(context);
    [backgroundPath addClip];
    CGContextDrawRadialGradient(context, radialGradient,
                                CGPointMake(self.bounds.size.width/2.0, self.bounds.size.height/2.0), 0,
                                CGPointMake(self.bounds.size.width/2.0, self.bounds.size.height/2.0), self.bounds.size.height,
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(context);
}

@end
