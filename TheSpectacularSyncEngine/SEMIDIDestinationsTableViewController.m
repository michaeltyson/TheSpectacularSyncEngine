//
//  SEMIDIDestinationsTableViewController.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDIDestinationsTableViewController.h"
#import "SEMIDIClockSenderCoreMIDIInterface.h"

static void * kAvailableDestinationsChanged = &kAvailableDestinationsChanged;

@interface SEMIDIDestinationsTableViewController ()
@property (nonatomic) NSArray *destinations;
@end

@implementation SEMIDIDestinationsTableViewController

-(instancetype)init {
    if ( !(self = [super initWithStyle:UITableViewStyleGrouped]) ) return nil;
    return self;
}

-(void)dealloc {
    self.interface = nil;
}

-(void)setInterface:(SEMIDIClockSenderCoreMIDIInterface *)interface {
    if ( _interface ) {
        [_interface removeObserver:self forKeyPath:@"availableDestinations"];
    }
    
    _interface = interface;
    
    if ( _interface ) {
        [_interface addObserver:self forKeyPath:@"availableDestinations" options:0 context:kAvailableDestinationsChanged];
    }
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ( context == kAvailableDestinationsChanged ) {
        self.destinations = nil;
        [self.tableView reloadData];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

-(NSArray *)destinations {
    if ( !_destinations ) {
        self.destinations = _interface.availableDestinations;
    }
    
    return _destinations;
}

#pragma mark - Table view data destination

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ( section ) {
        case 0:
            return self.destinations.count;
        default:
            return 0;
    }
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    SEMIDIClockSenderCoreMIDIDestination * destination = self.destinations[indexPath.row];
    cell.textLabel.text = destination.name;
    cell.accessoryType = [_interface.destinations containsObject:destination] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    if ( [_interface.destinations containsObject:self.destinations[indexPath.row]] ) {
        NSMutableArray * destinations = _interface.destinations ? [_interface.destinations mutableCopy] : [NSMutableArray array];
        [destinations removeObject:self.destinations[indexPath.row]];
        _interface.destinations = destinations;
    } else {
        _interface.destinations = [_interface.destinations ? _interface.destinations : [NSArray array] arrayByAddingObject:self.destinations[indexPath.row]];
    }
    
    [tableView reloadData];
}

@end
