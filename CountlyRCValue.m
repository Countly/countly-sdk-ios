//
//  CLYRCValue.m
//  Countly
//
//  Created by Muhammad Junaid Akram on 31/05/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

#import "CountlyCommon.h"

@implementation CountlyRCValue

- (instancetype)init
{
    if (self = [super init])
    {
        self.value = nil;
        self.valueState = CLYNoValue;
    }
    
    return self;
}

- (instancetype)initWithValue:(id)value meta:(CountlyRCMeta *) meta
{
    if (self = [super init])
    {
        self.value = value;
        if(meta) {
            self.timestamp = meta.timestamp;
            self.valueState = meta.valueState;
        }
    }
    
    return self;
}

@end

@implementation CountlyRCMeta


- (void)encodeWithCoder:(NSCoder *)encoder {
    
    [encoder encodeObject:self.deviceID forKey:NSStringFromSelector(@selector(deviceID))];
    [encoder encodeDouble:self.timestamp forKey:NSStringFromSelector(@selector(timestamp))];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if((self = [super init])) {
        self.deviceID = [decoder decodeObjectForKey:NSStringFromSelector(@selector(deviceID))];
        self.timestamp = [decoder decodeDoubleForKey:NSStringFromSelector(@selector(timestamp))];
    }
    return self;
}

- (instancetype)init
{
    if (self = [super init])
    {
    }
    
    return self;
}

- (instancetype)initWithDeviceID:(NSString *)deviceID timestamp:(NSTimeInterval) timestamp
{
    if (self = [super init])
    {
        self.deviceID = deviceID;
        self.timestamp = timestamp;
    }
    
    return self;
}

- (CLYRCValueState) valueState
{
    if(self.deviceID)
    {
       if([self.deviceID isEqualToString:[Countly.sharedInstance deviceID]] )
       {
           return CLYCurrentUser;
       }
       else {
           return CLYCached;
       }
    }
    return  CLYNoValue ;
}


@end
