// CountlyNotificationService.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

#if DEBUG
#define COUNTLY_EXT_LOG(fmt, ...) NSLog([@"%@ " stringByAppendingString:fmt], @"[CountlyNSE]", ##__VA_ARGS__)
#else
#define COUNTLY_EXT_LOG(...)
#endif

NSString* const kCountlyActionIdentifier = @"CountlyActionIdentifier";
NSString* const kCountlyCategoryIdentifier = @"CountlyCategoryIdentifier";

NSString* const kCountlyPNKeyCountlyPayload =        @"c";
NSString* const kCountlyPNKeyNotificationID =        @"i";
NSString* const kCountlyPNKeyButtons =               @"b";
NSString* const kCountlyPNKeyDefaultURL =            @"l";
NSString* const kCountlyPNKeyAttachment =            @"a";
NSString* const kCountlyPNKeyActionButtonIndex =     @"b";
NSString* const kCountlyPNKeyActionButtonTitle =     @"t";
NSString* const kCountlyPNKeyActionButtonURL =       @"l";

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
    COUNTLY_EXT_LOG(@"didReceiveNotificationRequest:withContentHandler:");

    NSDictionary* countlyPayload = request.content.userInfo[kCountlyPNKeyCountlyPayload];
    NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

    if (!notificationID)
    {
        COUNTLY_EXT_LOG(@"Countly payload not found in notification dictionary!");

        contentHandler(request.content);
        return;
    }

    COUNTLY_EXT_LOG(@"notification modification in progress...");

    UNMutableNotificationContent* bestAttemptContent = request.content.mutableCopy;

    NSArray* buttons = countlyPayload[kCountlyPNKeyButtons];
    if (buttons && buttons.count)
    {
        COUNTLY_EXT_LOG(@"custom action buttons found: %d", (int)buttons.count);

        NSMutableArray * actions = @[].mutableCopy;

        [buttons enumerateObjectsUsingBlock:^(NSDictionary* button, NSUInteger idx, BOOL * stop)
        {
            NSString* actionIdentifier = [NSString stringWithFormat:@"%@%lu", kCountlyActionIdentifier, (unsigned long)idx + 1];
            UNNotificationAction* action = [UNNotificationAction actionWithIdentifier:actionIdentifier title:button[kCountlyPNKeyActionButtonTitle] options:UNNotificationActionOptionForeground];
            [actions addObject:action];
        }];

        NSString* categoryIdentifier = [kCountlyCategoryIdentifier stringByAppendingString:notificationID];

        UNNotificationCategory* category = [UNNotificationCategory categoryWithIdentifier:categoryIdentifier actions:actions intentIdentifiers:@[] options:UNNotificationCategoryOptionNone];

        [UNUserNotificationCenter.currentNotificationCenter setNotificationCategories:[NSSet setWithObject:category]];

        bestAttemptContent.categoryIdentifier = categoryIdentifier;
    }

    NSString* attachment = countlyPayload[kCountlyPNKeyAttachment];
    if (attachment && attachment.length)
    {
        COUNTLY_EXT_LOG(@"attachment found: %@", attachment);

        [[NSURLSession.sharedSession downloadTaskWithURL:[NSURL URLWithString:attachment] completionHandler:^(NSURL * location, NSURLResponse * response, NSError * error)
        {
            if (error)
            {
                COUNTLY_EXT_LOG(@"attachment download error: %@", error);
            }
            else
            {
                COUNTLY_EXT_LOG(@"attachment download completed!");

                NSString* attachmentFileName = [NSString stringWithFormat:@"%@-%@", notificationID, response.suggestedFilename? response.suggestedFilename:response.URL.absoluteString.lastPathComponent];

                NSString* tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:attachmentFileName];

                if (location && tempPath)
                    [NSFileManager.defaultManager moveItemAtPath:location.path toPath:tempPath error:&error];

                NSError* attachmentError = nil;
                UNNotificationAttachment* attachment = [UNNotificationAttachment attachmentWithIdentifier:attachmentFileName URL:[NSURL fileURLWithPath:tempPath] options:nil error:&attachmentError];

                if (attachment && !attachmentError)
                {
                    bestAttemptContent.attachments = @[attachment];

                    COUNTLY_EXT_LOG(@"attachment added to notification!");
                }
                else
                {
                    COUNTLY_EXT_LOG(@"attachment creation error: %@", attachmentError);
                }
            }

            contentHandler(bestAttemptContent);

            COUNTLY_EXT_LOG(@"notification modification completed.");

        }] resume];
    }
    else
    {
        contentHandler(bestAttemptContent);

        COUNTLY_EXT_LOG(@"notification modification completed.");
    }
}
#endif
@end
