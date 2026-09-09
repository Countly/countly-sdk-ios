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
    CLY_LOG_I(@"%s location recording requested, coordinateProvided: [%@], cityProvided: [%@], countryCodeProvided: [%@], IPProvided: [%@]", __FUNCTION__, CLLocationCoordinate2DIsValid(location) ? @"YES" : @"NO", (city.length > 0) ? @"YES" : @"NO", (ISOCountryCode.length > 0) ? @"YES" : @"NO", (IP.length > 0) ? @"YES" : @"NO");
    CLY_LOG_D(@"%s location recording detail, latitude: [%f], longitude: [%f], city: [%@], countryCode: [%@], IP: [%@]", __FUNCTION__, location.latitude, location.longitude, city, ISOCountryCode, IP);

    if (!CountlyConsentManager.sharedInstance.consentForLocation)
    {
        CLY_LOG_V(@"%s no location consent given, location is not recorded", __FUNCTION__);
        return;
    }

    if(!CountlyServerConfig.sharedInstance.locationTrackingEnabled)
    {
        CLY_LOG_D(@"%s location recording is dropped, location tracking is disabled by server config", __FUNCTION__);
        return;
    }
    
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

    CLY_LOG_D(@"%s stored location fields updated, providedFields: [%@%@%@%@]", __FUNCTION__, self.location ? @"coordinate " : @"", self.city ? @"city " : @"", self.ISOCountryCode ? @"countryCode " : @"", self.IP ? @"IP" : @"");
    CLY_LOG_D(@"%s stored location field detail, location: [%@], city: [%@], countryCode: [%@], IP: [%@]", __FUNCTION__, self.location, self.city, self.ISOCountryCode, self.IP);

    if (self.city && !self.ISOCountryCode)
    {
        CLY_LOG_W(@"%s city and country code should be set as a pair, country code is missing while city is set", __FUNCTION__);
    }
    else if (self.ISOCountryCode && !self.city)
    {
        CLY_LOG_W(@"%s city and country code should be set as a pair, city is missing while country code is set", __FUNCTION__);
    }

    if ((self.location || self.city || self.ISOCountryCode || self.IP))
        self.isLocationInfoDisabled = NO;
}

- (void)sendLocationInfo
{
    CLY_LOG_I(@"%s stored location info send requested, locationInfoDisabled: [%@]", __FUNCTION__, self.isLocationInfoDisabled ? @"YES" : @"NO");

    if (!CountlyConsentManager.sharedInstance.consentForLocation)
    {
        CLY_LOG_V(@"%s no location consent given, stored location info is not sent", __FUNCTION__);
        return;
    }
    
    if(!CountlyServerConfig.sharedInstance.locationTrackingEnabled)
    {
        CLY_LOG_D(@"%s stored location info send is dropped, location tracking is disabled by server config", __FUNCTION__);
        return;
    }

    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

- (void)disableLocationInfo
{
    CLY_LOG_I(@"%s location clearing requested", __FUNCTION__);

    if (!CountlyConsentManager.sharedInstance.consentForLocation)
    {
        CLY_LOG_V(@"%s no location consent given, location info is not cleared", __FUNCTION__);
        return;
    }

    [self disableLocation];
    CLY_LOG_I(@"%s location info is cleared and location tracking is disabled for this device", __FUNCTION__);

    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

- (void)disableLocation
{
    CLY_LOG_D(@"%s clearing all stored location fields, clearedFields: [%@]", __FUNCTION__, @"coordinate city countryCode IP");

    self.isLocationInfoDisabled = YES;
    self.location = nil;
    self.city = nil;
    self.ISOCountryCode = nil;
    self.IP = nil;
}

@end
