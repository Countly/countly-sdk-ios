//
//  HelperFunctions.h
//  Navirize
//
//  Created by Hamdy on 8/13/15.
//  Copyright (c) 2015 RizeInnoFZCO. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HelperFunctions : NSObject
NSString* CountlyJSONFromObject(id object);
NSString* CountlyURLEscapedString(NSString* string);
NSString* CountlyURLUnescapedString(NSString* string);
@end
