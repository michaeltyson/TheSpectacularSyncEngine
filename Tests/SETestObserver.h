//
//  SETestObserver.h
//  TheSpectacularSyncEngine
//
//  Created by Michael Tyson on 31/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SETestObserver : NSObject
-(void)reset;
-(void)notification:(NSNotification*)notification;
@property (nonatomic) NSArray *observations;
@property (nonatomic) NSArray *notifications;
@end
