//
//  SEMIDIClockSenderCoreMIDIInterface.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 1/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIClockSenderCoreMIDIInterface.h"
#import "SEMIDINetworkMonitor.h"
#import "SEMIDIEndpoint.h"

static void * kNetworkContactsChanged = &kNetworkContactsChanged;

@interface SEMIDIClockSenderCoreMIDIInterface () {
    MIDIClientRef _midiClient;
    BOOL _portsAreOurs;
}
@property (nonatomic, readwrite) MIDIPortRef outputPort;
@property (nonatomic, readwrite) MIDIEndpointRef virtualSource;
@end

@implementation SEMIDIClockSenderCoreMIDIInterface
@synthesize destinations = _destinations;

-(instancetype)init {
    
    MIDIClientRef midiClient;
    if ( !SECheckResult(MIDIClientCreate((__bridge CFStringRef)@"SEMIDIClockSender MIDI Client", midiNotify, (__bridge void*)self, &midiClient), "MIDIClientCreate") ) {
        return nil;
    }
    
    MIDIPortRef outputPort;
    if ( !SECheckResult(MIDIOutputPortCreate(midiClient, (__bridge CFStringRef)@"SEMIDIClockSender MIDI Port", &outputPort), "MIDIOutputPortCreate") ) {
        MIDIClientDispose(midiClient);
        return nil;
    }
    
    MIDIEndpointRef virtualSource;
    if ( SECheckResult(MIDISourceCreate(midiClient, (__bridge CFStringRef)self.virtualEndpointName, &virtualSource), "MIDISourceCreate") ) {
        
        // Try to persist unique ID
        SInt32 uniqueID = (SInt32)[[NSUserDefaults standardUserDefaults] integerForKey:@"SEMIDIClockSender Unique ID"];
        if ( uniqueID ) {
            if ( MIDIObjectSetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, uniqueID) == kMIDIIDNotUnique ) {
                uniqueID = 0;
            }
        }
        if ( !uniqueID ) {
            if ( SECheckResult(MIDIObjectGetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, &uniqueID), "MIDIObjectGetIntegerProperty") ) {
                [[NSUserDefaults standardUserDefaults] setInteger:uniqueID forKey:@"SEMIDIClockSender Unique ID"];
            }
        }
    }
    
    if ( !(self=[self initWithMIDIClient:midiClient outputPort:outputPort virtualSource:virtualSource]) ) return nil;
    
    _portsAreOurs = YES;
    
    return self;
}

-(instancetype)initWithOutputPort:(MIDIPortRef)outputPort virtualSource:(MIDIEndpointRef)virtualSource {
    return [self initWithMIDIClient:0 outputPort:outputPort virtualSource:virtualSource];
}

-(instancetype)initWithMIDIClient:(MIDIClientRef)midiClient outputPort:(MIDIPortRef)outputPort virtualSource:(MIDIEndpointRef)virtualSource {
    if ( !(self = [super init]) ) return nil;
    
    NSAssert(outputPort, @"You must provide an output port");
    NSAssert(virtualSource, @"You must provide a Virtual MIDI source");
    
    _midiClient = midiClient;
    _outputPort = outputPort;
    _virtualSource = virtualSource;
    
    if ( !_midiClient ) {
        MIDIClientRef midiClient;
        if ( !SECheckResult(MIDIClientCreate((__bridge CFStringRef)@"SEMIDIClockSender MIDI Client", midiNotify, (__bridge void*)self, &midiClient), "MIDIClientCreate") ) {
            return nil;
        }
    }
    
    // Watch for changes to network contacts and connections
    [[SEMIDINetworkMonitor sharedNetworkMonitor] addObserver:self forKeyPath:@"contacts" options:0 context:kNetworkContactsChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkConnectionsChanged:) name:MIDINetworkNotificationSessionDidChange object:nil];

    return self;
}

