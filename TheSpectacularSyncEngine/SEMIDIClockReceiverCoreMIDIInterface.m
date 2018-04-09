//
//  SEMIDIClockReceiverCoreMIDIInterface.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIClockReceiverCoreMIDIInterface.h"
#import "SEMIDINetworkMonitor.h"

static void * kNetworkContactsChanged = &kNetworkContactsChanged;

@interface SEMIDIClockReceiverCoreMIDIInterface () {
    MIDIClientRef _midiClient;
    BOOL _portsAreOurs;
}
@property (nonatomic, strong, readwrite) SEMIDIClockReceiver * receiver;
@property (nonatomic, readwrite) MIDIPortRef inputPort;
@property (nonatomic, readwrite) MIDIEndpointRef virtualDestination;
@end

@implementation SEMIDIClockReceiverCoreMIDIInterface

-(instancetype)initWithReceiver:(SEMIDIClockReceiver *)receiver {
    MIDIClientRef midiClient;
    if ( !SECheckResult(MIDIClientCreate((__bridge CFStringRef)@"SEMIDIClockReceiver MIDI Client", midiNotify, (__bridge void*)self, &midiClient), "MIDIClientCreate") ) {
        return nil;
    }
    
    MIDIPortRef inputPort;
    if ( !SECheckResult(MIDIInputPortCreate(midiClient, (__bridge CFStringRef)@"SEMIDIClockReceiver MIDI Port", midiRead, (__bridge void*)self, &inputPort), "MIDIInputPortCreate") ) {
        MIDIClientDispose(midiClient);
        return nil;
    }
    
    MIDIEndpointRef virtualDestination;
    if ( SECheckResult(MIDIDestinationCreate(midiClient, (__bridge CFStringRef)self.virtualEndpointName, midiRead, (__bridge void*)self, &virtualDestination), "MIDIDestinationCreate") ) {
        
        // Try to persist unique ID
        SInt32 uniqueID = (SInt32)[[NSUserDefaults standardUserDefaults] integerForKey:@"SEMIDIClockReceiver Unique ID"];
        if ( uniqueID ) {
            if ( MIDIObjectSetIntegerProperty(virtualDestination, kMIDIPropertyUniqueID, uniqueID) == kMIDIIDNotUnique ) {
                uniqueID = 0;
            }
        }
        if ( !uniqueID ) {
            if ( SECheckResult(MIDIObjectGetIntegerProperty(virtualDestination, kMIDIPropertyUniqueID, &uniqueID), "MIDIObjectGetIntegerProperty") ) {
                [[NSUserDefaults standardUserDefaults] setInteger:uniqueID forKey:@"SEMIDIClockReceiver Unique ID"];
            }
        }
    }
    
    if ( !(self = [self initWithReceiver:receiver MIDIClient:midiClient inputPort:inputPort virtualDestination:virtualDestination]) ) return nil;
    
    _portsAreOurs = YES;
    
    return self;
}

-(instancetype)initWithReceiver:(SEMIDIClockReceiver *)receiver inputPort:(MIDIPortRef)inputPort virtualDestination:(MIDIEndpointRef)virtualDestination {
    return [self initWithReceiver:receiver MIDIClient:0 inputPort:inputPort virtualDestination:virtualDestination];
}

-(instancetype)initWithReceiver:(SEMIDIClockReceiver *)receiver MIDIClient:(MIDIClientRef)midiClient inputPort:(MIDIPortRef)inputPort virtualDestination:(MIDIEndpointRef)virtualDestination {
    if ( !(self = [super init]) ) return nil;
    
    NSAssert(virtualDestination, @"You must provide a Virtual MIDI destination");
    NSAssert(inputPort, @"You must provide an input port");
    
    self.receiver = receiver;
    _midiClient = midiClient;
    _inputPort = inputPort;
    _virtualDestination = virtualDestination;
    
    if ( !_midiClient ) {
        if ( !SECheckResult(MIDIClientCreate((__bridge CFStringRef)@"SEMIDIClockReceiver MIDI Client", midiNotify, (__bridge void*)self, &_midiClient), "MIDIClientCreate") ) {
            return nil;
        }
    }
    
    self.source = [[SEMIDIEndpoint alloc] initWithEndpoint:_virtualDestination];
    
    // Watch for changes to network contacts and connections
    [[SEMIDINetworkMonitor sharedNetworkMonitor] addObserver:self forKeyPath:@"contacts" options:0 context:kNetworkContactsChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkConnectionsChanged:) name:MIDINetworkNotificationSessionDidChange object:nil];
    
    return self;
    
}

