//
//  SECommon.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#include "SECommon.h"
#include <dispatch/dispatch.h>
#include <assert.h>

static double __hostTicksToSeconds = 0.0;
static double __secondsToHostTicks = 0.0;

static void SEMIDIInit() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info_data_t tinfo;
        mach_timebase_info(&tinfo);
        __hostTicksToSeconds = ((double)tinfo.numer / tinfo.denom) * 1.0e-9;
        __secondsToHostTicks = 1.0 / __hostTicksToSeconds;
    });
}

uint64_t SECurrentTimeInHostTicks() {
    return mach_absolute_time();
}

double SECurrentTimeInSeconds() {
    if ( !__hostTicksToSeconds ) SEMIDIInit();
    return mach_absolute_time() * __hostTicksToSeconds;
}

uint64_t SESecondsToHostTicks(NSTimeInterval seconds) {
    if ( !__secondsToHostTicks ) SEMIDIInit();
    assert(seconds >= 0);
    return seconds * __secondsToHostTicks;
}

NSTimeInterval SEHostTicksToSeconds(uint64_t ticks) {
    if ( !__hostTicksToSeconds ) SEMIDIInit();
    return ticks * __hostTicksToSeconds;
}

double SESecondsToBeats(double seconds, double tempo) {
    return seconds / (60.0 / tempo);
}

double SEBeatsToSeconds(double beats, double tempo) {
    return beats * (60.0 / tempo);
}

double SEHostTicksToBeats(uint64_t ticks, double tempo) {
    return ticks / (SESecondsToHostTicks(60.0) / tempo);
}

uint64_t SEBeatsToHostTicks(double beats, double tempo) {
    return beats * (SESecondsToHostTicks(60.0) / tempo);
}


#pragma mark - Weak retaining proxy for timers

@implementation SEWeakRetainingProxy
-(instancetype)initWithTarget:(id)target {
    self.target = target;
    return self;
}
-(NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [_target methodSignatureForSelector:selector];
}
-(void)forwardInvocation:(NSInvocation *)invocation {
    [invocation setTarget:_target];
    [invocation invoke];
}
@end
