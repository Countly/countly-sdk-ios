// CountlyDB.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import "CountlyDB.h"

#if __has_feature(objc_arc)
#error  This is a non-ARC class. Please add -fno-objc-arc flag for Countly.m, Countly_OpenUDID.m and CountlyDB.m under Build Phases > Compile Sources
#endif

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

+(instancetype)sharedInstance
{
    static CountlyDB* s_sharedCountlyDB;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedCountlyDB = self.new;});
	return s_sharedCountlyDB;
}

-(void)createEvent:(NSString*) eventKey count:(double)count sum:(double)sum segmentation:(NSDictionary*)segmentation timestamp:(NSTimeInterval)timestamp
{
    NSManagedObjectContext *context = [self managedObjectContext];
    NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:@"Event" inManagedObjectContext:context];

    [newManagedObject setValue:eventKey forKey:@"key"];
    [newManagedObject setValue:@(count) forKey:@"count"];
    [newManagedObject setValue:@(sum) forKey:@"sum"];
    [newManagedObject setValue:@(timestamp) forKey:@"timestamp"];
    [newManagedObject setValue:segmentation forKey:@"segmentation"];
    
    [self saveContext];
}

-(void)deleteEvent:(NSManagedObject*)eventObj
{
    NSManagedObjectContext *context = [self managedObjectContext];
    [context deleteObject:eventObj];
    [self saveContext];
}

-(void)addToQueue:(NSString*)postData
{
    NSManagedObjectContext *context = [self managedObjectContext];
    NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:@"Data" inManagedObjectContext:context];
    
    [newManagedObject setValue:postData forKey:@"post"];
    
    [self saveContext];
}

-(void)removeFromQueue:(NSManagedObject*)postDataObj
{
    NSManagedObjectContext *context = [self managedObjectContext];
    [context deleteObject:postDataObj];
    [self saveContext];
}

-(NSArray*) getEvents
{
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Event" inManagedObjectContext:[self managedObjectContext]];
    [fetchRequest setEntity:entity];
    
    NSError* error = nil;
    NSArray* result = [[self managedObjectContext] executeFetchRequest:fetchRequest error:&error];
    
    if (error)
    {
        COUNTLY_LOG(@"CoreData error %@, %@", error, [error userInfo]);
    }
    
    return result;
}

-(NSArray*) getQueue
{
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Data" inManagedObjectContext:[self managedObjectContext]];
    [fetchRequest setEntity:entity];
    
    NSError* error = nil;
    NSArray* result = [[self managedObjectContext] executeFetchRequest:fetchRequest error:&error];
    
    if (error)
    {
         COUNTLY_LOG(@"CoreData error %@, %@", error, [error userInfo]);
    }
    
    return result;
}

-(NSUInteger)getEventCount
{
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Event" inManagedObjectContext:[self managedObjectContext]];
    [fetchRequest setEntity:entity];
    
    NSError* error = nil;
    NSUInteger count = [[self managedObjectContext] countForFetchRequest:fetchRequest error:&error];
    
    if (error)
    {
        COUNTLY_LOG(@"CoreData error %@, %@", error, [error userInfo]);
    }
    
    return count;
}

-(NSUInteger)getQueueCount
{
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Data" inManagedObjectContext:[self managedObjectContext]];
    [fetchRequest setEntity:entity];
    
    NSError* error = nil;
    NSUInteger count = [[self managedObjectContext] countForFetchRequest:fetchRequest error:&error];
    
    if (error)
    {
        COUNTLY_LOG(@"CoreData error %@, %@", error, [error userInfo]);
    }
    
    return count;
}


- (void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = [self managedObjectContext];
    if (managedObjectContext != nil)
    {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error])
        {
           COUNTLY_LOG(@"CoreData error %@, %@", error, [error userInfo]);
        }
    }
}

- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

#pragma mark - Core Data Instance

- (NSManagedObjectContext *)managedObjectContext
{
    static NSManagedObjectContext* s_managedObjectContext;
    
    if (s_managedObjectContext != nil)
        return s_managedObjectContext;
    
    static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
        NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
        if (coordinator != nil)
        {
            s_managedObjectContext = [[NSManagedObjectContext alloc] init];
            [s_managedObjectContext setPersistentStoreCoordinator:coordinator];
        }
    });
    
    return s_managedObjectContext;
}

- (NSManagedObjectModel *)managedObjectModel
{
    static NSManagedObjectModel* s_managedObjectModel;

    if (s_managedObjectModel != nil)
        return s_managedObjectModel;

    static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
        NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Countly" withExtension:@"momd"];
        s_managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    });

    return s_managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    static NSPersistentStoreCoordinator* s_persistentStoreCoordinator;
    
    if (s_persistentStoreCoordinator != nil)
        return s_persistentStoreCoordinator;
    
    static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
        NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"Countly.sqlite"];
        NSError *error = nil;
        s_persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
        if (![s_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
            COUNTLY_LOG(@"CoreData error %@, %@", error, [error userInfo]);
    });

    return s_persistentStoreCoordinator;
}

@end