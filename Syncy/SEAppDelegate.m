//
//  SEAppDelegate.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEAppDelegate.h"

#import "SEMainViewController.h"

@interface SEAppDelegate ()

@end


@implementation SEAppDelegate


-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    

//    [[UIApplication sharedApplication] setIdleTimerDisabled:YES]; ???
    
    if ( [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone ) {
        [[UIApplication sharedApplication] setStatusBarHidden:YES];
    }
    
    return YES;
}


@end
