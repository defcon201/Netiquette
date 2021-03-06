//
//  TableViewController.m
//  Netiquette
//
//  Created by Patrick Wardle on 7/20/19.
//  Copyright © 2019 Objective-See. All rights reserved.
//

//id (tag) for detailed text in category table
#define TABLE_ROW_NAME_TAG 100

//id (tag) for detailed text in category table
#define TABLE_ROW_SUB_TEXT_TAG 101

#define BUTTON_SAVE         10001
#define BUTTON_LOGO         10002
#define BUTTON_REFRESH      10003
#define BUTTON_SHOW_APPLE   10004

#import "Event.h"
#import "CustomRow.h"
#import "utilities.h"
#import "TableViewController.h"

@implementation TableViewController

@synthesize items;
@synthesize collapsedItems;
@synthesize processedItems;

//perform some init's
-(void)awakeFromNib
{
    //once
    static dispatch_once_t once;
    
    dispatch_once (&once, ^{
        
        //only generate events end events
        self.filterBox.sendsWholeSearchString = YES;
        
        //alloc
        self.collapsedItems = [NSMutableDictionary dictionary];
        
        //pre-req for color of overlay
        self.overlay.wantsLayer = YES;
        
        //round overlay's corners
        self.overlay.layer.cornerRadius = 20.0;
        
        //mask overlay
        self.overlay.layer.masksToBounds = YES;
        
        //set overlay's view color to gray
        self.overlay.layer.backgroundColor = NSColor.lightGrayColor.CGColor;
        
        //set (default) scanning msg
        self.activityMessage.stringValue = @"Enumerating Network Connections...";
        
        //show overlay
        self.overlay.hidden = NO;
        
        //show activity indicator
        self.activityIndicator.hidden = NO;
        
        //start activity indicator
        [self.activityIndicator startAnimation:nil];
        
    });
    
    return;
}

//update outline view
-(void)update:(OrderedDictionary*)updatedItems
{
    //selected row
    __block NSInteger selectedRow = -1;
    
    //item's (new?) row
    __block NSInteger itemRow = -1;
    
    //currently selected item
    __block id selectedItem = nil;
    
    //once
    static dispatch_once_t once;
    
    //user turned off refresh?
    if(NSControlStateValueOff == self.refreshButton.state)
    {
        //bail
        goto bail;
    }
    
    //sync
    // filter & reload
    @synchronized (self)
    {

    //update
    self.items = updatedItems;
        
    //get currently selected row
    // default to first row if this fails
    selectedRow = self.outlineView.selectedRow;
    if(-1 == selectedRow)
    {
        //default
        selectedRow = 0;
    }
        
    //grab selected item
    selectedItem = [self.outlineView itemAtRow:selectedRow];
    
    //filter
    self.processedItems = [self filter];
        
    //first time
    // remove/update
    dispatch_once(&once, ^{
        
        //hide activity indicator
        self.activityIndicator.hidden = YES;
        
        //nothing found?
        // update overlay, then fade out
        if(0 == self.processedItems.count)
        {
            //ignore apple?
            // set message about 3rd-party
            if(NSControlStateValueOn == self.filterButton.state)
            {
                //set msg
                self.activityMessage.stringValue = @"No (3rd-party) Network Connections Detected";
            }
            
            //full scan
            // set message about all
            else
            {
                //set msg
                self.activityMessage.stringValue = @"No Network Connections Detected";
            }
            
            //fade-out overlay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                
                //begin grouping
                [NSAnimationContext beginGrouping];
                
                //set duration
                [[NSAnimationContext currentContext] setDuration:2.0];
                
                //fade out
                [[self.overlay animator] removeFromSuperview];
                
                //end grouping
                [NSAnimationContext endGrouping];
                
            });
        }
        
        else
        {
            //hide overlay
            self.overlay.hidden = YES;
        }
    });
    
    //dbg msg
    //NSLog(@"reloading table");
    
    //begin updates
    [self.outlineView beginUpdates];
    
    //full reload
    [self.outlineView reloadData];
    
    //auto expand
    [self.outlineView expandItem:nil expandChildren:YES];
    
    //end updates
    [self.outlineView endUpdates];
    
    //get selected item's (new) row
    itemRow = [self.outlineView rowForItem:selectedItem];
    if(-1 != itemRow)
    {
        //set
        selectedRow = itemRow;
    }
        
    //prev selected now beyond bounds?
    // just default to select last row...
    selectedRow = MIN(selectedRow, (self.outlineView.numberOfRows-1));
    
    //(re)select
    dispatch_async(dispatch_get_main_queue(),
    ^{
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
    });
        
    } //sync
    
