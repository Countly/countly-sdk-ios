// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyLocationManager : NSObject
@property (nonatomic, copy) NSString* location;
@property (nonatomic, copy) NSString* city;
@property (nonatomic, copy) NSString* ISOCountryCode;
@property (nonatomic, copy) NSString* IP;
@property (nonatomic) BOOL isLocationInfoDisabled;
+ (instancetype)sharedInstance;

- (void)sendLocationInfo;
- (void)recordLocationInfo:(CLLocationCoordinate2D)location city:(NSString *)city ISOCountryCode:(NSString *)ISOCountryCode andIP:(NSString *)IP;
- (void)disableLocationInfo;

@end
