//
//  CountlyViewData.h
//  Countly
//
//  Created by Muhammad Junaid Akram on 26/07/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CountlyViewData : NSObject

@property (nonatomic) NSString* viewID;
@property (nonatomic) NSString* viewName;
@property (nonatomic) NSTimeInterval viewStartTime;
@property (nonatomic) NSTimeInterval viewAccumulatedTime;

@end
