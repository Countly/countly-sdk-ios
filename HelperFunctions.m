//
//  HelperFunctions.m
//  Navirize
//
//  Created by Hamdy on 8/13/15.
//  Copyright (c) 2015 RizeInnoFZCO. All rights reserved.
//

#import "HelperFunctions.h"

@implementation HelperFunctions

#if COUNTLY_DEBUG
#   define COUNTLY_LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#   define COUNTLY_LOG(...)
#endif


NSString* CountlyJSONFromObject(id object)
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    
    if (error)
        COUNTLY_LOG(@"%@", [error description]);
    
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

NSString* CountlyURLEscapedString(NSString* string)
{
    // Encode all the reserved characters, per RFC 3986
    // (<http://www.ietf.org/rfc/rfc3986.txt>)
    CFStringRef escaped =
    CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                            (CFStringRef)string,
                                            NULL,
                                            (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                            kCFStringEncodingUTF8);
    return (NSString*)CFBridgingRelease(escaped);
}

NSString* CountlyURLUnescapedString(NSString* string)
{
    NSMutableString *resultString = [NSMutableString stringWithString:string];
    [resultString replaceOccurrencesOfString:@"+"
                                  withString:@" "
                                     options:NSLiteralSearch
                                       range:NSMakeRange(0, [resultString length])];
    return [resultString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

@end
