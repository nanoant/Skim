//
//  SKTemplateParser.m
//  Skim
//
//  Created by Christiaan Hofman on 5/26/07.
/*
 This software is Copyright (c) 2007-2008
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

#import "SKTemplateParser.h"
#import "SKTag.h"
#import "NSCharacterSet_SKExtensions.h"
#import "NSString_SKExtensions.h"
#import "NSObject_SKExtensions.h"

#define START_TAG_OPEN_DELIM            @"<$"
#define END_TAG_OPEN_DELIM              @"</$"
#define ALT_TAG_OPEN_DELIM              @"<?$"
#define VALUE_TAG_CLOSE_DELIM           @"/>"
#define COLLECTION_TAG_CLOSE_DELIM      @">"
#define CONDITION_TAG_CLOSE_DELIM       @"?>"
#define CONDITION_TAG_EQUAL             @"="
#define CONDITION_TAG_CONTAIN           @"~"
#define CONDITION_TAG_SMALLER           @"<"
#define CONDITION_TAG_SMALLER_OR_EQUAL  @"<="

/*
        value tag: <$key/>
   collection tag: <$key> </$key> 
               or: <$key> <?$key> </$key>
    condition tag: <$key?> </$key?> 
               or: <$key?> <?$key?> </$key?>
               or: <$key=value?> </$key?>
               or: <$key=value?> <?$key?> </$key?>
               or: <$key~value?> </$key?>
               or: <$key~value?> <?$key?> </$key?>
               or: <$key<value?> </$key?>
               or: <$key<value?> <?$key?> </$key?>
               or: <$key<=value?> </$key?>
               or: <$key<=value?> <?$key?> </$key?>
*/

enum {
    SKConditionTagMatchOther,
    SKConditionTagMatchEqual,
    SKConditionTagMatchContain,
    SKConditionTagMatchSmaller,
    SKConditionTagMatchSmallerOrEqual,
};

@implementation SKTemplateParser


static NSCharacterSet *keyCharacterSet = nil;
static NSCharacterSet *invertedKeyCharacterSet = nil;

+ (void)initialize {
    OBINITIALIZE;
    
    NSMutableCharacterSet *tmpSet = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [tmpSet addCharactersInString:@".-_@#"];
    keyCharacterSet = [tmpSet copy];
    [tmpSet release];
    
    invertedKeyCharacterSet = [[keyCharacterSet invertedSet] copy];
}

static inline NSString *endCollectionTagWithTag(NSString *tag) {
    static NSMutableDictionary *endCollectionDict = nil;
    if (nil == endCollectionDict)
        endCollectionDict = [[NSMutableDictionary alloc] init];
    
    NSString *endTag = [endCollectionDict objectForKey:tag];
    if (nil == endTag) {
        endTag = [NSString stringWithFormat:@"%@%@%@", END_TAG_OPEN_DELIM, tag, COLLECTION_TAG_CLOSE_DELIM];
        [endCollectionDict setObject:endTag forKey:tag];
    }
    return endTag;
}

static inline NSString *sepCollectionTagWithTag(NSString *tag) {
    static NSMutableDictionary *sepCollectionDict = nil;
    if (nil == sepCollectionDict)
        sepCollectionDict = [[NSMutableDictionary alloc] init];
    
    NSString *altTag = [sepCollectionDict objectForKey:tag];
    if (nil == altTag) {
        altTag = [NSString stringWithFormat:@"%@%@%@", ALT_TAG_OPEN_DELIM, tag, COLLECTION_TAG_CLOSE_DELIM];
        [sepCollectionDict setObject:altTag forKey:tag];
    }
    return altTag;
}

static inline NSString *endConditionTagWithTag(NSString *tag) {
    static NSMutableDictionary *endConditionDict = nil;
    if (nil == endConditionDict)
        endConditionDict = [[NSMutableDictionary alloc] init];
    
    NSString *endTag = [endConditionDict objectForKey:tag];
    if (nil == endTag) {
        endTag = [NSString stringWithFormat:@"%@%@%@", END_TAG_OPEN_DELIM, tag, CONDITION_TAG_CLOSE_DELIM];
        [endConditionDict setObject:endTag forKey:tag];
    }
    return endTag;
}

static inline NSString *altConditionTagWithTag(NSString *tag) {
    static NSMutableDictionary *altConditionDict = nil;
    if (nil == altConditionDict)
        altConditionDict = [[NSMutableDictionary alloc] init];
    
    NSString *altTag = [altConditionDict objectForKey:tag];
    if (nil == altTag) {
        altTag = [NSString stringWithFormat:@"%@%@%@", ALT_TAG_OPEN_DELIM, tag, CONDITION_TAG_CLOSE_DELIM];
        [altConditionDict setObject:altTag forKey:tag];
    }
    return altTag;
}

