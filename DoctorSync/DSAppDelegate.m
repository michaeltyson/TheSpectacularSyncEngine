//
//  DSAppDelegate.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "DSAppDelegate.h"
#import "DSAudioEngine.h"
#import "DSMetronome.h"
#import "SEMIDIClockReceiver.h"
#import "SEMIDIClockReceiverCoreMIDIInterface.h"
#import "SEMIDIClockSender.h"
#import "SEMIDIClockSenderCoreMIDIInterface.h"
#import "DSMainViewController.h"

@interface DSAppDelegate ()
@property (nonatomic) DSAudioEngine *audioEngine;
@property (nonatomic) DSMetronome *metronome;
@property (nonatomic) SEMIDIClockReceiver *receiver;
@property (nonatomic) SEMIDIClockReceiverCoreMIDIInterface *receiverInterface;
@property (nonatomic) SEMIDIClockSender *sender;
@property (nonatomic) SEMIDIClockSenderCoreMIDIInterface *senderInterface;
@property (nonatomic) NSTimer *shutdownTimer;
@end

@interface DSAppDelegateProxy : NSProxy
-(instancetype)initWithTarget:(DSAppDelegate*)target;
@property (nonatomic, weak) DSAppDelegate * target;
@end

@implementation DSAppDelegate

-(void)dealloc {
    if ( _shutdownTimer ) {
        [_shutdownTimer invalidate];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    self.receiver = [SEMIDIClockReceiver new];
    self.receiverInterface = [[SEMIDIClockReceiverCoreMIDIInterface alloc] initWithReceiver:_receiver];
    
    self.senderInterface = [[SEMIDIClockSenderCoreMIDIInterface alloc] init];
    self.sender = [[SEMIDIClockSender alloc] initWithInterface:_senderInterface];
    
    self.metronome = [DSMetronome new];
    
    self.audioEngine = [[DSAudioEngine alloc] initWithAudioProvider:_metronome];
    [_audioEngine start];
    
    DSMainViewController *viewController = (DSMainViewController*)self.window.rootViewController;
    viewController.metronome = _metronome;
    viewController.sender = _sender;
    viewController.receiver = _receiver;
    viewController.receiverInterface = _receiverInterface;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wentActive:) name:SEMIDIClockReceiverDidStartTempoSyncNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wentInactive:) name:SEMIDIClockReceiverDidStopTempoSyncNotification object:nil];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
    return YES;
}

-(void)applicationWillEnterForeground:(UIApplication *)application {
    if ( _shutdownTimer ) {
        [_shutdownTimer invalidate];
        self.shutdownTimer = nil;
    }
    
    [_audioEngine start];
}

-(void)applicationDidEnterBackground:(UIApplication *)application {
    if ( !_metronome.started && !_receiver.receivingTempo && !_shutdownTimer ) {
        self.shutdownTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:[[DSAppDelegateProxy alloc] initWithTarget:self] selector:@selector(shutdown) userInfo:nil repeats:NO];
    }
}

-(void)shutdown {
    [_audioEngine stop];
}

-(void)wentActive:(NSNotification*)notification {
    if ( _shutdownTimer ) {
        [_shutdownTimer invalidate];
        self.shutdownTimer = nil;
    }
}

-(void)wentInactive:(NSNotification*)notification {
    if ( [[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground && !_metronome.started && !_receiver.receivingTempo && !_shutdownTimer ) {
        self.shutdownTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:[[DSAppDelegateProxy alloc] initWithTarget:self] selector:@selector(shutdown) userInfo:nil repeats:NO];
    }
}

@end


@implementation DSAppDelegateProxy
-(instancetype)initWithTarget:(DSAppDelegate*)target {
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
