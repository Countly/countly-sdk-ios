//
//  CLYRCValue.m
//  Countly
//
//  Created by Muhammad Junaid Akram on 31/05/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

#import "CountlyCommon.h"

@implementation CountlyRCValue


- (void)encodeWithCoder:(NSCoder *)encoder {
    
    [encoder encodeObject:self.value forKey:NSStringFromSelector(@selector(valueState))];
    [encoder encodeObject:self.valueState forKey:NSStringFromSelector(@selector(valueState))];
    [encoder encodeDouble:self.timestamp forKey:NSStringFromSelector(@selector(timestamp))];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if((self = [super init])) {
        self.value = [decoder decodeObjectForKey:NSStringFromSelector(@selector(valueState))];
        self.valueState = [decoder decodeObjectForKey:NSStringFromSelector(@selector(valueState))];
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

- (instancetype)initWithValue:(id)value valueState:(CLYRCValueState)valueState timestamp:(NSTimeInterval) timestamp;
{
    if (self = [super init])
    {
        self.value = value;
        self.valueState = valueState;
        self.timestamp = timestamp;
    }
    
    return self;
}


@end
