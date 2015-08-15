//
//  Test.h
//  Navirize
//
//  Created by Hamdy on 8/13/15.
//  Copyright (c) 2015 RizeInnoFZCO. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CountlyDeviceInfo : NSObject

+ (NSString *)udid;
+ (NSString *)device;
+ (NSString *)osName;
+ (NSString *)osVersion;
+ (NSString *)carrier;
+ (NSString *)resolution;
+ (NSString *)locale;
+ (NSString *)appVersion;

+ (NSString *)metrics;

+ (NSString *)bundleId;

@end
