//
//  CLYRCValue.h
//  Countly
//
//  Created by Muhammad Junaid Akram on 31/05/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CountlyRCData : NSObject

@property (nonatomic) id value;
@property (nonatomic) BOOL isCurrentUsersData;

- (instancetype)initWithValue:(id)value isCurrentUsersData:(BOOL)isCurrentUsersData;

@end



