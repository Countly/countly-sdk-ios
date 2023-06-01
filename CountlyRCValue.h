//
//  CLYRCValue.h
//  Countly
//
//  Created by Muhammad Junaid Akram on 31/05/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CountlyRCValue : NSObject

@property (nonatomic) id value;
@property (nonatomic) CLYRCValueState valueState;
@property (nonatomic) NSTimeInterval timestamp;

- (instancetype)initWithValue:(id)value valueState:(CLYRCValueState)valueState timestamp:(NSTimeInterval) timestamp;
- (CLYRCValueState) valueState;

@end