static inline NSString *compareConditionTagWithTag(NSString *tag, int matchType) {
    static NSMutableDictionary *equalConditionDict = nil;
    static NSMutableDictionary *containConditionDict = nil;
    static NSMutableDictionary *smallerConditionDict = nil;
    static NSMutableDictionary *smallerOrEqualConditionDict = nil;
    NSString *altTag = nil;
    switch (matchType) {
        case SKConditionTagMatchEqual:
            if (nil == equalConditionDict)
                equalConditionDict = [[NSMutableDictionary alloc] init];
            altTag = [equalConditionDict objectForKey:tag];
            if (nil == altTag) {
                altTag = [NSString stringWithFormat:@"%@%@%@", ALT_TAG_OPEN_DELIM, tag, CONDITION_TAG_EQUAL];
                [equalConditionDict setObject:altTag forKey:tag];
            }
            break;
        case SKConditionTagMatchContain:
            if (nil == containConditionDict)
                containConditionDict = [[NSMutableDictionary alloc] init];
            altTag = [containConditionDict objectForKey:tag];
            if (nil == altTag) {
                altTag = [NSString stringWithFormat:@"%@%@%@", ALT_TAG_OPEN_DELIM, tag, CONDITION_TAG_CONTAIN];
                [containConditionDict setObject:altTag forKey:tag];
            }
            break;
        case SKConditionTagMatchSmaller:
            if (nil == smallerConditionDict)
                smallerConditionDict = [[NSMutableDictionary alloc] init];
            altTag = [smallerConditionDict objectForKey:tag];
            if (nil == altTag) {
                altTag = [NSString stringWithFormat:@"%@%@%@", ALT_TAG_OPEN_DELIM, tag, CONDITION_TAG_SMALLER];
                [smallerConditionDict setObject:altTag forKey:tag];
            }
            break;
        case SKConditionTagMatchSmallerOrEqual:
            if (nil == smallerOrEqualConditionDict)
                smallerOrEqualConditionDict = [[NSMutableDictionary alloc] init];
            altTag = [smallerOrEqualConditionDict objectForKey:tag];
            if (nil == altTag) {
                altTag = [NSString stringWithFormat:@"%@%@%@", ALT_TAG_OPEN_DELIM, tag, CONDITION_TAG_SMALLER_OR_EQUAL];
                [smallerOrEqualConditionDict setObject:altTag forKey:tag];
            }
            break;
    }
    return altTag;
}

static inline NSRange altTemplateTagRange(NSString *template, NSString *altTag, NSString *endDelim, NSString **argString) {
    NSRange altTagRange = [template rangeOfString:altTag];
    if (altTagRange.location != NSNotFound) {
        // ignore whitespaces before the tag
        NSRange wsRange = [template rangeOfTrailingEmptyLineInRange:NSMakeRange(0, altTagRange.location)];
        if (wsRange.location != NSNotFound) 
            altTagRange = NSMakeRange(wsRange.location, NSMaxRange(altTagRange) - wsRange.location);
        if (nil != endDelim) {
            // find the end tag and the argument (match string)
            NSRange endRange = [template rangeOfString:endDelim options:0 range:NSMakeRange(NSMaxRange(altTagRange), [template length] - NSMaxRange(altTagRange))];
            if (endRange.location != NSNotFound) {
                *argString = [template substringWithRange:NSMakeRange(NSMaxRange(altTagRange), endRange.location - NSMaxRange(altTagRange))];
                altTagRange.length = NSMaxRange(endRange) - altTagRange.location;
            } else {
                *argString = @"";
            }
        }
        // ignore whitespaces after the tag, including a trailing newline 
        wsRange = [template rangeOfLeadingEmptyLineInRange:NSMakeRange(NSMaxRange(altTagRange), [template length] - NSMaxRange(altTagRange))];
        if (wsRange.location != NSNotFound)
            altTagRange.length = NSMaxRange(wsRange) - altTagRange.location;
    }
    return altTagRange;
}

#pragma mark Parsing string templates

+ (NSString *)stringByParsingTemplate:(NSString *)template usingObject:(id)object {
    return [self stringFromTemplateArray:[self arrayByParsingTemplateString:template] usingObject:object atIndex:1];
}

