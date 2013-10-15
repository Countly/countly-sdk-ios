//
//  CountlyDB.h
//  Countly
//
//  Created by Nesim Tunç on 21.07.2013.
//  Copyright (c) 2013 Nesim Tunç. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface CountlyDB : NSObject

@property (readonly, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

+ (CountlyDB*) sharedInstance;

- (void)createEvent:(NSString*) eventKey count:(double)count sum:(double)sum segmentation:(NSDictionary*)segmentation timestamp:(double)timestamp;
- (void)addToQueue:(NSString*)postData;
- (void)deleteEvent:(NSManagedObject*)eventObj;
- (void)removeFromQueue:(NSManagedObject*)postDataObj;
- (NSArray*)events;
- (NSArray*)queue;
- (NSUInteger)eventCount;
- (NSUInteger)queueCount;
- (void)saveContext;

@end
