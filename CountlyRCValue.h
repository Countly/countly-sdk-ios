//
//  CLYRCValue.h
//  Countly
//
//  Created by Muhammad Junaid Akram on 31/05/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CountlyRCMeta : NSObject

@property (nonatomic) NSString *deviceID;
@property (nonatomic) NSTimeInterval timestamp;

- (instancetype)initWithDeviceID:(NSString *)deviceID timestamp:(NSTimeInterval) timestamp;
- (CLYRCValueState) valueState;

@end

@interface CountlyRCValue : NSObject

@property (nonatomic) id value;
@property (nonatomic) NSTimeInterval timestamp;
@property (nonatomic) CLYRCValueState valueState;

- (instancetype)initWithValue:(id)value meta:(CountlyRCMeta *) meta;

@end