+ (NSArray *)arrayByParsingTemplateString:(NSString *)template {
    NSScanner *scanner = [[NSScanner alloc] initWithString:template];
    NSMutableArray *result = [[NSMutableArray alloc] init];
    id currentTag = nil;

    [scanner setCharactersToBeSkipped:nil];
    
    while (![scanner isAtEnd]) {
        NSString *beforeText = nil;
        NSString *tag = nil;
        int start;
                
        if ([scanner scanUpToString:START_TAG_OPEN_DELIM intoString:&beforeText]) {
            if (currentTag && [(SKTag *)currentTag type] == SKTextTagType) {
                [(SKTextTag *)currentTag setText:[[(SKTextTag *)currentTag text] stringByAppendingString:beforeText]];
            } else {
                currentTag = [[SKTextTag alloc] initWithText:beforeText];
                [result addObject:currentTag];
                [currentTag release];
            }
        }
        
        if ([scanner scanString:START_TAG_OPEN_DELIM intoString:nil]) {
            
            start = [scanner scanLocation];
            
            // scan the key, must be letters and dots. We don't allow extra spaces
            // scanUpToCharactersFromSet is used for efficiency instead of scanCharactersFromSet
            [scanner scanUpToCharactersFromSet:invertedKeyCharacterSet intoString:&tag];
            
            if ([scanner scanString:VALUE_TAG_CLOSE_DELIM intoString:nil]) {
                
                // simple template currentTag
                currentTag = [[SKValueTag alloc] initWithKeyPath:tag];
                [result addObject:currentTag];
                [currentTag release];
                
            } else if ([scanner scanString:COLLECTION_TAG_CLOSE_DELIM intoString:nil]) {
                
                NSString *itemTemplate = nil, *separatorTemplate = nil;
                NSString *endTag;
                NSRange sepTagRange, wsRange;
                
                // collection template tag
                // ignore whitespace before the tag. Should we also remove a newline?
                if (currentTag && [(SKTag *)currentTag type] == SKTextTagType) {
                    wsRange = [[(SKTextTag *)currentTag text] rangeOfTrailingEmptyLineRequiringNewline:[result count] != 1];
                    if (wsRange.location != NSNotFound) {
                        if (wsRange.length == [[currentTag text] length]) {
                            [result removeLastObject];
                            currentTag = [result lastObject];
                        } else {
                            [(SKTextTag *)currentTag setText:[[(SKTextTag *)currentTag text] substringToIndex:wsRange.location]];
                        }
                    }
                }
                
                endTag = endCollectionTagWithTag(tag);
                // ignore the rest of an empty line after the tag
                [scanner scanEmptyLine];
                if ([scanner scanString:endTag intoString:nil])
                    continue;
                if ([scanner scanUpToString:endTag intoString:&itemTemplate] && [scanner scanString:endTag intoString:nil]) {
                    // ignore whitespace before the tag. Should we also remove a newline?
                    wsRange = [itemTemplate rangeOfTrailingEmptyLine];
                    if (wsRange.location != NSNotFound)
                        itemTemplate = [itemTemplate substringToIndex:wsRange.location];
                    
                    sepTagRange = altTemplateTagRange(itemTemplate, sepCollectionTagWithTag(tag), nil, NULL);
                    if (sepTagRange.location != NSNotFound) {
                        separatorTemplate = [itemTemplate substringFromIndex:NSMaxRange(sepTagRange)];
                        itemTemplate = [itemTemplate substringToIndex:sepTagRange.location];
                    }
                    
                    currentTag = [[SKCollectionTag alloc] initWithKeyPath:tag itemTemplateString:itemTemplate separatorTemplateString:separatorTemplate];
                    [result addObject:currentTag];
                    [currentTag release];
                    
                    // ignore the the rest of an empty line after the currentTag
                    [scanner scanEmptyLine];
                    
                }
                
            } else {
                
                NSString *matchString = nil;
                int matchType = SKConditionTagMatchOther;
                
                if ([scanner scanString:CONDITION_TAG_EQUAL intoString:nil]) {
                    if ([scanner scanUpToString:CONDITION_TAG_CLOSE_DELIM intoString:&matchString] == NO)
                        matchString = @"";
                    matchType = SKConditionTagMatchEqual;
                } else if ([scanner scanString:CONDITION_TAG_CONTAIN intoString:nil]) {
                    if ([scanner scanUpToString:CONDITION_TAG_CLOSE_DELIM intoString:&matchString] == NO)
                        matchString = @"";
                    matchType = SKConditionTagMatchContain;
                } else if ([scanner scanString:CONDITION_TAG_SMALLER_OR_EQUAL intoString:nil]) {
                    if ([scanner scanUpToString:CONDITION_TAG_CLOSE_DELIM intoString:&matchString] == NO)
                        matchString = @"";
                    matchType = SKConditionTagMatchSmallerOrEqual;
                } else if ([scanner scanString:CONDITION_TAG_SMALLER intoString:nil]) {
                    if ([scanner scanUpToString:CONDITION_TAG_CLOSE_DELIM intoString:&matchString] == NO)
                        matchString = @"";
                    matchType = SKConditionTagMatchSmaller;
                }
                
                if ([scanner scanString:CONDITION_TAG_CLOSE_DELIM intoString:nil]) {
                    
                    NSMutableArray *subTemplates, *matchStrings;
                    NSString *subTemplate = nil;
                    NSString *endTag, *altTag;
                    NSRange altTagRange, wsRange;
                    
                    // condition template tag
                    // ignore whitespace before the tag. Should we also remove a newline?
                    if (currentTag && [(SKTag *)currentTag type] == SKTextTagType) {
                        wsRange = [[(SKTextTag *)currentTag text] rangeOfTrailingEmptyLineRequiringNewline:[result count] != 1];
                        if (wsRange.location != NSNotFound) {
                            if (wsRange.length == [[currentTag text] length]) {
                                [result removeLastObject];
                                currentTag = [result lastObject];
                            } else {
                                [(SKTextTag *)currentTag setText:[[(SKTextTag *)currentTag text] substringToIndex:wsRange.location]];
                            }
                        }
                    }
                    
                    endTag = endConditionTagWithTag(tag);
                    // ignore the rest of an empty line after the tag
                    [scanner scanEmptyLine];
                    if ([scanner scanString:endTag intoString:nil])
                        continue;
                    if ([scanner scanUpToString:endTag intoString:&subTemplate] && [scanner scanString:endTag intoString:nil]) {
                        // ignore whitespace before the currentTag. Should we also remove a newline?
                        wsRange = [subTemplate rangeOfTrailingEmptyLine];
                        if (wsRange.location != NSNotFound)
                            subTemplate = [subTemplate substringToIndex:wsRange.location];
                        
                        subTemplates = [[NSMutableArray alloc] init];
                        matchStrings = [[NSMutableArray alloc] initWithObjects:matchString ? matchString : @"", nil];
                        
                        if (matchType != SKConditionTagMatchOther) {
                            altTag = compareConditionTagWithTag(tag, matchType);
                            altTagRange = altTemplateTagRange(subTemplate, altTag, CONDITION_TAG_CLOSE_DELIM, &matchString);
                            while (altTagRange.location != NSNotFound) {
                                [subTemplates addObject:[subTemplate substringToIndex:altTagRange.location]];
                                [matchStrings addObject:matchString ? matchString : @""];
                                subTemplate = [subTemplate substringFromIndex:NSMaxRange(altTagRange)];
                                altTagRange = altTemplateTagRange(subTemplate, altTag, CONDITION_TAG_CLOSE_DELIM, &matchString);
                            }
                        }
                        
                        altTagRange = altTemplateTagRange(subTemplate, altConditionTagWithTag(tag), nil, NULL);
                        if (altTagRange.location != NSNotFound) {
                            [subTemplates addObject:[subTemplate substringToIndex:altTagRange.location]];
                            subTemplate = [subTemplate substringFromIndex:NSMaxRange(altTagRange)];
                        }
                        [subTemplates addObject:subTemplate];
                        
                        currentTag = [[SKConditionTag alloc] initWithKeyPath:tag matchType:matchType matchStrings:matchStrings subtemplates:subTemplates];
                        [result addObject:currentTag];
                        [currentTag release];
                        
                        [subTemplates release];
                        [matchStrings release];
                        // ignore the the rest of an empty line after the currentTag
                        [scanner scanEmptyLine];
                        
                    }
                    
                } else {
                    
                    // an open delimiter without a close delimiter, so no template tag. Rewind
                    if (currentTag && [(SKTag *)currentTag type] == SKTextTagType) {
                        [(SKTextTag *)currentTag setText:[[(SKTextTag *)currentTag text] stringByAppendingString:START_TAG_OPEN_DELIM]];
                    } else {
                        currentTag = [[SKTextTag alloc] initWithText:START_TAG_OPEN_DELIM];
                        [result addObject:currentTag];
                        [currentTag release];
                    }
                    [scanner setScanLocation:start];
                    
                }
            }
        } // scan START_TAG_OPEN_DELIM
    } // while
    [scanner release];
    return [result autorelease];    
}

