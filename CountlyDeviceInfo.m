//
//  Test.m
//  Navirize
//
//  Created by Hamdy on 8/13/15.
//  Copyright (c) 2015 RizeInnoFZCO. All rights reserved.
//

#import "CountlyDeviceInfo.h"


#import "Countly_OpenUDID.h"

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#if COUNTLY_PREFER_IDFA
#import <AdSupport/ASIdentifierManager.h>
#endif
#endif

#include <sys/types.h>
#include <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#include <libkern/OSAtomic.h>
#include <execinfo.h>


#import "HelperFunctions.h"

#pragma mark - CountlyDeviceInfo



@implementation CountlyDeviceInfo

+ (NSString *)udid
{
    
#if COUNTLY_PREFER_IDFA && (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR || COUNTLY_TARGET_WATCHKIT)
    return ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString;
#else
    return [Countly_OpenUDID value];
#endif
}

+ (NSString *)device
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    char *modelKey = "hw.machine";
#else
    char *modelKey = "hw.model";
#endif
    size_t size;
    sysctlbyname(modelKey, NULL, &size, NULL, 0);
    char *model = malloc(size);
    sysctlbyname(modelKey, model, &size, NULL, 0);
    NSString *modelString = @(model);
    free(model);
    return modelString;
}

+ (NSString *)osName
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    return @"iOS";
#else
    return @"OS X";
#endif
}

+ (NSString *)osVersion
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    return [[UIDevice currentDevice] systemVersion];
#else
    return [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"][@"ProductVersion"];
#endif
}

+ (NSString *)carrier
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    if (NSClassFromString(@"CTTelephonyNetworkInfo"))
    {
        CTTelephonyNetworkInfo *netinfo = [CTTelephonyNetworkInfo new];
        CTCarrier *carrier = [netinfo subscriberCellularProvider];
        return [carrier carrierName];
    }
#endif
    return nil;
}

+ (NSString *)resolution
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat scale = [UIScreen.mainScreen respondsToSelector:@selector(scale)] ? [UIScreen.mainScreen scale] : 1.f;
    return [NSString stringWithFormat:@"%gx%g", bounds.size.width * scale, bounds.size.height * scale];
#else
    NSRect screenRect = NSScreen.mainScreen.frame;
    CGFloat scale = [NSScreen.mainScreen backingScaleFactor];
    return [NSString stringWithFormat:@"%gx%g", screenRect.size.width * scale, screenRect.size.height * scale];
#endif
}

+ (NSString *)locale
{
    return [[NSLocale currentLocale] localeIdentifier];
}

+ (NSString *)appVersion
{
    NSString *result = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if ([result length] == 0)
        result = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString*)kCFBundleVersionKey];
    
    return result;
}

+ (NSString *)metrics
{
    NSMutableDictionary* metricsDictionary = [NSMutableDictionary dictionary];
    metricsDictionary[@"_device"] = CountlyDeviceInfo.device;
    metricsDictionary[@"_os"] = CountlyDeviceInfo.osName;
    metricsDictionary[@"_os_version"] = CountlyDeviceInfo.osVersion;
    
    NSString *carrier = CountlyDeviceInfo.carrier;
    if (carrier)
        metricsDictionary[@"_carrier"] = carrier;
    
    metricsDictionary[@"_resolution"] = CountlyDeviceInfo.resolution;
    metricsDictionary[@"_locale"] = CountlyDeviceInfo.locale;
    metricsDictionary[@"_app_version"] = CountlyDeviceInfo.appVersion;
    
    return CountlyURLEscapedString(CountlyJSONFromObject(metricsDictionary));
}

+ (NSString *)bundleId
{
    return [[NSBundle mainBundle] bundleIdentifier];
}

@end