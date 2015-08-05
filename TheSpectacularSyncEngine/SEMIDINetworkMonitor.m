//
//  SEMIDINetworkMonitor.m
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 13/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDINetworkMonitor.h"
#import <CoreMIDI/CoreMIDI.h>
#import <netinet/in.h>
#import <ifaddrs.h>

static void * kMIDINetworkSessionEnabledChanged = &kMIDINetworkSessionEnabledChanged;

@interface SEMIDINetworkMonitor () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, strong) NSNetServiceBrowser * netServiceBrowser;
@property (nonatomic, strong) NSMutableArray * resolvingNetServices;
@property (nonatomic, strong, readwrite) NSSet * contacts;
@end


@implementation SEMIDINetworkMonitor

+(instancetype)sharedNetworkMonitor {
    static SEMIDINetworkMonitor * singletonInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ( !singletonInstance ) {
            singletonInstance = [SEMIDINetworkMonitor new];
        }
    });
    
    return singletonInstance;
}

-(instancetype)init {
    if ( !(self = [super init]) ) return nil;
    
    self.contacts = [NSMutableSet set];
    
    if ( [MIDINetworkSession defaultSession].isEnabled ) {
        [self start];
    }
    
    [[MIDINetworkSession defaultSession] addObserver:self forKeyPath:@"enabled" options:0 context:kMIDINetworkSessionEnabledChanged];
    
    return self;
}

-(void)dealloc {
    [self stop];
    [[MIDINetworkSession defaultSession] removeObserver:self forKeyPath:@"enabled"];
}

-(void)start {
    if ( _netServiceBrowser ) {
        return;
    }
    
    // Begin searching for network services
    self.netServiceBrowser = [NSNetServiceBrowser new];
    _netServiceBrowser.delegate = self;
    [_netServiceBrowser searchForServicesOfType:MIDINetworkBonjourServiceType inDomain:@""];
}

-(void)stop {
    if ( !_netServiceBrowser ) {
        return;
    }
    
    [_netServiceBrowser stop];
    for ( NSNetService * service in _resolvingNetServices ) {
        [service stop];
    }
    [_resolvingNetServices removeAllObjects];
    
    self.netServiceBrowser = nil;
    
    [[self mutableSetValueForKey:@"contacts"] removeAllObjects];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ( context == kMIDINetworkSessionEnabledChanged ) {
        BOOL enabled = [MIDINetworkSession defaultSession].isEnabled;
        
        if ( enabled && !_netServiceBrowser ) {
            [self start];
        } else if ( !enabled && _netServiceBrowser ) {
            [self stop];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Service browser delegate

-(void)netServiceBrowser:(NSNetServiceBrowser *)aBrowser didFindService:(NSNetService *)service moreComing:(BOOL)more {
    // Spotted a new service; resolve it
    if ( !_resolvingNetServices ) self.resolvingNetServices = [NSMutableArray array];
    [_resolvingNetServices addObject:service];
    service.delegate = self;
    [service resolveWithTimeout:5];
}

-(void)netServiceBrowser:(NSNetServiceBrowser *)aBrowser didRemoveService:(NSNetService *)service moreComing:(BOOL)more {
    // Service went away; remove it
    MIDINetworkHost* outgoingHost = [[_contacts filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"name = %@", service.name]] anyObject];
    if ( outgoingHost ) {
        [[self mutableSetValueForKey:@"contacts"] removeObject:outgoingHost];
    }
}

-(void)netServiceDidResolveAddress:(NSNetService *)service {
    // Resolved the service
    [_resolvingNetServices removeObject:service];
    
    if ( [self serviceIsSelf:service] ) {
        // Service is this host - ignore it
        return;
    }
    
    // Add to contacts, if not already there
    if ( [[_contacts filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"name = %@", service.name]] count] == 0 ) {
        [[self mutableSetValueForKey:@"contacts"] addObject:[MIDINetworkHost hostWithName:service.name netService:service]];
    }
    
    // Add to MIDINetworkSession's contacts, too
    if ( [[[MIDINetworkSession defaultSession].contacts filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"name = %@", service.name]] count] == 0 ) {
        [[MIDINetworkSession defaultSession] addContact:[MIDINetworkHost hostWithName:service.name netService:service]];
    }
}

-(void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)errorDict {
    [_resolvingNetServices removeObject:service];
    NSLog(@"Could not resolve network MIDI service %@: %@", service, errorDict);
}


-(BOOL)serviceIsSelf:(NSNetService*)service {
    // Check to see if service is actually this host
    struct ifaddrs* ifaddrs;
    if ( getifaddrs(&ifaddrs) == 0 ) {
        BOOL local = NO;
        
        struct ifaddrs* addr = ifaddrs;
        while ( addr != NULL ) {
            const struct sockaddr* myaddr = (const struct sockaddr*)addr->ifa_addr;
            if ( myaddr->sa_family != AF_INET && myaddr->sa_family != AF_INET6 ) {
                addr = addr->ifa_next;
                continue;
            }
            
            for ( NSData* addressData in [service addresses] ) {
                const struct sockaddr* serviceaddr = [addressData bytes];
                if ( (myaddr->sa_family == AF_INET && serviceaddr->sa_family == AF_INET && !memcmp(&((const struct sockaddr_in*)serviceaddr)->sin_addr.s_addr, &((const struct sockaddr_in*)myaddr)->sin_addr.s_addr, sizeof(in_addr_t)))
                    || (myaddr->sa_family == AF_INET6 && serviceaddr->sa_family == AF_INET6 && !memcmp(&((const struct sockaddr_in6*)serviceaddr)->sin6_addr.s6_addr, &((const struct sockaddr_in6*)myaddr)->sin6_addr.s6_addr, sizeof(struct in6_addr))) ) {
                    local = YES;
                    break;
                }
            }
            
            if (local) break;
            addr = addr->ifa_next;
        }
        
        freeifaddrs(ifaddrs);
        if ( local ) {
            return YES;
        }
    }
    
    return NO;
}

@end