bail:
        
    return;
}

//detect when user collapses a row
-(void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    //item
    OrderedDictionary* item = nil;
    
    //pid
    NSNumber* pid = nil;
    
    //grab item
    item = notification.userInfo[@"NSObject"];
    if(YES != [item isKindOfClass:[OrderedDictionary class]])
    {
        //bail
        goto bail;
    }
    
    //grab pid
    pid = [NSNumber numberWithInt:((Event*)[[item allValues] firstObject]).process.pid];
    
    //save
    self.collapsedItems[pid] = item;
    
bail:
    
    return;
}

//determine if item should be collapsed
// basically, if user has collapsed it, leave it collapsed (on reload)
-(BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
{
    //flag
    // default to 'YES'
    BOOL shouldExpand = YES;
    
    //pid
    NSNumber* pid = nil;
    
    //grab pid
    pid = [NSNumber numberWithInt:((Event*)[[item allValues] firstObject]).process.pid];
    
    //item was (user) collapsed?
    if(nil != self.collapsedItems[pid])
    {
        //'new' item
        // means auto-reloaded, so leave collapsed
        if(self.collapsedItems[pid] != item)
        {
            //set flag
            shouldExpand = NO;
            
            //insert
            self.collapsedItems[pid] = item;
        }
        //same item
        // means user is attempting to (re)expand
        else
        {
            //remove
            [self.collapsedItems removeObjectForKey:pid];
        }
    }

    return shouldExpand;
}

//number of the children
-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    //# of children
    // root: all
    // non-root, just items in item
    return (nil == item) ? self.processedItems.count : [item count];
}

//processes are expandable
// these items are built from items of type array
-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return (YES == [item isKindOfClass:[OrderedDictionary class]]);
}

//return child
-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    //child
    id child = nil;
    
    //key
    id key = nil;
    
    //root item?
    // 'child' it just top level item
    if(nil == item)
    {
        //key
        key = [self.processedItems keyAtIndex:index];
        
        //child
        child = [self.processedItems objectForKey:key];
        
    }
    //otherwise
    // child is event at index
    else
    {
        //key
        key = [item keyAtIndex:index];
        
        //child
        child = [item objectForKey:key];
    }
    
    return child;
}