+ (NSString *)stringFromTemplateArray:(NSArray *)template usingObject:(id)object atIndex:(int)anIndex {
    NSEnumerator *tagEnum = [template objectEnumerator];
    id tag;
    NSMutableString *result = [[NSMutableString alloc] init];
    
    while (tag = [tagEnum nextObject]) {
        int type = [(SKTag *)tag type];
        
        if (type == SKTextTagType) {
            
            [result appendString:[(SKTextTag *)tag text]];
            
        } else {
            
            NSString *keyPath = [tag keyPath];
            id keyValue = nil;
            
            if ([keyPath hasPrefix:@"#"]) {
                keyValue = [NSNumber numberWithInt:anIndex];
                if ([keyPath hasPrefix:@"#."] && [keyPath length] > 2)
                    keyValue = [keyValue templateValueForKeyPath:[keyPath substringFromIndex:2]];
            } else {
                keyValue = [object templateValueForKeyPath:keyPath];
            }
            
            if (type == SKValueTagType) {
                
                if (keyValue)
                    [result appendString:[keyValue templateStringValue]];
                
            } else if (type == SKCollectionTagType) {
                
                if ([keyValue respondsToSelector:@selector(objectEnumerator)]) {
                    NSEnumerator *itemE = [keyValue objectEnumerator];
                    id nextItem, item = [itemE nextObject];
                    NSArray *itemTemplate = [[tag itemTemplate] arrayByAddingObjectsFromArray:[tag separatorTemplate]];
                    int idx = 0;
                    while (item) {
                        nextItem = [itemE nextObject];
                        if (nextItem == nil)
                            itemTemplate = [tag itemTemplate];
                        keyValue = [self stringFromTemplateArray:itemTemplate usingObject:item atIndex:++idx];
                        if (keyValue != nil)
                            [result appendString:keyValue];
                        item = nextItem;
                    }
                }
                
            } else {
                
                NSString *matchString = nil;
                BOOL isMatch;
                NSArray *matchStrings = [tag matchStrings];
                unsigned int i, count = [matchStrings count];
                NSArray *subtemplate = nil;
                
                for (i = 0; i < count; i++) {
                    matchString = [matchStrings objectAtIndex:i];
                    if ([matchString hasPrefix:@"$"]) {
                        matchString = [[object templateValueForKeyPath:[matchString substringFromIndex:1]] templateStringValue];
                        if (matchString == nil)
                            matchString = @"";
                    }
                    switch ([tag matchType]) {
                        case SKConditionTagMatchEqual:
                            isMatch = [matchString isEqualToString:@""] ? NO == [keyValue isNotEmpty] : [[keyValue templateStringValue] caseInsensitiveCompare:matchString] == NSOrderedSame;
                            break;
                        case SKConditionTagMatchContain:
                            isMatch = [matchString isEqualToString:@""] ? NO == [keyValue isNotEmpty] : [[keyValue templateStringValue] rangeOfString:matchString options:NSCaseInsensitiveSearch].location != NSNotFound;
                            break;
                        case SKConditionTagMatchSmaller:
                            isMatch = [matchString isEqualToString:@""] ? NO == [keyValue isNotEmpty] : [[keyValue templateStringValue] localizedCaseInsensitiveNumericCompare:matchString] == NSOrderedAscending;
                            break;
                        case SKConditionTagMatchSmallerOrEqual:
                            isMatch = [matchString isEqualToString:@""] ? NO == [keyValue isNotEmpty] : [[keyValue templateStringValue] localizedCaseInsensitiveNumericCompare:matchString] != NSOrderedDescending;
                            break;
                        default:
                            isMatch = [keyValue isNotEmpty];
                            break;
                    }
                    if (isMatch) {
                        subtemplate = [tag subtemplateAtIndex:i];
                        break;
                    }
                }
                if (subtemplate == nil && [[tag subtemplates] count] > count) {
                    subtemplate = [tag subtemplateAtIndex:count];
                }
                if (subtemplate != nil) {
                    keyValue = [self stringFromTemplateArray:subtemplate usingObject:object atIndex:anIndex];
                    [result appendString:keyValue];
                }
                
            }
            
        }
    } // while
    
    return [result autorelease];    
}

#pragma mark Parsing attributed string templates

+ (NSAttributedString *)attributedStringByParsingTemplate:(NSAttributedString *)template usingObject:(id)object {
    return [self attributedStringFromTemplateArray:[self arrayByParsingTemplateAttributedString:template] usingObject:object atIndex:1];
}

