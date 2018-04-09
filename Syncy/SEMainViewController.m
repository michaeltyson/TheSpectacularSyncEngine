//
//  SEMainViewController.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMainViewController.h"
#import "SEMetronome.h"
#import "SEMIDIClockReceiver.h"
#import "SEMIDIClockSender.h"
#import "SETempoPulseView.h"
#import "SEMIDISourcesTableViewController.h"
#import "SEMIDIDestinationsTableViewController.h"

static NSString * const kPulseAnimationKey = @"pulse";

static const double kTempoDragVelocity = 0.15;

@interface SEMainViewController () {
    double _preDragTempo;
}
@property (nonatomic) NSTimer * updateTimer;
@property (nonatomic) UIPanGestureRecognizer * tempoDragGestureRecognizer;
@end

@implementation SEMainViewController

-(void)dealloc {
    self.metronome = nil;
    self.sender = nil;
    self.receiver = nil;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    self.positionLabel.hidden = YES;
    self.stabilityLabel.hidden = YES;
    self.forwardButton.hidden = YES;
    self.backButton.hidden = YES;
    self.tempoLabel.text = [NSString stringWithFormat:@"%g BPM", _metronome.tempo];
    _tempoPulseView.metronome = _metronome;
    
    self.tempoDragGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(tempoDrag:)];
    [_tempoPulseView addGestureRecognizer:_tempoDragGestureRecognizer];
    
    _sender.tempo = _metronome.tempo;
}

-(IBAction)togglePlayPause:(id)sender {
    if ( !_metronome.started ) {
        uint64_t startTime = [_sender startAtTime:0];
        [_metronome startAtTime:startTime];
    } else {
        [_metronome stop];
        [_sender stop];
    }
    
    _playPauseButton.selected = _metronome.started;
    _forwardButton.hidden = !_metronome.started || _receiver.clockRunning;
    _backButton.hidden = !_metronome.started || _receiver.clockRunning;
}

-(IBAction)forward:(id)sender {
    if ( !_metronome.started ) return;
    double newPosition = floor([_metronome timelinePositionForTime:SECurrentTimeInHostTicks()] + 4.0);
    uint64_t applyTime = [_sender setActiveTimelinePosition:newPosition atTime:0];
    [_metronome setTimelinePosition:newPosition atTime:applyTime];
}

-(IBAction)backward:(id)sender {
    if ( !_metronome.started ) return;
    double newPosition = floor([_metronome timelinePositionForTime:SECurrentTimeInHostTicks()] - 4.0);
    if ( newPosition < 0.0 ) newPosition = 0.0;
    uint64_t applyTime = [_sender setActiveTimelinePosition:newPosition atTime:0];
    [_metronome setTimelinePosition:newPosition atTime:applyTime];
}

-(void)tempoDrag:(UIPanGestureRecognizer*)recognizer {
    if ( recognizer.state == UIGestureRecognizerStateBegan ) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = @(0.8);
        animation.toValue = @(0.2);
        animation.autoreverses = YES;
        animation.duration = 0.2;
        animation.repeatCount = HUGE_VALF;
        [_tempoLabel.layer addAnimation:animation forKey:kPulseAnimationKey];
        
        _preDragTempo = _metronome.tempo;
        _tempoPulseView.indeterminate = YES;
    } else if ( recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled ) {
        [_tempoLabel.layer removeAnimationForKey:kPulseAnimationKey];
        _tempoPulseView.indeterminate = NO;
    } else if ( recognizer.state == UIGestureRecognizerStateChanged ) {
        double newTempo = round(_preDragTempo + -[recognizer translationInView:_tempoPulseView].y * kTempoDragVelocity);
        _metronome.tempo = MAX(10.0, newTempo);
    }
}

-(void)setMetronome:(SEMetronome *)metronome {
    if ( _metronome ) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMetronomeDidStartNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMetronomeDidStopNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMetronomeDidChangeTempoNotification object:_metronome];
    }
    
    _metronome = metronome;
    _tempoPulseView.metronome = _metronome;
    
    if ( _sender ) {
        _sender.tempo = _metronome.tempo;
    }
    
    if (_metronome ) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(started:) name:SEMetronomeDidStartNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopped:) name:SEMetronomeDidStopNotification object:_metronome];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changedTempo:) name:SEMetronomeDidChangeTempoNotification object:_metronome];
    }
}

-(void)setSender:(SEMIDIClockSender *)sender {
    _sender = sender;
    
    if ( _metronome && _sender) {
        _sender.tempo = _metronome.tempo;
    }
}

-(void)setReceiver:(SEMIDIClockReceiver *)receiver {
    if ( _receiver ) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMIDIClockReceiverDidStartTempoSyncNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMIDIClockReceiverDidStopTempoSyncNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMIDIClockReceiverDidStartNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMIDIClockReceiverDidStopNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMIDIClockReceiverDidChangeTempoNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SEMIDIClockReceiverDidLiveSeekNotification object:_receiver];
    }
    
    _receiver = receiver;
    
    if ( _receiver ) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiverStartedOrStoppedTempoSync:) name:SEMIDIClockReceiverDidStartTempoSyncNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiverStartedOrStoppedTempoSync:) name:SEMIDIClockReceiverDidStopTempoSyncNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiverStarted:) name:SEMIDIClockReceiverDidStartNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiverStopped:) name:SEMIDIClockReceiverDidStopNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiverChangedTempo:) name:SEMIDIClockReceiverDidChangeTempoNotification object:_receiver];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiverSeeked:) name:SEMIDIClockReceiverDidLiveSeekNotification object:_receiver];
    }
}

