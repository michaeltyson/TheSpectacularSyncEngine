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
    return 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sources.count;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    SEMIDIEndpoint * source = self.sources[indexPath.row];
    cell.textLabel.text = source.name;
    
    // Show as connected the actually-selected source, plus any connected network hosts if our source is another network host
    cell.accessoryType = [_interface.source isEqual:source]
                            || ([source isKindOfClass:[SEMIDINetworkEndpoint class]]
                                    && _interface.source.endpoint == source.endpoint
                                    && ((SEMIDINetworkEndpoint*)source).connected)
                            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    SEMIDIEndpoint * source = self.sources[indexPath.row];
    
    if ( [_interface.source isEqual:source] ) {
        // Disable source
        _interface.source = nil;
    } else if ( [source isKindOfClass:[SEMIDINetworkEndpoint class]] && _interface.source.endpoint == source.endpoint && ((SEMIDINetworkEndpoint*)source).connected ) {
        // Disconnect a connected network source that isn't our actual source
        [source disconnect];
    } else {
        // Select this source
        _interface.source = source;
    }
    
    [tableView reloadData];
}

@end
