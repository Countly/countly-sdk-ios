//
//  CountlyHealthTracker.h
//  CountlyTestApp-iOS
//
//  Created by Arif Burak Demiray on 20.05.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
#import <Foundation/Foundation.h>

@interface CountlyHealthTracker : NSObject

+ (instancetype)sharedInstance;

- (void)logWarning;

- (void)logError;

- (void)logFailedNetworkRequestWithStatusCode:(NSInteger)statusCode
                                errorResponse:(NSString *)errorResponse;

- (void)logBackoffRequest;

- (void)logConsecutiveBackoffRequest;

- (void)clearAndSave;

- (void)saveState;

- (void)sendHealthCheck;

@end
