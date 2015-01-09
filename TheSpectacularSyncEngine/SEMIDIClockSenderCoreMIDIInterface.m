//
//  SEMIDIClockSenderCoreMIDIInterface.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 1/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIClockSenderCoreMIDIInterface.h"

#define checkResult(result,operation) (_checkResult((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        int fourCC = CFSwapInt32HostToBig(result);
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&fourCC);
        return NO;
    }
    return YES;
}

@interface SEMIDIClockSenderCoreMIDIInterface () {
    MIDIClientRef _midiClient;
    BOOL _portsAreOurs;
}
@property (nonatomic, readwrite) MIDIPortRef outputPort;
@property (nonatomic, readwrite) MIDIEndpointRef virtualSource;
@end

@interface SEMIDIClockSenderCoreMIDIDestination ()
-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint;
@end

@implementation SEMIDIClockSenderCoreMIDIInterface

-(instancetype)init {
    
    MIDIClientRef midiClient;
    if ( !checkResult(MIDIClientCreate((__bridge CFStringRef)@"SEMIDIClockSender MIDI Client", midiNotify, (__bridge void*)self, &midiClient), "MIDIClientCreate") ) {
        return nil;
    }
    
    MIDIPortRef outputPort;
    if ( !checkResult(MIDIOutputPortCreate(midiClient, (__bridge CFStringRef)@"SEMIDIClockSender MIDI Port", &outputPort), "MIDIOutputPortCreate") ) {
        MIDIClientDispose(midiClient);
        return nil;
    }
    
    MIDIEndpointRef virtualSource;
    if ( checkResult(MIDISourceCreate(midiClient, (__bridge CFStringRef)self.virtualSourceEndpointName, &virtualSource), "MIDISourceCreate") ) {
        
        // Try to persist unique ID
        SInt32 uniqueID = (SInt32)[[NSUserDefaults standardUserDefaults] integerForKey:@"SEMIDIClockSender Unique ID"];
        if ( uniqueID ) {
            if ( MIDIObjectSetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, uniqueID) == kMIDIIDNotUnique ) {
                uniqueID = 0;
            }
        }
        if ( !uniqueID ) {
            if ( checkResult(MIDIObjectGetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, &uniqueID), "MIDIObjectGetIntegerProperty") ) {
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
    
    _midiClient = midiClient;
    _outputPort = outputPort;
    _virtualSource = virtualSource;
    
    if ( !_midiClient ) {
        MIDIClientRef midiClient;
        if ( !checkResult(MIDIClientCreate((__bridge CFStringRef)@"SEMIDIClockSender MIDI Client", midiNotify, (__bridge void*)self, &midiClient), "MIDIClientCreate") ) {
            return nil;
        }
    }
    
    return self;
}

-(void)dealloc {
    if ( _portsAreOurs ) {
        if ( _virtualSource ) MIDIEndpointDispose(_virtualSource);
        MIDIPortDispose(_outputPort);
    }
    MIDIClientDispose(_midiClient);
}

-(NSArray *)availableDestinations {
    NSMutableArray * destinations = [NSMutableArray array];
    ItemCount destinationCount = MIDIGetNumberOfDestinations();
    for ( ItemCount i=0; i<destinationCount; i++ ) {
        MIDIEndpointRef endpoint = MIDIGetDestination(i);
        if ( endpoint == _virtualSource ) continue;
        
        SEMIDIClockSenderCoreMIDIDestination * destination = [[SEMIDIClockSenderCoreMIDIDestination alloc] initWithEndpoint:endpoint];
        if ( [destination.name isEqualToString:self.virtualSourceEndpointName] ) continue;
        
        [destinations addObject:destination];
    }
    return destinations;
}

-(void)sendMIDIPacketList:(const MIDIPacketList *)packetList {
    if ( _virtualSource ) {
        checkResult(MIDIReceived(_virtualSource, packetList), "MIDISend");
    }
    for ( SEMIDIClockSenderCoreMIDIDestination * destination in self.destinations ) {
        checkResult(MIDISend(_outputPort, destination.endpoint, packetList), "MIDISend");
    }
}

static void midiNotify(const MIDINotification * message, void * inRefCon) {
    SEMIDIClockSenderCoreMIDIInterface * THIS = (__bridge SEMIDIClockSenderCoreMIDIInterface*)inRefCon;
    
    switch ( message->messageID ) {
        case kMIDIMsgObjectAdded:
        case kMIDIMsgObjectRemoved: {
            if ( message->messageID == kMIDIMsgObjectRemoved ) {
                MIDIObjectAddRemoveNotification * notification = (MIDIObjectAddRemoveNotification *)message;
                SEMIDIClockSenderCoreMIDIDestination * destination = [[SEMIDIClockSenderCoreMIDIDestination alloc] initWithEndpoint:notification->child];
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

- (NSString*)virtualSourceEndpointName {
    NSString *virtualSourceName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"];
    if ( !virtualSourceName ) virtualSourceName = [NSBundle mainBundle].infoDictionary[(__bridge NSString*)kCFBundleNameKey];
    return virtualSourceName;
}

@end

@implementation SEMIDIClockSenderCoreMIDIDestination
@dynamic name;

-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint {
    if ( !(self = [super init]) ) return nil;
    
    _endpoint = endpoint;
    
    return self;
}

-(BOOL)isEqual:(id)object {
    return [object isKindOfClass:[self class]] && ((SEMIDIClockSenderCoreMIDIDestination*)object).endpoint == _endpoint;
}

-(NSUInteger)hash {
    return (NSUInteger)_endpoint;
}

-(id)copyWithZone:(NSZone*)zone {
    return [[SEMIDIClockSenderCoreMIDIDestination allocWithZone:zone] initWithEndpoint:_endpoint];
}

-(NSString *)name {
    CFStringRef name = NULL;
    if ( !checkResult(MIDIObjectGetStringProperty(_endpoint, kMIDIPropertyDisplayName, &name), "MIDIObjectGetStringProperty") ) {
        return nil;
    }
    return (__bridge_transfer NSString*)name;
}

@end