-(void)dealloc {
    [[SEMIDINetworkMonitor sharedNetworkMonitor] removeObserver:self forKeyPath:@"contacts"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.destinations = @[];
    if ( _portsAreOurs ) {
        if ( _virtualSource ) MIDIEndpointDispose(_virtualSource);
        MIDIPortDispose(_outputPort);
    }
    MIDIClientDispose(_midiClient);
}

-(NSArray *)availableDestinations {
    MIDINetworkSession *netSession = [MIDINetworkSession defaultSession];
    NSMutableArray * destinations = [NSMutableArray array];
    ItemCount destinationCount = MIDIGetNumberOfDestinations();
    for ( ItemCount i=0; i<destinationCount; i++ ) {
        MIDIEndpointRef endpoint = MIDIGetDestination(i);
        if ( endpoint == _virtualSource || endpoint == netSession.destinationEndpoint ) {
            continue;
        }
        
        SEMIDIEndpoint * destination = [[SEMIDIEndpoint alloc] initWithEndpoint:endpoint];
        
        if ( [destination.name isEqualToString:self.virtualEndpointName] ) {
            continue;
        }
        
        [destinations addObject:destination];
    }
    
    if ( netSession.isEnabled ) {
        for ( MIDINetworkHost * host in [SEMIDINetworkMonitor sharedNetworkMonitor].contacts ) {
            SEMIDINetworkEndpoint *destination = [[SEMIDINetworkEndpoint alloc] initWithEndpoint:netSession.destinationEndpoint host:host];
            [destinations addObject:destination];
        }
    }
    
    return destinations;
}

-(void)sendMIDIPacketList:(const MIDIPacketList *)packetList {
    if ( _virtualSource ) {
        SECheckResult(MIDIReceived(_virtualSource, packetList), "MIDISend");
    }
    @synchronized ( _destinations ) {
        BOOL alreadySentToNetworkEndpoint = NO;
        for ( SEMIDIEndpoint * destination in _destinations ) {
            
            // If we're connected to two network destinations, be sure to only sent to the network endpoint once
            if ( [destination isKindOfClass:[SEMIDINetworkEndpoint class]] ) {
                if ( alreadySentToNetworkEndpoint) {
                    continue;
                }
                alreadySentToNetworkEndpoint = YES;
            }
            
            SECheckResult(MIDISend(_outputPort, destination.endpoint, packetList), "MIDISend");
        }
    }
}

-(void)setDestinations:(NSArray *)destinations {
    if ( _destinations ) {
        for ( SEMIDIEndpoint * destination in self.destinations ) {
            if ( ![destinations containsObject:destination] ) {
                [destination disconnect];
            }
        }
    }
    
    @synchronized ( _destinations ) {
        _destinations = [destinations copy];
    }
    
    if ( _destinations ) {
        for ( SEMIDIEndpoint * destination in _destinations ) {
            [destination connect];
        }
    }
}

-(NSArray *)destinations {
    MIDINetworkSession * networkSession = [MIDINetworkSession defaultSession];
    
    // If any of the destinations are the MIDI network session destination, we need to show those
    // hosts we're connected to, as well as the selected destinations
    if ( !networkSession.isEnabled ) {
        return _destinations;
    }
    
    BOOL hasNetworkDestination = NO;
    for ( SEMIDIEndpoint * destination in _destinations ) {
        if ( destination.endpoint == networkSession.destinationEndpoint ) {
            hasNetworkDestination = YES;
            break;
        }
    }
    
    if ( !hasNetworkDestination ) {
        return _destinations;
    }
    
    NSMutableArray *array = [_destinations mutableCopy];
    for ( MIDINetworkConnection * connection in networkSession.connections ) {
        SEMIDINetworkEndpoint * destination = [[SEMIDINetworkEndpoint alloc] initWithEndpoint:networkSession.destinationEndpoint
                                                                                         host:connection.host];
        if ( ![array containsObject:destination] ) {
            [array addObject:destination];
        }
    }
    
    return array;
}

static void midiNotify(const MIDINotification * message, void * inRefCon) {
    SEMIDIClockSenderCoreMIDIInterface * THIS = (__bridge SEMIDIClockSenderCoreMIDIInterface*)inRefCon;
    
    switch ( message->messageID ) {
        case kMIDIMsgObjectAdded:
        case kMIDIMsgObjectRemoved:
        case kMIDIMsgSetupChanged: {
            if ( message->messageID == kMIDIMsgObjectRemoved ) {
                MIDIObjectAddRemoveNotification * notification = (MIDIObjectAddRemoveNotification *)message;
                SEMIDIEndpoint * destination = [[SEMIDIEndpoint alloc] initWithEndpoint:notification->child];
                if ( [THIS.destinations containsObject:destination] ) {
                    NSMutableArray * destinations = [THIS.destinations mutableCopy];
                    [destinations removeObject:destination];
                    THIS.destinations = destinations;
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [THIS willChangeValueForKey:@"availableDestinations"];
                [THIS didChangeValueForKey:@"availableDestinations"];
            });
            break;
        }
            
        default:
            break;
    }
}

- (NSString*)virtualEndpointName {
    if ( _virtualSource ) {
        CFStringRef name = NULL;
        if ( SECheckResult(MIDIObjectGetStringProperty(_virtualSource, kMIDIPropertyDisplayName, &name), "MIDIObjectGetStringProperty") ) {
            return (__bridge_transfer NSString*)name;
        }
    }
    
    NSString *virtualEndpointName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"];
    if ( !virtualEndpointName ) virtualEndpointName = [NSBundle mainBundle].infoDictionary[(__bridge NSString*)kCFBundleNameKey];
    return virtualEndpointName;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ( context == kNetworkContactsChanged ) {
        // Network contacts list changed; announce corresponding change to available destinations list
        [self willChangeValueForKey:@"availableDestinations"];
        [self didChangeValueForKey:@"availableDestinations"];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

-(void)networkConnectionsChanged:(NSNotification*)notification {
    // Network connections changed; announce corresponding change to destinations list
    [self willChangeValueForKey:@"destinations"];
    [self didChangeValueForKey:@"destinations"];
}

@end
