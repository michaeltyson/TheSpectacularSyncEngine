//
//  SEInitViewController.m
//  Syncy
//
//  Created by Oliver Greschke on 09.04.18.
//  Copyright © 2018 A Tasty Pixel. All rights reserved.
//

#import "SEInitViewController.h"

#import "SEAppDelegate.h"
#import "SEAudioEngine.h"
#import "SEMetronome.h"
#import "SEMIDIClockReceiver.h"
#import "SEMIDIClockReceiverCoreMIDIInterface.h"
#import "SEMIDIClockSender.h"
#import "SEMIDIClockSenderCoreMIDIInterface.h"
#import "SEMainViewController.h"

@interface SEInitViewController ()

@property (nonatomic) SEAudioEngine *audioEngine;
@property (nonatomic) SEMetronome *metronome;
@property (nonatomic) SEMIDIClockReceiver *receiver;
@property (nonatomic) SEMIDIClockReceiverCoreMIDIInterface *receiverInterface;
@property (nonatomic) SEMIDIClockSender *sender;
@property (nonatomic) SEMIDIClockSenderCoreMIDIInterface *senderInterface;
@property (nonatomic) NSTimer *shutdownTimer;

@end

@interface SESEInitViewControllerProxy : NSProxy
-(instancetype)initWithTarget:(SEInitViewController*)target;
@property (nonatomic, weak) SEInitViewController * target;
@end

@implementation SEInitViewController

-(void)dealloc {
    if ( _shutdownTimer ) {
        [_shutdownTimer invalidate];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.receiver = [SEMIDIClockReceiver new];
    self.receiverInterface = [[SEMIDIClockReceiverCoreMIDIInterface alloc] initWithReceiver:_receiver];
    
    self.senderInterface = [[SEMIDIClockSenderCoreMIDIInterface alloc] init];
    self.sender = [[SEMIDIClockSender alloc] initWithInterface:_senderInterface];
    self.sender.sendClockTicksWhileTimelineStopped = YES;
    
    self.metronome = [SEMetronome new];
    
    self.audioEngine = [[SEAudioEngine alloc] initWithAudioProvider:_metronome];
    [_audioEngine start];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wentActive:) name:SEMIDIClockReceiverDidStartTempoSyncNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wentInactive:) name:SEMIDIClockReceiverDidStopTempoSyncNotification object:nil];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
    [MIDINetworkSession defaultSession].enabled = YES;
    [MIDINetworkSession defaultSession].connectionPolicy = MIDINetworkConnectionPolicy_Anyone;
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
        self.shutdownTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:[[SESEInitViewControllerProxy alloc] initWithTarget:self] selector:@selector(shutdown) userInfo:nil repeats:NO];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    
    if ( [segue.destinationViewController isKindOfClass:[SEMainViewController class]] ) {
        SEMainViewController *viewController = segue.destinationViewController;
        viewController.metronome = _metronome;
        viewController.sender = _sender;
        viewController.receiver = _receiver;
        viewController.receiverInterface = _receiverInterface;
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
        self.shutdownTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:[[SESEInitViewControllerProxy alloc] initWithTarget:self] selector:@selector(shutdown) userInfo:nil repeats:NO];
    }
}



- (IBAction)StartSync:(UIButton *)sender {
}
@end

// --------------------------------------------------------------------------------------


@implementation SESEInitViewControllerProxy

-(instancetype)initWithTarget:(SEInitViewController*)target {
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
