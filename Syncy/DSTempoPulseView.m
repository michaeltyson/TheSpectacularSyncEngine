//
//  DSTempoPulseView.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 6/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "DSTempoPulseView.h"
@import QuartzCore;
#import "DSMetronome.h"

static NSString * const kAnimationName = @"animation";

@interface DSTempoPulseView () {
    uint64_t _timeBase;
}
@property (nonatomic) CALayer * animationLayer;
@property (nonatomic) CABasicAnimation * animation;
@end

@implementation DSTempoPulseView

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
    self.metronome = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)layoutSubviews {
    _animationLayer.cornerRadius = self.bounds.size.width / 2.0;
    _animationLayer.frame = self.bounds;
}

-(void)tintColorDidChange {
    _animationLayer.borderColor = self.tintColor.CGColor;
    if ( _indeterminate ) {
        [self setupAnimation];
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
}

-(void)applicationWillEnterForeground:(NSNotification*)notification {
    [self setupAnimation];
}

-(void)setMetronome:(DSMetronome *)metronome {
    if ( _metronome ) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMetronomeDidChangeTempoNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMetronomeDidChangeTimelineNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMetronomeDidStartNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMetronomeDidStopNotification object:_metronome];
    }
    
    _metronome = metronome;
    
    if (_metronome ) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stateChanged:) name:DSMetronomeDidChangeTempoNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stateChanged:) name:DSMetronomeDidChangeTimelineNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stateChanged:) name:DSMetronomeDidStartNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stateChanged:) name:DSMetronomeDidStopNotification object:_metronome];
        
        [self setupAnimation];
    }
}

-(void)setIndeterminate:(BOOL)indeterminate {
    if ( _indeterminate == indeterminate ) return;
    
    _indeterminate = indeterminate;
    
    [self setupAnimation];
}

-(void)stateChanged:(NSNotification*)notification {
    if ( !_indeterminate ) {
        [self setupAnimation];
    }
}

-(void)setupAnimation {
    if ( _animation ) {
        [_animationLayer removeAnimationForKey:kAnimationName];
        _animation = nil;
    }
    
    if ( !_indeterminate ) {
        _animationLayer.borderWidth = 2.0;
        _animationLayer.contents = nil;
        
        _animation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        _animation.fromValue = @(1.0);
        _animation.toValue = @(1.2);
        _animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        _animation.autoreverses = YES;
        _animation.duration = (60.0 / _metronome.tempo) / 2.0;
        _animation.repeatCount = HUGE_VALF;
        
        double position = [_metronome timelinePositionForTime:0] + 0.5;
        double delay = fmod(position, 1.0);
        if ( delay > 1.0-1.0e-5 ) delay = 0.0;
        NSTimeInterval delayInSeconds = (60.0 / _metronome.tempo) * delay;

        if ( delayInSeconds <= 0.1 ) {
            [_animationLayer addAnimation:_animation forKey:kAnimationName];
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [_animationLayer addAnimation:_animation forKey:kAnimationName];
            });
        }
    } else {
        _animationLayer.borderWidth = 0.0;
        _animationLayer.contents = (id)[self indeterminateImage].CGImage;
        _animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation"];
        _animation.fromValue = @(0.0);
        _animation.toValue = @(2*M_PI);
        _animation.duration = 5.0;
        _animation.repeatCount = HUGE_VALF;
        [_animationLayer addAnimation:_animation forKey:kAnimationName];
    }
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