+ (NSArray *)arrayByParsingTemplateAttributedString:(NSAttributedString *)template {
    NSString *templateString = [template string];
    NSScanner *scanner = [[NSScanner alloc] initWithString:templateString];
    NSMutableArray *result = [[NSMutableArray alloc] init];
    id currentTag = nil;

    [scanner setCharactersToBeSkipped:nil];
    
    while (![scanner isAtEnd]) {
        NSString *beforeText = nil;
        NSString *tag = nil;
        int start;
        NSDictionary *attr = nil;
        NSMutableAttributedString *tmpAttrStr = nil;
        
        start = [scanner scanLocation];
                
        if ([scanner scanUpToString:START_TAG_OPEN_DELIM intoString:&beforeText]) {
            if (currentTag && [(SKTag *)currentTag type] == SKTextTagType) {
                tmpAttrStr = [[(SKRichTextTag *)currentTag attributedText] mutableCopy];
                [tmpAttrStr appendAttributedString:[template attributedSubstringFromRange:NSMakeRange(start, [beforeText length])]];
                [tmpAttrStr fixAttributesInRange:NSMakeRange(0, [tmpAttrStr length])];
                [(SKRichTextTag *)currentTag setAttributedText:tmpAttrStr];
                [tmpAttrStr release];
            } else {
                currentTag = [[SKRichTextTag alloc] initWithAttributedText:[template attributedSubstringFromRange:NSMakeRange(start, [beforeText length])]];
                [result addObject:currentTag];
                [currentTag release];
            }
        }
        
        if ([scanner scanString:START_TAG_OPEN_DELIM intoString:nil]) {
            
            attr = [template attributesAtIndex:[scanner scanLocation] - 1 effectiveRange:NULL];
            start = [scanner scanLocation];
            
            // scan the key, must be letters and dots. We don't allow extra spaces
            // scanUpToCharactersFromSet is used for efficiency instead of scanCharactersFromSet
            [scanner scanUpToCharactersFromSet:invertedKeyCharacterSet intoString:&tag];

            if ([scanner scanString:VALUE_TAG_CLOSE_DELIM intoString:nil]) {
                
                // simple template tag
                currentTag = [[SKRichValueTag alloc] initWithKeyPath:tag attributes:attr];
                [result addObject:currentTag];
                [currentTag release];
               
            } else if ([scanner scanString:COLLECTION_TAG_CLOSE_DELIM intoString:nil]) {
                
                NSString *itemTemplateString = nil;
                NSAttributedString *itemTemplate = nil, *separatorTemplate = nil;
                NSString *endTag;
                NSRange sepTagRange, wsRange;
                
                // collection template tag
                // ignore whitespace before the tag. Should we also remove a newline?
                if (currentTag && [(SKTag *)currentTag type] == SKTextTagType) {
                    wsRange = [[[(SKRichTextTag *)currentTag attributedText] string] rangeOfTrailingEmptyLineRequiringNewline:[result count] != 1];
                    if (wsRange.location != NSNotFound) {
                        if (wsRange.length == [[(SKRichTextTag *)currentTag attributedText] length]) {
                            [result removeLastObject];
                            currentTag = [result lastObject];
                        } else {
                            [(SKRichTextTag *)currentTag setAttributedText:[[(SKRichTextTag *)currentTag attributedText] attributedSubstringFromRange:NSMakeRange(0, wsRange.location)]];
                        }
                    }
                }
                
                endTag = endCollectionTagWithTag(tag);
                // ignore the rest of an empty line after the tag
                [scanner scanEmptyLine];
                if ([scanner scanString:endTag intoString:nil])
                    continue;
                start = [scanner scanLocation];
                if ([scanner scanUpToString:endTag intoString:&itemTemplateString] && [scanner scanString:endTag intoString:nil]) {
                    // ignore whitespace before the tag. Should we also remove a newline?
                    wsRange = [itemTemplateString rangeOfTrailingEmptyLine];
                    itemTemplate = [template attributedSubstringFromRange:NSMakeRange(start, [itemTemplateString length] - wsRange.length)];
                    
                    sepTagRange = altTemplateTagRange([itemTemplate string], sepCollectionTagWithTag(tag), nil, NULL);
                    if (sepTagRange.location != NSNotFound) {
                        separatorTemplate = [itemTemplate attributedSubstringFromRange:NSMakeRange(NSMaxRange(sepTagRange), [itemTemplate length] - NSMaxRange(sepTagRange))];
                        itemTemplate = [itemTemplate attributedSubstringFromRange:NSMakeRange(0, sepTagRange.location)];
                    }
                    
                    currentTag = [[SKRichCollectionTag alloc] initWithKeyPath:tag itemTemplateAttributedString:itemTemplate separatorTemplateAttributedString:separatorTemplate];
                    [result addObject:currentTag];
                    [currentTag release];
                    
                    // ignore the the rest of an empty line after the tag
                    [scanner scanEmptyLine];
                    
                }
                
            } else {
                
                NSString *matchString = nil;
                int matchType = SKConditionTagMatchOther;
                
                if ([scanner scanString:CONDITION_TAG_EQUAL intoString:nil]) {
                    if ([scanner scanUpToString:CONDITION_TAG_CLOSE_DELIM intoString:&matchString] == NO)
                        matchString = @"";
                    matchType = SKConditionTagMatchEqual;
                } else if ([scanner scanString:CONDITION_TAG_CONTAIN intoString:nil]) {
                    if ([scanner scanUpToString:CONDITION_TAG_CLOSE_DELIM intoString:&matchString] == NO)
                        matchString = @"";
                    matchType = SKConditionTagMatchContain;
                } else if ([scanner scanString:CONDITION_TAG_SMALLER_OR_EQUAL intoString:nil]) {
                    if ([scanner scanUpToString:CONDITION_TAG_CLOSE_DELIM intoString:&matchString] == NO)
                        matchString = @"";
                    matchType = SKConditionTagMatchSmallerOrEqual;
                } else if ([scanner scanString:CONDITION_TAG_SMALLER intoString:nil]) {
                    if ([scanner scanUpToString:CONDITION_TAG_CLOSE_DELIM intoString:&matchString] == NO)
                        matchString = @"";
                    matchType = SKConditionTagMatchSmaller;
                }
                
                if ([scanner scanString:CONDITION_TAG_CLOSE_DELIM intoString:nil]) {
                    
                    NSMutableArray *subTemplates, *matchStrings;
                    NSString *subTemplateString = nil;
                    NSAttributedString *subTemplate = nil;
                    NSString *endTag, *altTag;
                    NSRange altTagRange, wsRange;
                    
                    // condition template tag
                    // ignore whitespace before the tag. Should we also remove a newline?
                    if (currentTag && [(SKTag *)currentTag type] == SKTextTagType) {
                        wsRange = [[[(SKRichTextTag *)currentTag attributedText] string] rangeOfTrailingEmptyLineRequiringNewline:[result count] != 1];
                        if (wsRange.location != NSNotFound) {
                            if (wsRange.length == [[(SKRichTextTag *)currentTag attributedText] length]) {
                                [result removeLastObject];
                                currentTag = [result lastObject];
                            } else {
                                [(SKRichTextTag *)currentTag setAttributedText:[[(SKRichTextTag *)currentTag attributedText] attributedSubstringFromRange:NSMakeRange(0, wsRange.location)]];
                            }
                        }
                    }
                    
                    endTag = endConditionTagWithTag(tag);
                    altTag = altConditionTagWithTag(tag);
                    // ignore the rest of an empty line after the tag
                    [scanner scanEmptyLine];
                    if ([scanner scanString:endTag intoString:nil])
                        continue;
                    start = [scanner scanLocation];
                    if ([scanner scanUpToString:endTag intoString:&subTemplateString] && [scanner scanString:endTag intoString:nil]) {
                        // ignore whitespace before the tag. Should we also remove a newline?
                        wsRange = [subTemplateString rangeOfTrailingEmptyLine];
                        subTemplate = [template attributedSubstringFromRange:NSMakeRange(start, [subTemplateString length] - wsRange.length)];
                        
                        subTemplates = [[NSMutableArray alloc] init];
                        matchStrings = [[NSMutableArray alloc] initWithObjects:matchString ? matchString : @"", nil];
                        
                        if (matchType != SKConditionTagMatchOther) {
                            altTag = compareConditionTagWithTag(tag, matchType);
                            altTagRange = altTemplateTagRange([subTemplate string], altTag, CONDITION_TAG_CLOSE_DELIM, &matchString);
                            while (altTagRange.location != NSNotFound) {
                                [subTemplates addObject:[subTemplate attributedSubstringFromRange:NSMakeRange(0, altTagRange.location)]];
                                [matchStrings addObject:matchString ? matchString : @""];
                                subTemplate = [subTemplate attributedSubstringFromRange:NSMakeRange(NSMaxRange(altTagRange), [subTemplate length] - NSMaxRange(altTagRange))];
                                altTagRange = altTemplateTagRange([subTemplate string], altTag, CONDITION_TAG_CLOSE_DELIM, &matchString);
                            }
                        }
                        
                        altTagRange = altTemplateTagRange([subTemplate string], altConditionTagWithTag(tag), nil, NULL);
                        if (altTagRange.location != NSNotFound) {
                            [subTemplates addObject:[subTemplate attributedSubstringFromRange:NSMakeRange(0, altTagRange.location)]];
                            subTemplate = [subTemplate attributedSubstringFromRange:NSMakeRange(NSMaxRange(altTagRange), [subTemplate length] - NSMaxRange(altTagRange))];
                        }
                        [subTemplates addObject:subTemplate];
                        
                        currentTag = [[SKRichConditionTag alloc] initWithKeyPath:tag matchType:matchType matchStrings:matchStrings subtemplates:subTemplates];
                        [result addObject:currentTag];
                        [currentTag release];
                        
                        [subTemplates release];
                        [matchStrings release];
                        // ignore the the rest of an empty line after the tag
                        [scanner scanEmptyLine];
                        
                    }
                    
                } else {
                    
                    // a START_TAG_OPEN_DELIM without COLLECTION_TAG_CLOSE_DELIM, so no template tag. Rewind
                    if (currentTag && [(SKTag *)currentTag type] == SKTextTagType) {
                        tmpAttrStr = [[(SKRichTextTag *)currentTag attributedText] mutableCopy];
                        [tmpAttrStr appendAttributedString:[template attributedSubstringFromRange:NSMakeRange(start - [START_TAG_OPEN_DELIM length], [START_TAG_OPEN_DELIM length])]];
                        [tmpAttrStr fixAttributesInRange:NSMakeRange(0, [tmpAttrStr length])];
                        [(SKRichTextTag *)currentTag setAttributedText:tmpAttrStr];
                        [tmpAttrStr release];
                    } else {
                        currentTag = [[SKRichTextTag alloc] initWithAttributedText:[template attributedSubstringFromRange:NSMakeRange(start - [START_TAG_OPEN_DELIM length], [START_TAG_OPEN_DELIM length])]];
                        [result addObject:currentTag];
                        [currentTag release];
                    }
                    [scanner setScanLocation:start];
                    
                }
            }
        } // scan START_TAG_OPEN_DELIM
    } // while
    
    [scanner release];
    
    return [result autorelease];    
}

