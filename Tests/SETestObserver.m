//
//  SETestObserver.m
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 31/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SETestObserver.h"

@implementation SETestObserver

-(instancetype)init {
    if ( !(self = [super init]) ) return nil;
    
    self.observations = [NSMutableArray array];
    self.notifications = [NSMutableArray array];
    
    return self;
}

-(void)reset {
    [(NSMutableArray*)_notifications removeAllObjects];
    [(NSMutableArray*)_observations removeAllObjects];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [(NSMutableArray*)_observations addObject:keyPath];
}

-(void)notification:(NSNotification*)notification {
    [(NSMutableArray*)_notifications addObject:notification];
}

@end
