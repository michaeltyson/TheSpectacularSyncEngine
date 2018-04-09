//
//  TPDismissSegue.m
//
//  Created by Michael Tyson on 2/11/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "TPDismissSegue.h"

@implementation TPDismissSegue

-(void)perform {
    UIViewController *sourceViewController = self.sourceViewController;
    [sourceViewController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