+ (NSAttributedString *)attributedStringFromTemplateArray:(NSArray *)template usingObject:(id)object atIndex:(int)anIndex {
    NSEnumerator *tagEnum = [template objectEnumerator];
    id tag;
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    while (tag = [tagEnum nextObject]) {
        int type = [(SKTag *)tag type];
        NSAttributedString *tmpAttrStr = nil;
        
        if (type == SKTextTagType) {
            
            [result appendAttributedString:[(SKRichTextTag *)tag attributedText]];
            
        } else {
            
            NSString *keyPath = [tag keyPath];
            id keyValue = nil;
            
            if ([keyPath hasPrefix:@"#"]) {
                keyValue = [NSNumber numberWithInt:anIndex];
                if ([keyPath hasPrefix:@"#."] && [keyPath length] > 2)
                    keyValue = [keyValue templateValueForKeyPath:[keyPath substringFromIndex:2]];
            } else {
                keyValue = [object templateValueForKeyPath:keyPath];
            }
            
            if (type == SKValueTagType) {
                
                if (keyValue)
                    [result appendAttributedString:[keyValue templateAttributedStringValueWithAttributes:[(SKRichValueTag *)tag attributes]]];
                
            } else if (type == SKCollectionTagType) {
                
                if ([keyValue respondsToSelector:@selector(objectEnumerator)]) {
                    NSEnumerator *itemE = [keyValue objectEnumerator];
                    id nextItem, item = [itemE nextObject];
                    NSArray *itemTemplate = [[tag itemTemplate] arrayByAddingObjectsFromArray:[tag separatorTemplate]];
                    int idx = 0;
                    while (item) {
                        nextItem = [itemE nextObject];
                        if (nextItem == nil)
                            itemTemplate = [tag itemTemplate];
                        tmpAttrStr = [self attributedStringFromTemplateArray:itemTemplate usingObject:item atIndex:++idx];
                        if (tmpAttrStr != nil)
                            [result appendAttributedString:tmpAttrStr];
                        item = nextItem;
                    }
                }
                
            } else {
                
                NSString *matchString = nil;
                BOOL isMatch;
                NSArray *matchStrings = [tag matchStrings];
                unsigned int i, count = [matchStrings count];
                NSArray *subtemplate = nil;
                
                count = [matchStrings count];
                subtemplate = nil;
                for (i = 0; i < count; i++) {
                    matchString = [matchStrings objectAtIndex:i];
                    if ([matchString hasPrefix:@"$"]) {
                        matchString = [[object templateValueForKeyPath:[matchString substringFromIndex:1]] templateStringValue];
                        if (matchString == nil)
                            matchString = @"";
                    }
                    switch ([tag matchType]) {
                        case SKConditionTagMatchEqual:
                            isMatch = [matchString isEqualToString:@""] ? NO == [keyValue isNotEmpty] : [[keyValue templateStringValue] caseInsensitiveCompare:matchString] == NSOrderedSame;
                            break;
                        case SKConditionTagMatchContain:
                            isMatch = [matchString isEqualToString:@""] ? NO == [keyValue isNotEmpty] : [[keyValue templateStringValue] rangeOfString:matchString options:NSCaseInsensitiveSearch].location != NSNotFound;
                            break;
                        case SKConditionTagMatchSmaller:
                            isMatch = [matchString isEqualToString:@""] ? NO == [keyValue isNotEmpty] : [[keyValue templateStringValue] localizedCaseInsensitiveNumericCompare:matchString] == NSOrderedAscending;
                            break;
                        case SKConditionTagMatchSmallerOrEqual:
                            isMatch = [matchString isEqualToString:@""] ? NO == [keyValue isNotEmpty] : [[keyValue templateStringValue] localizedCaseInsensitiveNumericCompare:matchString] != NSOrderedDescending;
                            break;
                        default:
                            isMatch = [keyValue isNotEmpty];
                            break;
                    }
                    if (isMatch) {
                        subtemplate = [tag subtemplateAtIndex:i];
                        break;
                    }
                }
                if (subtemplate == nil && [[tag subtemplates] count] > count) {
                    subtemplate = [tag subtemplateAtIndex:count];
                }
                if (subtemplate != nil) {
                    tmpAttrStr = [self attributedStringFromTemplateArray:subtemplate usingObject:object atIndex:anIndex];
                    [result appendAttributedString:tmpAttrStr];
                }
                
            }
            
        }
    } // while
    
    [result fixAttributesInRange:NSMakeRange(0, [result length])];
    
    return [result autorelease];    
}

