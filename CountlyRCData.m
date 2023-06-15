//
//  CLYRCValue.m
//  Countly
//
//  Created by Muhammad Junaid Akram on 31/05/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

#import "CountlyCommon.h"

@implementation CountlyRCData


- (void)encodeWithCoder:(NSCoder *)encoder {
    
    [encoder encodeObject:self.value forKey:NSStringFromSelector(@selector(value))];
    [encoder encodeBool:self.isCurrentUsersData forKey:NSStringFromSelector(@selector(isCurrentUsersData))];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if((self = [super init])) {
        self.value = [decoder decodeObjectForKey:NSStringFromSelector(@selector(value))];
        self.isCurrentUsersData = [decoder decodeBoolForKey:NSStringFromSelector(@selector(isCurrentUsersData))];
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

- (instancetype)initWithValue:(id)value isCurrentUsersData:(BOOL)isCurrentUsersData;
{
    if (self = [super init])
    {
        self.value = value;
        self.isCurrentUsersData = isCurrentUsersData;
    }
    
    return self;
}


@end