//return custom row for view
// allows highlighting, etc...
-(NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item
{
    //row view
    CustomRow* rowView = nil;
    
    //row ID
    static NSString* const kRowIdentifier = @"RowView";
    
    //try grab existing row view
    rowView = [self.outlineView makeViewWithIdentifier:kRowIdentifier owner:self];
    
    //make new if needed
    if(nil == rowView)
    {
        //create new
        // ->size doesn't matter
        rowView = [[CustomRow alloc] initWithFrame:NSZeroRect];
        
        //set row ID
        rowView.identifier = kRowIdentifier;
    }
    
    return rowView;
}

//table delegate method
// return new cell for row
-(NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    //view
    NSView* cell = nil;
    
    //first event
    Event* event = nil;
    
    //first column
    // process or connection
    if(tableColumn == self.outlineView.tableColumns[0])
    {
        //root item?
        // will be a array of (per-process) connections
        // grab first (could be any) process obj, and config cell
        if(YES == [item isKindOfClass:[OrderedDictionary class]])
        {
            //grab firt event
            event = [[item allValues] firstObject];
            
            //create/configure process cell
            cell = [self createProcessCell:event.process];
        }
        //child
        // create/configure event cell
        else
        {
            //create/configure process cell
            cell = [self createConnectionCell:item];
        }
    }
    //all other columns
    // init a basic cell
    else
    {
        //sanity check
        if(YES != [item isKindOfClass:[Event class]])
        {
            //bail
            goto bail;
        }
        
        //init table cell
        cell = [self.outlineView makeViewWithIdentifier:@"simpleCell" owner:self];
        
        //reset text
        ((NSTableCellView*)cell).textField.stringValue = @"";
        
        //2nd column: protocol
        if(tableColumn  == self.outlineView.tableColumns[1])
        {
            //set protocol
            ((NSTableCellView*)cell).textField.stringValue = ((Event*)item).provider;
        }
        
        //3rd column: interface
        if(tableColumn  == self.outlineView.tableColumns[2])
        {
            //set interface
            if(nil != ((Event*)item).interface)
            {
                //interface
                ((NSTableCellView*)cell).textField.stringValue = ((Event*)item).interface;
            }
        }
        
        //4th column: for (tcp) events: state
        if(tableColumn  == self.outlineView.tableColumns[3])
        {
            //set state
            if(nil != ((Event*)item).tcpState)
            {
                //state
                ((NSTableCellView*)cell).textField.stringValue = ((Event*)item).tcpState;
            }
        }
    }
    
bail:
    
    return cell;

}

//create & customize process cell
// this are the root cells,
-(NSTableCellView*)createProcessCell:(Process*)process
{
    //item cell
    NSTableCellView* processCell = nil;
    
    //process name + pid
    NSString* name = nil;
    
    //process path
    NSString* path = nil;
    
    //create cell
    processCell = [self.outlineView makeViewWithIdentifier:@"processCell" owner:self];
    
    //generate icon
    if(nil == process.binary.icon)
    {
        //generate
        [process.binary getIcon];
    }
    
    //set icon
    processCell.imageView.image = process.binary.icon;
    
    //init process name/pid
    name = [NSString stringWithFormat:@"%@ (pid: %d)", (nil != process.binary.name) ? process.binary.name : @"unknown", process.pid];
    
    //set main text (process name+pid)
    processCell.textField.stringValue = name;

    //init process path
    path = (nil != process.binary.path) ? process.binary.path : @"unknown";
    
    //set sub text (process path)
    [[processCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:path];
    
    //set detailed text color to gray
    ((NSTextField*)[processCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG]).textColor = [NSColor secondaryLabelColor];
    
    return processCell;
}
//create & customize connection cell
-(NSTableCellView*)createConnectionCell:(Event*)event
{
    //item cell
    NSTableCellView* cell = nil;
    
    //create cell
    cell = [self.outlineView makeViewWithIdentifier:@"simpleCell" owner:self];
    
    //reset text
    ((NSTableCellView*)cell).textField.stringValue = @"";

    //no remote addr/port for listen
    if(YES == [event.tcpState isEqualToString:@"Listen"])
    {
        //set main text
        cell.textField.stringValue = [NSString stringWithFormat:@"%@:%@", event.localAddress[KEY_ADDRRESS], event.localAddress[KEY_PORT]];
    }
    
    //no remote addr/port for udp
    else if(YES == [event.provider isEqualToString:@"UDP"])
    {
        //set main text
        cell.textField.stringValue = [NSString stringWithFormat:@"%@:%@ ->", event.localAddress[KEY_ADDRRESS], event.localAddress[KEY_PORT]];
    }
    //show remote addr/port for all others...
    else
    {
        //set main text
        cell.textField.stringValue = [NSString stringWithFormat:@"%@:%@ -> %@:%@", event.localAddress[KEY_ADDRRESS], event.localAddress[KEY_PORT], event.remoteAddress[KEY_ADDRRESS], event.remoteAddress[KEY_PORT]];
    }

    return cell;
}

//method to toggle apple procs
// filter, then reload all items
-(void)toggleAppleProcs {
    
    //call into filter
    @synchronized (self)
    {
        //filter
        self.processedItems = [self filter];
        
        //reload
        [self.outlineView reloadData];
        
        //default to all expanded
        [self.outlineView expandItem:nil expandChildren:YES];
        
        //scroll to top
        [self.outlineView scrollRowToVisible:0];
        
        //select top row
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    
    return;
}

//button handler
// save, open product url, toggle view, etc...
-(IBAction)buttonHandler:(id)sender {
    
    //switch on action
    switch (((NSButton*)sender).tag)
    {
        //save
        case BUTTON_SAVE:
            [self saveResults];
            break;
            
        //logo
        case BUTTON_LOGO:
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:PRODUCT_URL]];
            break;
            
        //show/hide apple
        case BUTTON_SHOW_APPLE:
            [self toggleAppleProcs];
            break;
            
        default:
            break;
    }
    
    return;
}

//(original) items is an array of arrays
// each array contains Event objs, per process
-(OrderedDictionary*)filter
{
    //filtered items
    OrderedDictionary* results = nil;
    
    //filter string
    NSString* filter = nil;
    
    //process
    Process* process = nil;
    
    //events (per process)
    OrderedDictionary* events = nil;
    
    //event
    Event* event = nil;
    
    //sanity check
    if(0 == self.items.count)
    {
        //bail
        goto bail;
    }
    
    //init
    results = [[OrderedDictionary alloc] init];
    
    //grab filter string
    filter = self.filterBox.stringValue;
    
    //filter (apple) button on?
    // filter out all apple processes
    if(NSControlStateValueOn == self.filterButton.state)
    {
        //sanity check
        if(0 == self.items.count)
        {
            //bail
            goto bail;
        }
        
        //process all items
        for(NSInteger i=0; i<self.items.count-1; i++)
        {
            //pid
            NSNumber* pid = [self.items keyAtIndex:i];
            
            //extract
            OrderedDictionary* events = self.items[pid];
            
            //grab process from first event obj
            process = ((Event*)[[events allValues] firstObject]).process;
            
            //skip apple processes
            if( (noErr == [process.signingInfo[KEY_SIGNATURE_STATUS] intValue]) &&
                (Apple == [process.signingInfo[KEY_SIGNATURE_SIGNER] intValue]) )
            {
                //skip
                continue;
            }
            
            //cups is apple,
            // but owned by root so we can't check it's signature (but it's SIP protected)
            if(YES == [process.binary.path isEqualToString:CUPS])
            {
                //skip
                continue;
            }
            
            //add (only) non-apple procs
            [results setObject:self.items[pid] forKey:pid];
        }
    }
    //don't filter apple, so grab all
    else
    {
        //all
        results = [self.items copy];
    }
    
    //search field blank?
    // all done filtering
    if(0 == filter.length)
    {
        //done!
        goto bail;
    }
    
    //sanity check
    if(0 == results.count)
    {
        //bail
        goto bail;
    }
    
    //apply search field
    // remove any items that *don't* match
    for(NSInteger i = results.count-1; i >= 0; i--)
    {
        //grab events (for process)
        events = [[results objectForKey:[results keyAtIndex:i]] copy];
        if(0 == events.count)
        {
            //skip
            continue;
        }
        
        //search all (per) process events
        // remove any events that don't match
        for(NSInteger j = events.count-1; j >= 0; j--)
        {
            //grab event
            event = [events objectForKey:[events keyAtIndex:j]];
            
            //no match?
            // remove event
            if(YES != [event matches:filter])
            {
                //remove
                [events removeObjectForKey:[events keyAtIndex:j]];
            }
        }
        
        //no (per-process) events matched?
        // remove entire process from results
        if(0 == events.count)
        {
            //remove
            [results removeObjectForKey:[results keyAtIndex:i]];
        }
        //otherwise add
        else
        {
            //add
            [results setObject:events forKey:[results keyAtIndex:i]];
        }
    }
    
bail:
    
    return results;
}

//invoked when user clicks 'save' icon
// show popup that allows user to save results
-(void)saveResults
{
    //save panel
    NSSavePanel *panel = nil;
    
    //results
    __block NSMutableArray* results;
    
    //output
    // connections, as json
    __block NSMutableString* output = nil;
    
    //alert
    __block NSAlert *popup = nil;
    
    //error
    __block NSError* error = nil;
    
    //create panel
    panel = [NSSavePanel savePanel];
    
    //suggest file name
    [panel setNameFieldStringValue:@"connections.json"];
    
    //show panel
    // completion handler invoked when user clicks 'Ok'
    [panel beginWithCompletionHandler:^(NSInteger result)
    {
         //only need to handle 'ok'
         if(NSModalResponseOK == result)
         {
             //alloc results
             results = [NSMutableArray array];
             
             //alloc alert
             popup = [[NSAlert alloc] init];
             
             //add default button
             [popup addButtonWithTitle:@"Ok"];
             
             //format results
             // convert to JSON
             output = formatResults(self.processedItems, self.filterButton.state);
             
             //save JSON to disk
             // display results in popup
             if(YES != [output writeToURL:[panel URL] atomically:NO encoding:NSUTF8StringEncoding error:&error])
             {
                 //set error msg
                 popup.messageText = @"ERROR: Failed To Save Output";
                 
                 //set error details
                 popup.informativeText = [NSString stringWithFormat:@"Details: %@", error];
             }
             //saved ok
             // just show msg
             else
             {
                 //set msg
                 popup.messageText = @"Succesfully Saved Output";
                 
                 //set details
                 popup.informativeText = [NSString stringWithFormat:@"File: %s", [[panel URL] fileSystemRepresentation]];
             }
            
             //show popup
             [popup runModal];
         }
         
     }];
    
bail:
    
    return;
}

//filter (search box) handler
// just call into update method (which filters, etc)
-(IBAction)filterConnections:(id)sender
{
    //update
    [self update:self.items];
    
    return;
}

@end