@end

#pragma mark -

@implementation NSObject (SKTemplateParser)

- (BOOL)isNotEmpty {
    if ([self respondsToSelector:@selector(count)])
        return [(id)self count] > 0;
    if ([self respondsToSelector:@selector(length)])
        return [(id)self length] > 0;
    return YES;
}

- (id)safeValueForKeyPath:(NSString *)keyPath {
    id value = nil;
    @try{ value = [self valueForKeyPath:keyPath]; }
    @catch (id exception) { value = nil; }
    return value;
}

- (id)templateValueForKeyPath:(NSString *)keyPath {
    unsigned int atIndex = [keyPath rangeOfString:@"@"].location;
    if (atIndex != NSNotFound) {
        unsigned int dotIndex = [keyPath rangeOfString:@"." options:0 range:NSMakeRange(atIndex + 1, [keyPath length] - atIndex - 1)].location;
        if (dotIndex != NSNotFound) {
            static NSSet *arrayOperators = nil;
            if (arrayOperators == nil)
                arrayOperators = [[NSSet alloc] initWithObjects:@"@avg", @"@max", @"@min", @"@sum", @"@distinctUnionOfArrays", @"@distinctUnionOfObjects", @"@distinctUnionOfSets", @"@unionOfArrays", @"@unionOfObjects", @"@unionOfSets", nil];
            if ([arrayOperators containsObject:[keyPath substringWithRange:NSMakeRange(atIndex, dotIndex - atIndex)]] == NO)
                return [[self safeValueForKeyPath:[keyPath substringToIndex:dotIndex]] templateValueForKeyPath:[keyPath substringFromIndex:dotIndex + 1]];
        }
    }
    return [self safeValueForKeyPath:keyPath];
}

- (NSString *)templateStringValue {
    NSString *description = nil;
    if ([self respondsToSelector:@selector(stringValue)])
        description = [self performSelector:@selector(stringValue)];
    if ([self respondsToSelector:@selector(string)])
        description = [self performSelector:@selector(string)];
    return description ? description : [self description];
}

- (NSAttributedString *)templateAttributedStringValueWithAttributes:(NSDictionary *)attributes {
    return [[[NSAttributedString alloc] initWithString:[self templateStringValue] attributes:attributes] autorelease];
}

@end

#pragma mark -

@implementation NSScanner (SKTemplateParser)

