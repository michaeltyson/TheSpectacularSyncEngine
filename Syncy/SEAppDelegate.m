//
//  SEAppDelegate.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEAppDelegate.h"
//#import "SEAudioEngine.h"
//#import "SEMetronome.h"
//#import "SEMIDIClockReceiver.h"
//#import "SEMIDIClockReceiverCoreMIDIInterface.h"
//#import "SEMIDIClockSender.h"
//#import "SEMIDIClockSenderCoreMIDIInterface.h"
#import "SEMainViewController.h"

@interface SEAppDelegate ()
//@property (nonatomic) SEAudioEngine *audioEngine;
//@property (nonatomic) SEMetronome *metronome;
//@property (nonatomic) SEMIDIClockReceiver *receiver;
//@property (nonatomic) SEMIDIClockReceiverCoreMIDIInterface *receiverInterface;
//@property (nonatomic) SEMIDIClockSender *sender;
//@property (nonatomic) SEMIDIClockSenderCoreMIDIInterface *senderInterface;
//@property (nonatomic) NSTimer *shutdownTimer;
@end

@interface SEAppDelegateProxy : NSProxy
-(instancetype)initWithTarget:(SEAppDelegate*)target;
@property (nonatomic, weak) SEAppDelegate * target;
@end

@implementation SEAppDelegate

//-(void)dealloc {
//    if ( _shutdownTimer ) {
//        [_shutdownTimer invalidate];
//    }
//    [[NSNotificationCenter defaultCenter] removeObserver:self];
//}

-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
//    self.receiver = [SEMIDIClockReceiver new];
//    self.receiverInterface = [[SEMIDIClockReceiverCoreMIDIInterface alloc] initWithReceiver:_receiver];
//
//    self.senderInterface = [[SEMIDIClockSenderCoreMIDIInterface alloc] init];
//    self.sender = [[SEMIDIClockSender alloc] initWithInterface:_senderInterface];
//    self.sender.sendClockTicksWhileTimelineStopped = YES;
//
//    self.metronome = [SEMetronome new];
//
//    self.audioEngine = [[SEAudioEngine alloc] initWithAudioProvider:_metronome];
//    [_audioEngine start];
//
//    SEMainViewController *viewController = (SEMainViewController*)self.window.rootViewController;
//    viewController.metronome = _metronome;
//    viewController.sender = _sender;
//    viewController.receiver = _receiver;
//    viewController.receiverInterface = _receiverInterface;
//
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wentActive:) name:SEMIDIClockReceiverDidStartTempoSyncNotification object:nil];
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wentInactive:) name:SEMIDIClockReceiverDidStopTempoSyncNotification object:nil];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
//    [MIDINetworkSession defaultSession].enabled = YES;
//    [MIDINetworkSession defaultSession].connectionPolicy = MIDINetworkConnectionPolicy_Anyone;
    
    if ( [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone ) {
        [[UIApplication sharedApplication] setStatusBarHidden:YES];
    }
    
    return YES;
}

//-(void)applicationWillEnterForeground:(UIApplication *)application {
//    if ( _shutdownTimer ) {
//        [_shutdownTimer invalidate];
//        self.shutdownTimer = nil;
//    }
//
//    [_audioEngine start];
//}
//
//-(void)applicationDidEnterBackground:(UIApplication *)application {
//    if ( !_metronome.started && !_receiver.receivingTempo && !_shutdownTimer ) {
//        self.shutdownTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:[[SEAppDelegateProxy alloc] initWithTarget:self] selector:@selector(shutdown) userInfo:nil repeats:NO];
//    }
//}
//
//-(void)shutdown {
//    [_audioEngine stop];
//}
//
//-(void)wentActive:(NSNotification*)notification {
//    if ( _shutdownTimer ) {
//        [_shutdownTimer invalidate];
//        self.shutdownTimer = nil;
//    }
//}
//
//-(void)wentInactive:(NSNotification*)notification {
//    if ( [[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground && !_metronome.started && !_receiver.receivingTempo && !_shutdownTimer ) {
//        self.shutdownTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:[[SEAppDelegateProxy alloc] initWithTarget:self] selector:@selector(shutdown) userInfo:nil repeats:NO];
//    }
//}

@end


//@implementation SEAppDelegateProxy
//-(instancetype)initWithTarget:(SEAppDelegate*)target {
//    self.target = target;
//    return self;
//}
//-(NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
//    return [_target methodSignatureForSelector:selector];
//}
//-(void)forwardInvocation:(NSInvocation *)invocation {
//    [invocation setTarget:_target];
//    [invocation invoke];
//}
//@end
