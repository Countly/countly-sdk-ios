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
- (void)updateLocation:(CLLocationCoordinate2D)location city:(NSString *)city ISOCountryCode:(NSString *)ISOCountryCode IP:(NSString *)IP;
- (void)recordLocation:(CLLocationCoordinate2D)location city:(NSString *)city ISOCountryCode:(NSString *)ISOCountryCode IP:(NSString *)IP;
- (void)disableLocationInfo;

@end
