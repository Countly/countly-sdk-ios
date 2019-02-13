// CountlyConnectionManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

@interface CountlyConnectionManager : NSObject <NSURLSessionDelegate>

@property (nonatomic) NSString* appKey;
@property (nonatomic) NSString* host;
@property (nonatomic) NSURLSessionTask* connection;
@property (nonatomic) NSArray* pinnedCertificates;
@property (nonatomic) NSString* customHeaderFieldName;
@property (nonatomic) NSString* customHeaderFieldValue;
@property (nonatomic) NSString* secretSalt;
@property (nonatomic) BOOL alwaysUsePOST;
@property (nonatomic) BOOL applyZeroIDFAFix;

+ (instancetype)sharedInstance;

- (void)beginSession;
- (void)updateSession;
- (void)endSession;

- (void)sendEvents;
- (void)sendPushToken:(NSString *)token;
- (void)sendLocationInfo;
- (void)sendUserDetails:(NSString *)userDetails;
- (void)sendCrashReport:(NSString *)report immediately:(BOOL)immediately;
- (void)sendOldDeviceID:(NSString *)oldDeviceID;
- (void)sendParentDeviceID:(NSString *)parentDeviceID;
- (void)sendAttribution:(NSString *)attribution;
- (void)sendConsentChanges:(NSString *)consentChanges;

- (void)proceedOnQueue;

- (NSString *)queryEssentials;
- (NSString *)appendChecksum:(NSString *)queryString;

@end