-(void)update {
    if ( _metronome.started ) {
        double position = [_metronome timelinePositionForTime:0];
        _positionLabel.text = [NSString stringWithFormat:@"%d:%d:%d", (int)floor(position / 4.0) + 1, (int)floor(fmod(position, 4.0)) + 1, (int)floor(fmod(position, 1.0) / 0.25) + 1];
        _positionLabel.hidden = NO;
    } else {
        _positionLabel.hidden = YES;
    }
    
    if ( _receiver.receivingTempo ) {
        double error = _receiver.error;
        _stabilityLabel.text = error == 0.0 ? @"PERFECT SIGNAL" : [NSString stringWithFormat:@"%0.2g%% ERROR", _receiver.error];
        _stabilityLabel.hidden = NO;
    } else {
        _stabilityLabel.hidden = YES;
    }
    
    if ( _receiver.clockRunning ) {
        uint64_t timestamp = SECurrentTimeInHostTicks();
        double receiverPosition = [_receiver timelinePositionForTime:timestamp];
        double metronomePosition = [_metronome timelinePositionForTime:timestamp];
        
        if ( fabs(receiverPosition - metronomePosition) > 0.01 ) {
            [_metronome setTimelinePosition:receiverPosition atTime:timestamp];
        }
    }
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ( [segue.destinationViewController isKindOfClass:[UINavigationController class]] ) {
        UIViewController *viewController = [segue.destinationViewController topViewController];
        if ( [viewController isKindOfClass:[SEMIDISourcesTableViewController class]] ) {
            ((SEMIDISourcesTableViewController*)viewController).interface = _receiverInterface;
        } else if ( [viewController isKindOfClass:[SEMIDIDestinationsTableViewController class]] ) {
            ((SEMIDIDestinationsTableViewController*)viewController).interface = (SEMIDIClockSenderCoreMIDIInterface*)_sender.senderInterface;
        }
    }
}

#pragma mark - Metronome notifications

-(void)started:(NSNotification*)notification {
    if ( !_updateTimer ) {
        self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(update) userInfo:nil repeats:YES];
    }
    
    _playPauseButton.selected = _metronome.started;
    _forwardButton.hidden = !_metronome.started || _receiver.clockRunning;
    _backButton.hidden = !_metronome.started || _receiver.clockRunning;

    
    if ( !_sender.started ) {
        [_sender startAtTime:[notification.userInfo[SENotificationTimestampKey] unsignedLongLongValue]];
    }
}

-(void)stopped:(NSNotification*)notification {
    if ( !_receiver.receivingTempo && !_metronome.started && _updateTimer ) {
        [_updateTimer invalidate];
        self.updateTimer = nil;
        _positionLabel.hidden = YES;
    }
    
    if ( _sender.started ) {
        [_sender stop];
    }
    
    _playPauseButton.selected = _metronome.started;
    _forwardButton.hidden = !_metronome.started || _receiver.clockRunning;
    _backButton.hidden = !_metronome.started || _receiver.clockRunning;
}

-(void)changedTempo:(NSNotification*)notification {
    self.tempoLabel.text = [NSString stringWithFormat:@"%g BPM", _metronome.tempo];
    _sender.tempo = _metronome.tempo;
}

#pragma mark - Receiver notifications

-(void)receiverStartedOrStoppedTempoSync:(NSNotification*)notification {
    if ( _receiver.receivingTempo ) {
        _metronome.tempo = _receiver.tempo;
    } else if ( _metronome.started ) {
        [_metronome stop];
        _playPauseButton.enabled = YES;
    }
    
    if ( _receiver.receivingTempo && !_updateTimer ) {
        self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(update) userInfo:nil repeats:YES];
    } else if ( !_receiver.receivingTempo ) {
        if ( _updateTimer ) {
            [_updateTimer invalidate];
            self.updateTimer = nil;
        }
        _stabilityLabel.hidden = YES;
    }
    
    _tempoDragGestureRecognizer.enabled = !_receiver.receivingTempo;
}

-(void)receiverStarted:(NSNotification*)notification {
    uint64_t applyTime = [notification.userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue];
    double position = [_receiver timelinePositionForTime:applyTime];
    
    [_metronome setTimelinePosition:position atTime:applyTime];
    [_metronome startAtTime:applyTime];
    
    _playPauseButton.enabled = NO;
}

-(void)receiverStopped:(NSNotification*)notification {
    [_metronome stop];
    _playPauseButton.enabled = YES;
}

-(void)receiverChangedTempo:(NSNotification*)notification {
    _metronome.tempo = _receiver.tempo;
}

-(void)receiverSeeked:(NSNotification*)notification {
    uint64_t applyTime = [notification.userInfo[SEMIDIClockReceiverTimestampKey] unsignedLongLongValue];
    double position = [_receiver timelinePositionForTime:applyTime];
    
    [_metronome setTimelinePosition:position atTime:applyTime];
}

@end
