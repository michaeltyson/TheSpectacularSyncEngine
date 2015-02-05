//
//  SEBackgroundView.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 1/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEBackgroundView.h"

@implementation SEBackgroundView

-(void)drawRect:(CGRect)rect {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    UIColor* color = [UIColor colorWithRed: 0.1 green: 0.064 blue: 0.001 alpha: 1];
    UIColor* color2 = [UIColor colorWithRed: 0.29 green: 0.159 blue: 0.004 alpha: 1];
    
    CGFloat radialGradient1Locations[] = {0, 1};
    CGGradientRef radialGradient1 = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)@[(id)color2.CGColor, (id)color.CGColor], radialGradient1Locations);
    
    UIBezierPath* backgroundPath = [UIBezierPath bezierPathWithRect: CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height)];
    CGContextSaveGState(context);
    [backgroundPath addClip];
    CGContextDrawRadialGradient(context, radialGradient1,
                                CGPointMake(self.bounds.size.width/2.0, self.bounds.size.height/2.0), 0,
                                CGPointMake(self.bounds.size.width/2.0, self.bounds.size.height/2.0), self.bounds.size.height,
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(context);
    
    CGGradientRelease(radialGradient1);
    CGColorSpaceRelease(colorSpace);
}

@end