-(void)dealloc {
    [[SEMIDINetworkMonitor sharedNetworkMonitor] removeObserver:self forKeyPath:@"contacts"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.source = NULL;
    if ( _portsAreOurs ) {
        if ( _virtualDestination ) MIDIEndpointDispose(_virtualDestination);
        MIDIPortDispose(_inputPort);
    }
    MIDIClientDispose(_midiClient);
}

-(NSArray *)availableSources {
    MIDINetworkSession *netSession = [MIDINetworkSession defaultSession];
    NSMutableArray * sources = [NSMutableArray array];
    
    if ( _virtualDestination ) {
        [sources addObject:[[SEMIDIEndpoint alloc] initWithEndpoint:_virtualDestination name:NSLocalizedString(@"Incoming connections", @"")]];
    }
    
    ItemCount sourceCount = MIDIGetNumberOfSources();
    for ( ItemCount i=0; i<sourceCount; i++ ) {
        MIDIEndpointRef endpoint = MIDIGetSource(i);
        if ( endpoint == netSession.sourceEndpoint ) {
            continue;
        }
        
        SEMIDIEndpoint *source = [[SEMIDIEndpoint alloc] initWithEndpoint:endpoint];
        
        if ( [source.name isEqualToString:self.virtualEndpointName] ) {
            continue;
        }
    
        [sources addObject:source];
    }
    
    if ( netSession.isEnabled ) {
        for ( MIDINetworkHost * host in [SEMIDINetworkMonitor sharedNetworkMonitor].contacts ) {
            SEMIDINetworkEndpoint *source = [[SEMIDINetworkEndpoint alloc] initWithEndpoint:netSession.sourceEndpoint host:host];
            [sources addObject:source];
        }
    }
    
    return sources;
}

-(void)setSource:(SEMIDIEndpoint *)source {
    if ( _source == source ) return;
    
    if ( _source && _source.endpoint != _virtualDestination ) {
        SECheckResult(MIDIPortDisconnectSource(_inputPort, _source.endpoint), "MIDIPortDisconnectSource");
        [source disconnect]; // Perform any source-specfic disconnection tasks
    }
    
    if ( [source isKindOfClass:[SEMIDINetworkEndpoint class]] ) {
        // If new source is network, look through available sources and disconnect any network sources that aren't our new source
        for ( SEMIDIEndpoint * availableSource in self.availableSources ) {
            if ( [availableSource isKindOfClass:[SEMIDINetworkEndpoint class]] && ![availableSource isEqual:source] && ((SEMIDINetworkEndpoint*)availableSource).connected ) {
                [availableSource disconnect];
            }
        }
    }
    
    _source = source;
    [_receiver reset];
    
    if ( _source && _source.endpoint != _virtualDestination ) {
        SECheckResult(MIDIPortConnectSource(_inputPort, _source.endpoint, (void*)(intptr_t)_source.endpoint), "MIDIPortConnectSource");
        [source connect]; // Perform any source-specfic connection tasks
    }
}

void SEMIDIClockReceiverCoreMIDIInterfaceReceive(__unsafe_unretained SEMIDIClockReceiverCoreMIDIInterface * THIS, const MIDIPacketList * packetList, MIDIEndpointRef endpoint) {
    midiRead(packetList, (__bridge void*)THIS, (void*)(intptr_t)endpoint);
}

static void midiNotify(const MIDINotification * message, void * inRefCon) {
    SEMIDIClockReceiverCoreMIDIInterface * THIS = (__bridge SEMIDIClockReceiverCoreMIDIInterface*)inRefCon;
    
    switch ( message->messageID ) {
        case kMIDIMsgObjectAdded:
        case kMIDIMsgObjectRemoved:
        case kMIDIMsgSetupChanged: {
            if ( message->messageID == kMIDIMsgObjectRemoved ) {
                MIDIObjectAddRemoveNotification * notification = (MIDIObjectAddRemoveNotification *)message;
                SEMIDIEndpoint * source = [[SEMIDIEndpoint alloc] initWithEndpoint:notification->child];
                if ( [THIS.source isEqual:source] ) {
                    THIS.source = nil;
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [THIS willChangeValueForKey:@"availableSources"];
                [THIS didChangeValueForKey:@"availableSources"];
            });
            break;
        }
        
        default:
            break;
    }
}

static void midiRead(const MIDIPacketList * pktlist, void * readProcRefCon, void * srcConnRefCon) {
    __unsafe_unretained SEMIDIClockReceiverCoreMIDIInterface * THIS = (__bridge SEMIDIClockReceiverCoreMIDIInterface*)readProcRefCon;
    if ( !THIS->_source ) {
        return;
    }
    
    BOOL isVirtualMIDISource = srcConnRefCon == NULL;
    if ( isVirtualMIDISource && THIS->_source.endpoint != THIS->_virtualDestination ) {
        return;
    } else if ( !isVirtualMIDISource && THIS->_source.endpoint != (MIDIEndpointRef)srcConnRefCon ) {
        return;
    }
    
    SEMIDIClockReceiverReceivePacketList(THIS->_receiver, pktlist);
}

- (NSString*)virtualEndpointName {
    if ( _virtualDestination ) {
        CFStringRef name = NULL;
        if ( SECheckResult(MIDIObjectGetStringProperty(_virtualDestination, kMIDIPropertyDisplayName, &name), "MIDIObjectGetStringProperty") ) {
            return (__bridge_transfer NSString*)name;
        }
    }

    NSString *virtualEndpointName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"];
    if ( !virtualEndpointName ) virtualEndpointName = [NSBundle mainBundle].infoDictionary[(__bridge NSString*)kCFBundleNameKey];
    return virtualEndpointName;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ( context == kNetworkContactsChanged ) {
        // Network contacts list changed; announce corresponding change to available sources list
        [self willChangeValueForKey:@"availableSources"];
        [self didChangeValueForKey:@"availableSources"];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

-(void)networkConnectionsChanged:(NSNotification*)notification {
    // Network connections changed; announce corresponding change to available sources list
    [self willChangeValueForKey:@"availableSources"];
    [self didChangeValueForKey:@"availableSources"];
}

@end
