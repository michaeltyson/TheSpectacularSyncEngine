//
//  SEMIDISourcesTableViewController.m
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 7/01/2015.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

#import "SEMIDISourcesTableViewController.h"
#import "SEMIDIClockReceiverCoreMIDIInterface.h"

static void * kAvailableSourcesChanged = &kAvailableSourcesChanged;

@interface SEMIDISourcesTableViewController ()
@property (nonatomic) NSArray *sources;
@end

@implementation SEMIDISourcesTableViewController

-(instancetype)init {
    if ( !(self = [super initWithStyle:UITableViewStyleGrouped]) ) return nil;
    return self;
}

-(void)dealloc {
    self.interface = nil;
}

-(void)setInterface:(SEMIDIClockReceiverCoreMIDIInterface *)interface {
    if ( _interface ) {
        [_interface removeObserver:self forKeyPath:@"availableSources"];
    }
    
    _interface = interface;
    
    if ( _interface ) {
        [_interface addObserver:self forKeyPath:@"availableSources" options:0 context:kAvailableSourcesChanged];
    }
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ( context == kAvailableSourcesChanged ) {
        self.sources = nil;
        [self.tableView reloadData];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

-(NSArray *)sources {
    if ( !_sources ) {
        self.sources = _interface.availableSources;
    }
    
    return _sources;
}

#pragma mark - Table view data source

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ( section ) {
        case 0:
            return 1;
        case 1:
            return self.sources.count;
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
    
    switch ( indexPath.section ) {
        case 0: {
            cell.textLabel.text = NSLocalizedString(@"Virtual MIDI Source", @"Title");
            cell.accessoryType = _interface.source == NULL ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        }
        case 1: {
            SEMIDIClockReceiverCoreMIDISource * source = self.sources[indexPath.row];
            cell.textLabel.text = source.name;
            cell.accessoryType = [_interface.source isEqual:source] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        }
        default:
            break;
    }
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    _interface.source = indexPath.section == 0 ? NULL : self.sources[indexPath.row];
    
    [tableView reloadData];
}

@end
