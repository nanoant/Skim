//
//  SKPreferenceController.m
//  Skim
//
//  Created by Christiaan Hofman on 2/10/07.
/*
 This software is Copyright (c) 2007-2011
 Christiaan Hofman. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

 - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

 - Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

 - Neither the name of Christiaan Hofman nor the names of any
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SKPreferenceController.h"
#import "SKPreferencePane.h"
#import "SKGeneralPreferences.h"
#import "SKDisplayPreferences.h"
#import "SKNotesPreferences.h"
#import "SKSyncPreferences.h"
#import "NSUserDefaultsController_SKExtensions.h"
#import "SKFontWell.h"
#import "NSView_SKExtensions.h"
#import "NSGeometry_SKExtensions.h"

#define INITIALUSERDEFAULTS_KEY @"InitialUserDefaults"
#define RESETTABLEKEYS_KEY @"ResettableKeys"

#define SKPreferencesToolbarIdentifier @"SKPreferencesToolbarIdentifier"

#define SKPreferenceWindowFrameAutosaveName @"SKPreferenceWindow"

#define SKLastSelectedPreferencePaneKey @"SKLastSelectedPreferencePane"

#define NIBNAME_KEY @"nibName"

@implementation SKPreferenceController

@synthesize contentView, resetButtons;

static SKPreferenceController *sharedPrefenceController = nil;

+ (id)sharedPrefenceController {
    if (sharedPrefenceController == nil)
        [[[self alloc] init] autorelease];
    return sharedPrefenceController;
}

+ (id)allocWithZone:(NSZone *)zone {
    return [sharedPrefenceController retain] ?: [super allocWithZone:zone];
}

- (id)init {
    if (sharedPrefenceController == nil) {
        self = [super initWithWindowNibName:@"PreferenceWindow"];
        if (self) {
            preferencePanes = [[NSArray alloc] initWithObjects:
                [[[SKGeneralPreferences alloc] init] autorelease], 
                [[[SKDisplayPreferences alloc] init] autorelease], 
                [[[SKNotesPreferences alloc] init] autorelease], 
                [[[SKSyncPreferences alloc] init] autorelease], nil];
        }
        sharedPrefenceController = [self retain];
    } else if (self != sharedPrefenceController) {
        NSLog(@"Attempt to allocate second instance of %@", [self class]);
        [self release];
        self = [sharedPrefenceController retain];
    }
    return self;
}

- (void)dealloc {
    currentPane = nil;
    SKDESTROY(preferencePanes);
    SKDESTROY(contentView);
    SKDESTROY(resetButtons);
    [super dealloc];
}

- (SKPreferencePane *)preferencePaneForItemIdentifier:(NSString *)itemIdent {
    for (SKPreferencePane *pane in preferencePanes)
        if ([[pane nibName] isEqualToString:itemIdent])
            return pane;
    return nil;
}

- (void)selectPane:(SKPreferencePane *)pane {
    if ([pane isEqual:currentPane] == NO) {
        
        [[self window] setTitle:[pane title]];
        
        // make sure edits are committed
        [currentPane commitEditing];
        [[NSUserDefaultsController sharedUserDefaultsController] commitEditing];
        
        NSView *view = [pane view];
        NSRect frame = [view frame];
        CGFloat dh = NSHeight([contentView frame]) - NSHeight(frame);
        CGFloat dw = NSWidth([contentView frame]) - NSWidth(frame);
        
        [view setFrameOrigin:NSMakePoint(0.0, dh)];
        [contentView replaceSubview:[currentPane view] with:view];
        
        currentPane = pane;
        
        frame = [[self window] frame];
        frame.origin.y += dh;
        frame.size.height -= dh;
        frame.size.width -= dw;
        [[self window] setFrame:frame display:YES animate:YES];
        
        [[NSUserDefaults standardUserDefaults] setObject:[currentPane nibName] forKey:SKLastSelectedPreferencePaneKey];
    }
}

- (void)windowDidLoad {
    NSWindow *window = [self window];
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:SKPreferencesToolbarIdentifier] autorelease];
    
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO];
    [toolbar setVisible:YES];
    [toolbar setDelegate:self];
    [window setToolbar:toolbar];
    [window setShowsToolbarButton:NO];
    
    [self setWindowFrameAutosaveName:SKPreferenceWindowFrameAutosaveName];
    
    SKAutoSizeButtons(resetButtons, NO);
    
    currentPane = [self preferencePaneForItemIdentifier:[[NSUserDefaults standardUserDefaults] stringForKey:SKLastSelectedPreferencePaneKey]] ?: [preferencePanes objectAtIndex:0];
    [toolbar setSelectedItemIdentifier:[currentPane nibName]];
    [window setTitle:[currentPane title]];
        
    NSView *view = [currentPane view];
    NSRect frame = [[self window] frame];
    frame.size.width = NSWidth([view frame]);
    frame.size.height -= NSHeight([contentView frame]) - NSHeight([view frame]);
    [window setFrame:frame display:NO];
    
    [view setFrameOrigin:NSZeroPoint];
    [contentView addSubview:view];
}

- (void)windowDidResignMain:(NSNotification *)notification {
    [[[self window] contentView] deactivateWellSubcontrols];
}

- (void)windowWillClose:(NSNotification *)notification {
    // make sure edits are committed
    [currentPane commitEditing];
    [[NSUserDefaultsController sharedUserDefaultsController] commitEditing];
}

#pragma mark Actions

- (void)selectPaneAction:(id)sender {
    [self selectPane:[self preferencePaneForItemIdentifier:[sender itemIdentifier]]];
}

- (void)resetAllSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (returnCode == NSAlertDefaultReturn) {
        [[NSUserDefaultsController sharedUserDefaultsController] revertToInitialValues:nil];
        [preferencePanes makeObjectsPerformSelector:@selector(defaultsDidRevert)];
    }
}

- (IBAction)resetAll:(id)sender {
    NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Reset all preferences to their original values?", @"Message in alert dialog when pressing Reset All button") 
                                     defaultButton:NSLocalizedString(@"Reset", @"Button title")
                                   alternateButton:NSLocalizedString(@"Cancel", @"Button title")
                                       otherButton:nil
                         informativeTextWithFormat:NSLocalizedString(@"Choosing Reset will restore all settings to the state they were in when Skim was first installed.", @"Informative text in alert dialog when pressing Reset All button")];
    [alert beginSheetModalForWindow:[self window]
                      modalDelegate:self
                     didEndSelector:@selector(resetAllSheetDidEnd:returnCode:contextInfo:)
                        contextInfo:NULL];
}

- (void)resetCurrentSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (returnCode == NSAlertDefaultReturn) {
        NSString *initialUserDefaultsPath = [[NSBundle mainBundle] pathForResource:INITIALUSERDEFAULTS_KEY ofType:@"plist"];
        NSArray *resettableKeys = [[[NSDictionary dictionaryWithContentsOfFile:initialUserDefaultsPath] objectForKey:RESETTABLEKEYS_KEY] objectForKey:[currentPane nibName]];
        [[NSUserDefaultsController sharedUserDefaultsController] revertToInitialValuesForKeys:resettableKeys];
        [currentPane defaultsDidRevert];
    }
}

- (IBAction)resetCurrent:(id)sender {
    if (currentPane == nil) {
        NSBeep();
        return;
    }
    NSString *label = [currentPane title];
    NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedString(@"Reset %@ preferences to their original values?", @"Message in alert dialog when pressing Reset All button"), label]
                                     defaultButton:NSLocalizedString(@"Reset", @"Button title")
                                   alternateButton:NSLocalizedString(@"Cancel", @"Button title")
                                       otherButton:nil
                         informativeTextWithFormat:NSLocalizedString(@"Choosing Reset will restore all settings in this pane to the state they were in when Skim was first installed.", @"Informative text in alert dialog when pressing Reset All button"), label];
    [alert beginSheetModalForWindow:[self window]
                      modalDelegate:self
                     didEndSelector:@selector(resetCurrentSheetDidEnd:returnCode:contextInfo:)
                        contextInfo:NULL];
}

- (IBAction)changeFont:(id)sender {
    [currentPane changeFont:sender];
}

- (IBAction)changeAttributes:(id)sender {
    [currentPane changeAttributes:sender];
}

- (IBAction)doGoToNextPage:(id)sender {
    NSUInteger itemIndex = [preferencePanes indexOfObject:currentPane];
    if (itemIndex != NSNotFound && ++itemIndex < [preferencePanes count]) {
        SKPreferencePane *pane = [preferencePanes objectAtIndex:itemIndex];
        [[[self window] toolbar] setSelectedItemIdentifier:[pane nibName]];
        [self selectPane:pane];
    }
}

- (IBAction)doGoToPreviousPage:(id)sender {
    NSUInteger itemIndex = [preferencePanes indexOfObject:currentPane];
    if (itemIndex != NSNotFound && itemIndex-- > 0) {
        SKPreferencePane *pane = [preferencePanes objectAtIndex:itemIndex];
        [[[self window] toolbar] setSelectedItemIdentifier:[pane nibName]];
        [self selectPane:pane];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(doGoToNextPage:))
        return [currentPane isEqual:[preferencePanes lastObject]] == NO;
    else if ([menuItem action] == @selector(doGoToPreviousPage:))
        return [currentPane isEqual:[preferencePanes objectAtIndex:0]] == NO;
    return YES;
}

#pragma mark Toolbar

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdent willBeInsertedIntoToolbar:(BOOL)willBeInserted {
    SKPreferencePane *pane = [self preferencePaneForItemIdentifier:itemIdent];
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdent] autorelease];
    [item setLabel:[pane title]];
    [item setImage:[pane icon]];
    [item setTarget:self];
    [item setAction:@selector(selectPaneAction:)];
    return item;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [preferencePanes valueForKey:NIBNAME_KEY];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

@end
