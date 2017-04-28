// CountlyNotificationService.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyActionIdentifier = @"CountlyActionIdentifier";
NSString* const kCountlyCategoryIdentifier = @"CountlyCategoryIdentifier";

@interface CountlyNotificationService ()
#if TARGET_OS_IOS
@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;
#endif
@end

@implementation CountlyNotificationService
#if TARGET_OS_IOS
+ (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent *))contentHandler
{
    NSLog(@"[NSE] notification modification in progress...");

    UNMutableNotificationContent* bestAttemptContent = request.content.mutableCopy;

    NSDictionary* userInfo = request.content.userInfo;
    NSDictionary* countlyPayload = userInfo[@"c"];
    NSString* timestamp = [NSString stringWithFormat:@"%llu", (long long)floor(NSDate.date.timeIntervalSince1970 * 1000)];

    NSArray* buttons = countlyPayload[@"b"];
    if(buttons && buttons.count)
    {
        NSLog(@"[NSE] custom action buttons found: %d", (int)buttons.count);

        NSMutableArray * actions = @[].mutableCopy;

        [buttons enumerateObjectsUsingBlock:^(NSDictionary* button, NSUInteger idx, BOOL * stop)
        {
            NSString* actionIdentifier = [NSString stringWithFormat:@"%@%lu", kCountlyActionIdentifier, (unsigned long)idx + 1];
            UNNotificationAction* action = [UNNotificationAction actionWithIdentifier:actionIdentifier title:button[@"t"] options:UNNotificationActionOptionForeground];
            [actions addObject:action];
        }];

        NSString* categoryIdentifier = [kCountlyCategoryIdentifier stringByAppendingString:timestamp];

        UNNotificationCategory* category = [UNNotificationCategory categoryWithIdentifier:categoryIdentifier actions:actions intentIdentifiers:@[] options:UNNotificationCategoryOptionNone];

        [UNUserNotificationCenter.currentNotificationCenter setNotificationCategories:[NSSet setWithObject:category]];

        bestAttemptContent.categoryIdentifier = categoryIdentifier;
    }

    NSString* attachment = countlyPayload[@"a"];
    if(attachment && attachment.length)
    {
        NSLog(@"[NSE] attachment found: %@", attachment);

        [[NSURLSession.sharedSession downloadTaskWithURL:[NSURL URLWithString:attachment] completionHandler:^(NSURL * location, NSURLResponse * response, NSError * error)
        {
            if(error)
            {
                NSLog(@"[NSE] attachment download error: %@", error);
            }
            else
            {
                NSLog(@"[NSE] attachment download completed!");

                NSString* attachmentFileName = [NSString stringWithFormat:@"%@-%@", timestamp, response.suggestedFilename? response.suggestedFilename:response.URL.absoluteString.lastPathComponent];

                NSString* tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:attachmentFileName];

                if(location && tempPath)
                    [NSFileManager.defaultManager moveItemAtPath:location.path toPath:tempPath error:&error];

                NSError* attachmentError = nil;
                UNNotificationAttachment* attachment = [UNNotificationAttachment attachmentWithIdentifier:attachmentFileName URL:[NSURL fileURLWithPath:tempPath] options:nil error:&attachmentError];

                if(attachment && !attachmentError)
                {
                    bestAttemptContent.attachments = @[attachment];

                    NSLog(@"[NSE] attachment added to notification!");
                }
                else
                {
                    NSLog(@"[NSE] attachment creation error: %@", attachmentError);
                }
            }

            contentHandler(bestAttemptContent);

            NSLog(@"[NSE] notification modification completed.");

        }] resume];
    }
    else
    {
        contentHandler(bestAttemptContent);

        NSLog(@"[NSE] notification modification completed.");
    }
}
#endif
@end
