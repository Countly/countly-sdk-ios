// CountlyLocationManager.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"


@implementation CountlyLocationManager

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyLocationManager* s_sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {

    }

    return self;
}

#pragma mark ---

- (void)sendLocationInfo
{
    if (!CountlyConsentManager.sharedInstance.consentForLocation)
        return;

    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

- (void)recordLocationInfo:(CLLocationCoordinate2D)location city:(NSString *)city ISOCountryCode:(NSString *)ISOCountryCode andIP:(NSString *)IP
{
    if (!CountlyConsentManager.sharedInstance.consentForLocation)
        return;

    if (CLLocationCoordinate2DIsValid(location))
        self.location = [NSString stringWithFormat:@"%f,%f", location.latitude, location.longitude];
    else
        self.location = nil;

    self.city = city;
    self.ISOCountryCode = ISOCountryCode;
    self.IP = IP;

    if ((self.location || self.city || self.ISOCountryCode || self.IP))
        self.isLocationInfoDisabled = NO;

    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

- (void)disableLocationInfo
{
    if (!CountlyConsentManager.sharedInstance.consentForLocation)
        return;

    self.isLocationInfoDisabled = YES;

    //NOTE: Set location to empty string, as Countly Server needs it for disabling geo-location
    self.location = @"";
    self.city = nil;
    self.ISOCountryCode = nil;
    self.IP = nil;

    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

@end
