// CountlyConnectionManager.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyConnectionManager : NSObject

+ (instancetype)sharedInstance
{
    static CountlyConnectionManager *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (void)tick
{
    if (self.connection != nil || CountlyPersistency.sharedInstance.queuedRequests.count == 0)
        return;

    [self startBackgroundTask];
    
    NSString* currentRequestData = CountlyPersistency.sharedInstance.queuedRequests.firstObject;
    NSString* urlString = [NSString stringWithFormat:@"%@/i", self.appHost];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [currentRequestData dataUsingEncoding:NSUTF8StringEncoding];
    
#if TARGET_OS_IOS
    NSString* picturePath = [CountlyUserDetails.sharedInstance extractPicturePathFromURLString:currentRequestData];
    if(picturePath && ![picturePath isEqualToString:@""])
    {
        COUNTLY_LOG(@"picturePath: %@", picturePath);

        NSArray* allowedFileTypes = @[@"gif",@"png",@"jpg",@"jpeg"];
        NSString* fileExt = picturePath.pathExtension.lowercaseString;
        NSInteger fileExtIndex = [allowedFileTypes indexOfObject:fileExt];
        
        if(fileExtIndex != NSNotFound)
        {
            NSData* imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:picturePath]];
            if (fileExtIndex == 1) imageData = UIImagePNGRepresentation([UIImage imageWithData:imageData]); //NOTE: for png upload fix. (png file data read directly from disk fails on upload)
            if (fileExtIndex == 2) fileExtIndex = 3; //NOTE: for mime type jpg -> jpeg
            
            if (imageData)
            {
                COUNTLY_LOG(@"local image retrieved from picturePath");
                
                NSString *boundary = @"c1c673d52fea01a50318d915b6966d5e";
                
                NSString *contentType = [@"multipart/form-data; boundary=" stringByAppendingString:boundary];
                [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
                
                NSMutableData *body = request.HTTPBody.mutableCopy;
                [body appendStringUTF8:[NSString stringWithFormat:@"--%@\r\n", boundary]];
                [body appendStringUTF8:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"pictureFile\"; filename=\"%@\"\r\n",picturePath.lastPathComponent]];
                [body appendStringUTF8:[NSString stringWithFormat:@"Content-Type: image/%@\r\n\r\n", allowedFileTypes[fileExtIndex]]];
                [body appendData:imageData];
                [body appendStringUTF8:[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary]];
                request.HTTPBody = body;
            }
        }
    }
#endif

    self.connection = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                   completionHandler:^(NSData * _Nullable data,
                                                                       NSURLResponse * _Nullable response,
                                                                       NSError * _Nullable error)
    {
        self.connection = nil;

        if(!error && data)
        {
            NSDictionary* serverReply = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

            if(([serverReply[@"result"] isEqualToString:@"Success"]))
            {
                COUNTLY_LOG(@"Request successfully completed");

                @synchronized(self)
                {
                    [CountlyPersistency.sharedInstance.queuedRequests removeObject:currentRequestData];
                }

                [CountlyPersistency.sharedInstance saveToFile];

                [self tick];
            }
        }
        else
        {
            COUNTLY_LOG(@"Request failed %@ \n %@ \n Error: %@", urlString, [currentRequestData description], error);
#if TARGET_OS_WATCH
            [CountlyPersistency.sharedInstance saveToFile];
#endif
        }
    
        [self finishBackgroundTask];
    }];
    
    [self.connection resume];
    
    COUNTLY_LOG(@"Request started %@ with body:\n%@", urlString, currentRequestData);
}

#pragma mark ---

- (void)beginSession
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&begin_session=1&metrics=%@",
                             [CountlyDeviceInfo metrics]];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self tick];
}

- (void)updateSessionWithDuration:(int)duration
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&session_duration=%d", duration];
        
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self tick];
}

- (void)endSessionWithDuration:(int)duration
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&end_session=1&session_duration=%d", duration];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self tick];
}

- (void)sendEvents
{
    NSMutableArray* eventsArray = NSMutableArray.new;
    @synchronized (self)
    {
        if(CountlyPersistency.sharedInstance.recordedEvents.count == 0)
            return;
    
        for (CountlyEvent* event in CountlyPersistency.sharedInstance.recordedEvents.copy)
        {
            [eventsArray addObject:[event dictionaryRepresentation]];
            [CountlyPersistency.sharedInstance.recordedEvents removeObject:event];
        }
    }
    
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&events=%@", [eventsArray JSONify]];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self tick];
}

#pragma mark ---

- (void)sendPushToken:(NSString*)token
{
    // Test modes: 0 = production mode, 1 = development build, 2 = Ad Hoc build
    int testMode;
#ifndef __OPTIMIZE__
    testMode = 1;
#else
    testMode = self.startedWithTest ? 2 : 0;
#endif
    
    COUNTLY_LOG(@"Sending APN token in mode %d", testMode);
    
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&token_session=1&ios_token=%@&test_mode=%d",
                             [token length] ? token : @"",
                             testMode];

    // Not right now to prevent race with begin_session=1 when adding new user
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [CountlyPersistency.sharedInstance addToQueue:queryString];
        [self tick];
    });
}

- (void)sendUserDetails:(NSString*)userDetails
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&user_details=%@",
                             userDetails];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self tick];
}

- (void)sendCrashReportLater:(NSString *)report
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&crash=%@", report];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [CountlyPersistency.sharedInstance saveToFileSync];
}

- (void)sendOldDeviceID:(NSString *)oldDeviceID
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&old_device_id=%@",oldDeviceID];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self tick];
}

- (void)sendParentDeviceID:(NSString *)parentDeviceID
{    
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&parent_device_id=%@",parentDeviceID];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self tick];
}

- (void)sendLocation:(CLLocationCoordinate2D)coordinate
{
    NSString* locationString = [NSString stringWithFormat:@"%f,%f", coordinate.latitude, coordinate.longitude];

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&location=%@",locationString];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

#pragma mark ---

- (void)startBackgroundTask
{
#if TARGET_OS_IOS
    if (self.bgTask != UIBackgroundTaskInvalid)
        return;
    
    self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }];
#endif
}

- (void)finishBackgroundTask
{
#if TARGET_OS_IOS
    if (self.bgTask != UIBackgroundTaskInvalid)
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif
}

#pragma mark ---

- (NSString *)queryEssentials
{
    return [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&hour=%ld&dow=%ld&sdk_version=%@",
                                        self.appKey,
                                        CountlyDeviceInfo.sharedInstance.deviceID,
                                        (long)NSDate.date.timeIntervalSince1970,
                                        (long)[CountlyCommon.sharedInstance hourOfDay],
                                        (long)[CountlyCommon.sharedInstance dayOfWeek],
                                        COUNTLY_SDK_VERSION];
}

@end