- (BOOL)scanEmptyLine {
    BOOL foundEndOfLine = NO;
    BOOL foundWhitespace = NO;
    int startLoc = [self scanLocation];
    
    // [self scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:nil] is much more sensible, but NSScanner creates an autoreleased inverted character set every time you use it, so it's pretty inefficient
    foundWhitespace = [self scanUpToCharactersFromSet:[NSCharacterSet nonWhitespaceCharacterSet] intoString:nil];

    if ([self isAtEnd]) {
        foundEndOfLine = foundWhitespace;
    } else {
        foundEndOfLine = [self scanString:@"\r\n" intoString:nil];
        if (foundEndOfLine == NO) {
            unichar nextChar = [[self string] characterAtIndex:[self scanLocation]];
            if (foundEndOfLine = [[NSCharacterSet newlineCharacterSet] characterIsMember:nextChar])
                [self setScanLocation:[self scanLocation] + 1];
        }
    }
    if (foundEndOfLine == NO && foundWhitespace == YES)
        [self setScanLocation:startLoc];
    return foundEndOfLine;
}

@end

#pragma mark -

@interface NSAttributedString (SKTemplateParser)
@end

@implementation NSAttributedString (SKTemplateParser)

- (NSAttributedString *)templateAttributedStringValueWithAttributes:(NSDictionary *)attributes {
    NSMutableAttributedString *attributedString = [self mutableCopy];
    unsigned idx = 0, length = [self length];
    NSRange range = NSMakeRange(0, length);
    NSDictionary *attrs;
    [attributedString addAttributes:attributes range:range];
    while (idx < length) {
        attrs = [self attributesAtIndex:idx effectiveRange:&range];
        if (range.length > 0) {
            [attributedString addAttributes:attrs range:range];
            idx = NSMaxRange(range);
        } else idx++;
    }
    [attributedString fixAttributesInRange:NSMakeRange(0, length)];
    return [attributedString autorelease];
}

@end

#pragma mark -

@interface NSData (SKTemplateParser)
@end

@implementation NSData (SKTemplateParser)
- (NSString *)templateStringValue { return [[[NSString alloc] initWithData:self encoding:NSUTF8StringEncoding] autorelease]; }
@end

#pragma mark -

@implementation NSString (SKTemplateParser)

- (NSString *)templateStringValue{ return self; }

#pragma mark Empty lines

// whitespace at the beginning of the string up to and including a newline
- (NSRange)rangeOfLeadingEmptyLine {
    return [self rangeOfLeadingEmptyLineRequiringNewline:YES];
}

- (NSRange)rangeOfLeadingEmptyLineRequiringNewline:(BOOL)requireNL {
    return [self rangeOfLeadingEmptyLineRequiringNewline:requireNL range:NSMakeRange(0, [self length])];
}

- (NSRange)rangeOfLeadingEmptyLineInRange:(NSRange)range {
    return [self rangeOfLeadingEmptyLineRequiringNewline:YES range:range];
}

- (NSRange)rangeOfLeadingEmptyLineRequiringNewline:(BOOL)requireNL range:(NSRange)range {
    NSRange firstCharRange = [self rangeOfCharacterFromSet:[NSCharacterSet nonWhitespaceCharacterSet] options:0 range:range];
    NSRange wsRange = NSMakeRange(NSNotFound, 0);
    unsigned int start = range.location;
    if (firstCharRange.location == NSNotFound) {
        if (requireNL == NO)
            wsRange = range;
    } else {
        unichar firstChar = [self characterAtIndex:firstCharRange.location];
        unsigned int rangeEnd = NSMaxRange(firstCharRange);
        if([[NSCharacterSet newlineCharacterSet] characterIsMember:firstChar]) {
            if (firstChar == NSCarriageReturnCharacter && rangeEnd < NSMaxRange(range) && [self characterAtIndex:rangeEnd] == NSNewlineCharacter)
                wsRange = NSMakeRange(start, rangeEnd + 1 - start);
            else 
                wsRange = NSMakeRange(start, rangeEnd - start);
        }
    }
    return wsRange;
}

// whitespace at the end of the string after a newline
- (NSRange)rangeOfTrailingEmptyLine {
    return [self rangeOfTrailingEmptyLineRequiringNewline:YES];
}

- (NSRange)rangeOfTrailingEmptyLineRequiringNewline:(BOOL)requireNL {
    return [self rangeOfTrailingEmptyLineRequiringNewline:requireNL range:NSMakeRange(0, [self length])];
}

- (NSRange)rangeOfTrailingEmptyLineInRange:(NSRange)range {
    return [self rangeOfTrailingEmptyLineRequiringNewline:YES range:range];
}

- (NSRange)rangeOfTrailingEmptyLineRequiringNewline:(BOOL)requireNL range:(NSRange)range {
    NSRange lastCharRange = [self rangeOfCharacterFromSet:[NSCharacterSet nonWhitespaceCharacterSet] options:NSBackwardsSearch range:range];
    NSRange wsRange = NSMakeRange(NSNotFound, 0);
    unsigned int end = NSMaxRange(range);
    if (lastCharRange.location == NSNotFound) {
        if (requireNL == NO)
            wsRange = range;
    } else {
        unichar lastChar = [self characterAtIndex:lastCharRange.location];
        unsigned int rangeEnd = NSMaxRange(lastCharRange);
        if ([[NSCharacterSet newlineCharacterSet] characterIsMember:lastChar])
            wsRange = NSMakeRange(rangeEnd, end - rangeEnd);
    }
    return wsRange;
}

@end

#pragma mark -

@interface NSNumber (SKTemplateParser)
@end

@implementation NSNumber (SKTemplateParser)
- (BOOL)isNotEmpty { return [self isEqualToNumber:[NSNumber numberWithBool:NO]] == NO && [self isEqualToNumber:[NSNumber numberWithInt:0]] == NO; }
@end
