//
//  SEMIDIEndpoint.m
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 13/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIEndpoint.h"
#import "SECommon.h"

@interface SEMIDIEndpoint ()
@property (nonatomic, readwrite) MIDIEndpointRef endpoint;
@property (nonatomic, strong) NSString *name;
@end

@implementation SEMIDIEndpoint
@synthesize name = _name;

-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint {
    return [self initWithEndpoint:endpoint name:nil];
}

-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint name:(NSString *)name {
    if ( !(self = [super init]) ) return nil;
    
    _endpoint = endpoint;
    _name = name;
    
    return self;
}

-(BOOL)isEqual:(id)object {
    return [object isKindOfClass:[self class]] && ((SEMIDIEndpoint*)object).endpoint == _endpoint;
}

-(NSUInteger)hash {
    return (NSUInteger)_endpoint;
}

-(id)copyWithZone:(NSZone*)zone {
    return [[SEMIDIEndpoint allocWithZone:zone] initWithEndpoint:_endpoint];
}

-(NSString *)description {
    return [NSString stringWithFormat:@"<%@: \"%@\" %p", NSStringFromClass([self class]), self.name, self];
}

-(NSString *)name {
    if ( _name ) {
        return _name;
    }
    
    CFStringRef name = NULL;
    if ( !SECheckResult(MIDIObjectGetStringProperty(_endpoint, kMIDIPropertyDisplayName, &name), "MIDIObjectGetStringProperty") ) {
        return nil;
    }
    
    return (__bridge_transfer NSString*)name;
}

-(void)connect {
    
}

-(void)disconnect {
    
}

@end

@interface SEMIDINetworkEndpoint ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong, readonly) MIDINetworkConnection *connection;
@property (nonatomic) BOOL shouldBeConnected;
@end

@implementation SEMIDINetworkEndpoint

-(instancetype)initWithEndpoint:(MIDIEndpointRef)endpoint host:(MIDINetworkHost *)host {
    if ( !(self = [super initWithEndpoint:endpoint]) ) return nil;
    self.host = host;
    return self;
}

-(void)dealloc {
    if ( _timer ) {
        [_timer invalidate];
    }
}

-(BOOL)isEqual:(id)object {
    return [object isKindOfClass:[self class]]
        && ((SEMIDINetworkEndpoint*)object).endpoint == self.endpoint
        && [((SEMIDINetworkEndpoint*)object).host.name isEqualToString:_host.name];
}

-(NSUInteger)hash {
    return ([super hash] * 1283) + _host.name.hash;
}

-(id)copyWithZone:(NSZone*)zone {
    SEMIDINetworkEndpoint * endpoint = [[SEMIDINetworkEndpoint allocWithZone:zone] initWithEndpoint:self.endpoint host:self.host];
    if ( _shouldBeConnected ) {
        [endpoint connect];
    }
    return endpoint;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"<%@: \"%@\" (\"%@\"), %p", NSStringFromClass([self class]), self.name, [super name], self];
}

-(NSString *)name {
    return _host.name;
}

-(void)connect {
    self.shouldBeConnected = YES;
    [self checkConnection];
    if ( !_timer ) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                      target:[[SEWeakRetainingProxy alloc] initWithTarget:self]
                                                    selector:@selector(checkConnection)
                                                    userInfo:nil
                                                     repeats:YES];
    }
}

-(void)disconnect {
    self.shouldBeConnected = NO;
    [self checkConnection];
    if ( _timer ) {
        [_timer invalidate];
        self.timer = nil;
    }
}

-(MIDINetworkConnection *)connection {
    return [[MIDINetworkSession defaultSession].connections filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"host.name = %@", self.name]].anyObject;
}

-(void)checkConnection {
    MIDINetworkConnection *connection = self.connection;
    
    if ( _shouldBeConnected && !connection ) {
        connection = [MIDINetworkConnection connectionWithHost:self.host];
        [[MIDINetworkSession defaultSession] addConnection:connection];
    } else if ( !_shouldBeConnected && connection ) {
        [[MIDINetworkSession defaultSession] removeConnection:connection];
    }
}

-(BOOL)connected {
    return self.connection != nil;
}

@end
