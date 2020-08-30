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

- (void)recordLocation:(CLLocationCoordinate2D)location city:(NSString *)city ISOCountryCode:(NSString *)ISOCountryCode IP:(NSString *)IP
{
    if (!CountlyConsentManager.sharedInstance.consentForLocation)
        return;

    [self updateLocation:location city:city ISOCountryCode:ISOCountryCode IP:IP];

    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

- (void)updateLocation:(CLLocationCoordinate2D)location city:(NSString *)city ISOCountryCode:(NSString *)ISOCountryCode IP:(NSString *)IP
{
    if (CLLocationCoordinate2DIsValid(location))
        self.location = [NSString stringWithFormat:@"%f,%f", location.latitude, location.longitude];
    else
        self.location = nil;

    self.city = city.length ? city : nil;
    self.ISOCountryCode = ISOCountryCode.length ? ISOCountryCode : nil;
    self.IP = IP.length ? IP : nil;

    if (self.city && !self.ISOCountryCode)
    {
        COUNTLY_LOG(@"City and Country Code should be set as a pair. Country Code is missing while City is set!");
    }
    else if (self.ISOCountryCode && !self.city)
    {
        COUNTLY_LOG(@"City and Country Code should be set as a pair. City is missing while Country Code is set!");
    }

    if ((self.location || self.city || self.ISOCountryCode || self.IP))
        self.isLocationInfoDisabled = NO;
}

- (void)sendLocationInfo
{
    if (!CountlyConsentManager.sharedInstance.consentForLocation)
        return;

    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

- (void)disableLocationInfo
{
    if (!CountlyConsentManager.sharedInstance.consentForLocation)
        return;

    self.isLocationInfoDisabled = YES;

    self.location = nil;
    self.city = nil;
    self.ISOCountryCode = nil;
    self.IP = nil;

    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

@end
