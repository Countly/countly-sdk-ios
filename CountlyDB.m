//
//  CountlyDB.m
//  Countly
//
//  Created by Nesim Tunç on 21.07.2013.
//  Copyright (c) 2013 Nesim Tunç. All rights reserved.
//

#import "CountlyDB.h"

#ifndef COUNTLY_DEBUG
#define COUNTLY_DEBUG 0
#endif

#if COUNTLY_DEBUG
#   define COUNTLY_LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#   define COUNTLY_LOG(...)
#endif

@interface CountlyDB()
- (NSURL *)applicationDocumentsDirectory;
@end

@implementation CountlyDB

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

+(CountlyDB*) sharedInstance{
    static CountlyDB* _sharedInstance;
    if (!_sharedInstance) _sharedInstance = [[CountlyDB alloc] init];
    return _sharedInstance;
}

- (void)dealloc{
    [_managedObjectContext release];
    [_managedObjectModel release];
    [_persistentStoreCoordinator release];
    [super dealloc];
}

-(void)createEvent:(NSString*) eventKey count:(double)count sum:(double)sum segmentation:(NSDictionary*)segmentation timestamp:(double)timestamp{
    NSManagedObjectContext *context = [self managedObjectContext];
    NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:@"Event" inManagedObjectContext:context];

    [newManagedObject setValue:eventKey forKey:@"key"];
    [newManagedObject setValue:[NSNumber numberWithDouble:count] forKey:@"count"];
    [newManagedObject setValue:[NSNumber numberWithDouble:sum] forKey:@"sum"];
    [newManagedObject setValue:[NSNumber numberWithDouble:timestamp] forKey:@"timestamp"];
    [newManagedObject setValue:segmentation forKey:@"segmentation"];
    
    [self saveContext];
}

-(void)deleteEvent:(NSManagedObject*)eventObj{
    NSManagedObjectContext *context = [self managedObjectContext];
    [context deleteObject:eventObj];
    [self saveContext];
}

-(void)addToQueue:(NSString*)postData{
    NSManagedObjectContext *context = [self managedObjectContext];
    NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:@"Data" inManagedObjectContext:context];
    
    [newManagedObject setValue:postData forKey:@"post"];
    
    [self saveContext];
}

-(void)removeFromQueue:(NSManagedObject*)postDataObj{
    NSManagedObjectContext *context = [self managedObjectContext];
    [context deleteObject:postDataObj];
    [self saveContext];
}

-(NSArray*) getEvents{
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Event" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSError* error = nil;
    NSArray* result = [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    
    if (!error){
        COUNTLY_LOG(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    
    return result;
}

-(NSArray*) getQueue{
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Data" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSError* error = nil;
    NSArray* result = [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    
    if (!error){
         COUNTLY_LOG(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    
    return result;
}

-(NSUInteger)getEventCount{
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Event" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSError* error = nil;
    NSUInteger count = [_managedObjectContext countForFetchRequest:fetchRequest error:&error];
    
    if (!error){
        COUNTLY_LOG(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    return count;
}

-(NSUInteger)getQueueCount{
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Data" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSError* error = nil;
    NSUInteger count = [_managedObjectContext countForFetchRequest:fetchRequest error:&error];
    
    if (!error){
        COUNTLY_LOG(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    return count;
}


- (void)saveContext{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
           COUNTLY_LOG(@"Unresolved error %@, %@", error, [error userInfo]);
        }
    }
}

- (NSURL *)applicationDocumentsDirectory{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        _managedObjectContext = [[NSManagedObjectContext alloc] init];
        [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return _managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Countly" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"Countly.sqlite"];

    NSError *error = nil;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    
    return _persistentStoreCoordinator;
}

@end