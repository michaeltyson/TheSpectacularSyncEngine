//
//  SEMIDIClockReceiverCoreMIDIInterface.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIClockReceiverCoreMIDIInterface.h"

#define checkResult(result,operation) (_checkResult((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        int fourCC = CFSwapInt32HostToBig(result);
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&fourCC);
        return NO;
    }
    return YES;
}

@interface SEMIDIClockReceiverCoreMIDIInterface () {
    MIDIClientRef _midiClient;
}
@property (nonatomic, strong, readwrite) SEMIDIClockReceiver * receiver;
@property (nonatomic, readwrite) MIDIPortRef inputPort;
@property (nonatomic, readwrite) MIDIEndpointRef virtualDestination;
@end

@interface SEMIDIClockReceiverCoreMIDISource ()
-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint;
@end

@implementation SEMIDIClockReceiverCoreMIDIInterface

-(instancetype)initWithReceiver:(SEMIDIClockReceiver *)receiver {
    if ( !(self = [super init]) ) return nil;
    
    self.receiver = receiver;
    
    if ( !checkResult(MIDIClientCreate((__bridge CFStringRef)@"SEMIDIClockReceiver MIDI Client", midiNotify, (__bridge void*)self, &_midiClient), "MIDIClientCreate") ) {
        return nil;
    }
    
    if ( !checkResult(MIDIInputPortCreate(_midiClient, (__bridge CFStringRef)@"SEMIDIClockReceiver MIDI Port", midiRead, (__bridge void*)self, &_inputPort), "MIDIInputPortCreate") ) {
        MIDIClientDispose(_midiClient);
        return nil;
    }
    
    
    if ( checkResult(MIDIDestinationCreate(_midiClient, (__bridge CFStringRef)self.virtualDestinationEndpointName, midiRead, (__bridge void*)self, &_virtualDestination), "MIDIDestinationCreate") ) {
        
        // Try to persist unique ID
        SInt32 uniqueID = (SInt32)[[NSUserDefaults standardUserDefaults] integerForKey:@"SEMIDIClockReceiver Unique ID"];
        if ( uniqueID ) {
            if ( MIDIObjectSetIntegerProperty(_virtualDestination, kMIDIPropertyUniqueID, uniqueID) == kMIDIIDNotUnique ) {
                uniqueID = 0;
            }
        }
        if ( !uniqueID ) {
            if ( checkResult(MIDIObjectGetIntegerProperty(_virtualDestination, kMIDIPropertyUniqueID, &uniqueID), "MIDIObjectGetIntegerProperty") ) {
                [[NSUserDefaults standardUserDefaults] setInteger:uniqueID forKey:@"SEMIDIClockReceiver Unique ID"];
            }
        }
    }

    return self;
}

-(void)dealloc {
    if ( _source ) MIDIPortDisconnectSource(_inputPort, _source.endpoint);
    if ( _virtualDestination ) MIDIEndpointDispose(_virtualDestination);
    MIDIPortDispose(_inputPort);
    MIDIClientDispose(_midiClient);
}

-(NSArray *)availableSources {
    NSMutableArray * sources = [NSMutableArray array];
    ItemCount sourceCount = MIDIGetNumberOfSources();
    for ( ItemCount i=0; i<sourceCount; i++ ) {
        MIDIEndpointRef endpoint = MIDIGetSource(i);
        if ( endpoint == _virtualDestination ) continue;
        
        SEMIDIClockReceiverCoreMIDISource *source = [[SEMIDIClockReceiverCoreMIDISource alloc] initWithEndpoint:endpoint];
        if ( [source.name isEqualToString:self.virtualDestinationEndpointName] ) continue;
        
        [sources addObject:source];
    }
    return sources;
}

-(void)setSource:(SEMIDIClockReceiverCoreMIDISource *)source {
    if ( _source ) {
        checkResult(MIDIPortDisconnectSource(_inputPort, _source.endpoint), "MIDIPortDisconnectSource");
    }
    
    _source = [source copy];
    [_receiver reset];
    
    if ( _source ) {
        checkResult(MIDIPortConnectSource(_inputPort, _source.endpoint, (__bridge void*)_source), "MIDIPortConnectSource");
    }
}

static void midiNotify(const MIDINotification * message, void * inRefCon) {
    SEMIDIClockReceiverCoreMIDIInterface * THIS = (__bridge SEMIDIClockReceiverCoreMIDIInterface*)inRefCon;
    
    switch ( message->messageID ) {
        case kMIDIMsgObjectAdded:
        case kMIDIMsgObjectRemoved: {
            if ( message->messageID == kMIDIMsgObjectRemoved ) {
                MIDIObjectAddRemoveNotification * notification = (MIDIObjectAddRemoveNotification *)message;
                SEMIDIClockReceiverCoreMIDISource * source = [[SEMIDIClockReceiverCoreMIDISource alloc] initWithEndpoint:notification->child];
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
    SEMIDIClockReceiverCoreMIDIInterface * THIS = (__bridge SEMIDIClockReceiverCoreMIDIInterface*)readProcRefCon;
    if ( srcConnRefCon != (__bridge void*)THIS->_source ) {
        // Ignore messages coming from other sources
        return;
    }
    
    [THIS->_receiver receivePacketList:pktlist];
}

- (NSString*)virtualDestinationEndpointName {
    NSString *virtualDestinationName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"];
    if ( !virtualDestinationName ) virtualDestinationName = [NSBundle mainBundle].infoDictionary[(__bridge NSString*)kCFBundleNameKey];
    return virtualDestinationName;
}

@end

@implementation SEMIDIClockReceiverCoreMIDISource
@dynamic name;

-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint {
    if ( !(self = [super init]) ) return nil;
    
    _endpoint = endpoint;
    
    return self;
}

-(BOOL)isEqual:(id)object {
    return [object isKindOfClass:[self class]] && ((SEMIDIClockReceiverCoreMIDISource*)object).endpoint == _endpoint;
}

-(NSUInteger)hash {
    return (NSUInteger)_endpoint;
}

-(id)copyWithZone:(NSZone*)zone {
    return [[SEMIDIClockReceiverCoreMIDISource allocWithZone:zone] initWithEndpoint:_endpoint];
}

-(NSString *)name {
    CFStringRef name = NULL;
    if ( !checkResult(MIDIObjectGetStringProperty(_endpoint, kMIDIPropertyDisplayName, &name), "MIDIObjectGetStringProperty") ) {
        return nil;
    }
    return (__bridge_transfer NSString*)name;
}

@end
