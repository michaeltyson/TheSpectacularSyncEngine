//
//  SETempoPulseView.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 6/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SETempoPulseView.h"
@import QuartzCore;
#import "SEMetronome.h"

static NSString * const kAnimationName = @"animation";

@interface SETempoPulseView () {
    uint64_t _timeBase;
}
@property (nonatomic) CALayer * animationLayer;
@property (nonatomic) CADisplayLink * displayLink;
@end

@implementation SETempoPulseView

-(instancetype)initWithFrame:(CGRect)frame {
    if ( !(self = [super initWithFrame:frame]) ) return nil;
    
    [self setup];
    
    return self;
}

-(instancetype)initWithCoder:(NSCoder *)coder {
    if ( !(self = [super initWithCoder:coder]) ) return nil;
    
    [self setup];
    
    return self;
}

-(void)dealloc {
    if ( _displayLink ) {
        [_displayLink invalidate];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)layoutSubviews {
    _animationLayer.cornerRadius = self.bounds.size.width / 2.0;
    _animationLayer.frame = self.bounds;
}

-(void)tintColorDidChange {
    _animationLayer.borderColor = self.tintColor.CGColor;
    if ( _indeterminate ) {
        [self updateAnimationStatus];
    }
}

-(void)setup {
    self.animationLayer = [CALayer layer];
    
    _animationLayer.cornerRadius = self.bounds.size.width / 2.0;
    _animationLayer.borderColor = self.tintColor.CGColor;
    _animationLayer.borderWidth = 2;
    _animationLayer.frame = self.bounds;
    
    [self.layer addSublayer:_animationLayer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

-(void)applicationWillEnterForeground:(NSNotification*)notification {
    [self updateAnimationStatus];
}

-(void)applicationDidEnterBackground:(NSNotification*)notification {
    [self updateAnimationStatus];
}

-(void)setMetronome:(SEMetronome *)metronome {
    if ( _metronome ) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMetronomeDidStartNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMetronomeDidStopNotification object:_metronome];
    }
    
    _metronome = metronome;
    
    if (_metronome ) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clockStartedOrStopped) name:SEMetronomeDidStartNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clockStartedOrStopped) name:SEMetronomeDidStopNotification object:_metronome];
        
        [self updateAnimationStatus];
    }
}

-(void)setIndeterminate:(BOOL)indeterminate {
    if ( _indeterminate == indeterminate ) return;
    
    _indeterminate = indeterminate;
    
    if ( !_indeterminate ) {
        _animationLayer.borderWidth = 2.0;
        _animationLayer.contents = nil;
    } else {
        _animationLayer.borderWidth = 0.0;
        _animationLayer.contents = (id)[self indeterminateImage].CGImage;
    }
    
    [self updateAnimationStatus];
}

-(void)updateAnimationStatus {
    if ( (_indeterminate || _metronome.started) && [UIApplication sharedApplication].applicationState == UIApplicationStateActive && !_displayLink ) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(update)];
        [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    } else {
        if ( _displayLink ) {
            [_displayLink invalidate];
            self.displayLink = nil;
        }
    }
}

- (void)clockStartedOrStopped {
    [self updateAnimationStatus];
}

-(void)update {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if ( _indeterminate ) {
        const NSTimeInterval duration = 5.0;
        _animationLayer.transform = CATransform3DMakeRotation((fmod(CACurrentMediaTime(), duration) / duration) * 2 * M_PI, 0, 0, 1);
    } else {
        double time     = [_metronome timelinePositionForTime:0];
        double position = fmod(time, 1.0) / 1.0;
        
        double scale    = position < 0.5 ? 1.0 - position*2.0 : (position-0.5) * 2.0;
        
        const double minScale = 1.0;
        const double maxScale = 1.2;
        scale = minScale + ((scale*scale) * (maxScale-minScale));
        _animationLayer.transform = CATransform3DMakeScale(scale, scale, 1);
    }
    [CATransaction commit];
}

-(UIImage*)indeterminateImage {
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, [[UIScreen mainScreen] scale]);

    [self.tintColor setStroke];

    int segments = 8;
    double increment = (2.0*M_PI) / (double)(segments*2.0);
    CGRect rect = CGRectInset(self.bounds, 1, 1);
    
    UIBezierPath * path = [UIBezierPath bezierPath];
    
    for ( int i=0; i<segments; i++ ) {
        [path moveToPoint:CGPointMake(CGRectGetMidX(rect) + cos(increment * (2*i))*rect.size.width/2.0,
                                      CGRectGetMidY(rect) + sin(increment * (2*i))*rect.size.height/2.0)];
        [path addArcWithCenter:CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect))
                        radius:rect.size.height/2.0
                    startAngle:increment * (2*i)
                      endAngle:increment * ((2*i)+1)
                     clockwise:YES];
    }
    
    [path setLineWidth:2.0];
    [path stroke];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end
