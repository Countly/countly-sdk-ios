// CountlyDeviceInfo.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#import <mach-o/dyld.h>
#import <mach/mach_host.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#include <sys/types.h>
#include <sys/sysctl.h>

#if TARGET_OS_IOS
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#endif

NSString* const kCountlyZeroIDFA = @"00000000-0000-0000-0000-000000000000";

NSString* const kCountlyMetricKeyDevice             = @"_device";
NSString* const kCountlyMetricKeyOS                 = @"_os";
NSString* const kCountlyMetricKeyOSVersion          = @"_os_version";
NSString* const kCountlyMetricKeyAppVersion         = @"_app_version";
NSString* const kCountlyMetricKeyCarrier            = @"_carrier";
NSString* const kCountlyMetricKeyResolution         = @"_resolution";
NSString* const kCountlyMetricKeyDensity            = @"_density";
NSString* const kCountlyMetricKeyLocale             = @"_locale";
NSString* const kCountlyMetricKeyHasWatch           = @"_has_watch";
NSString* const kCountlyMetricKeyInstalledWatchApp  = @"_installed_watch_app";

#if TARGET_OS_IOS
@interface CountlyDeviceInfo ()
@property (nonatomic) CTTelephonyNetworkInfo* networkInfo;
@end
#endif

@implementation CountlyDeviceInfo

+ (instancetype)sharedInstance
{
    static CountlyDeviceInfo *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.deviceID = [CountlyPersistency.sharedInstance retrieveStoredDeviceID];
#if TARGET_OS_IOS
        //NOTE: Handle Limit Ad Tracking zero-IDFA problem
        if ([self.deviceID isEqualToString:kCountlyZeroIDFA])
            [self initializeDeviceID:CLYIDFV];

        self.networkInfo = CTTelephonyNetworkInfo.new;
#endif
    }

    return self;
}

- (void)initializeDeviceID:(NSString *)deviceID
{
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#if TARGET_OS_IOS
    if (!deviceID || !deviceID.length)
        self.deviceID = UIDevice.currentDevice.identifierForVendor.UUIDString;
    else if ([deviceID isEqualToString:CLYIDFV])
        self.deviceID = UIDevice.currentDevice.identifierForVendor.UUIDString;
    else if ([deviceID isEqualToString:CLYIDFA])
        self.deviceID = [self zeroSafeIDFA];
    else if ([deviceID isEqualToString:CLYOpenUDID])
        self.deviceID = [Countly_OpenUDID value];
    else
        self.deviceID = deviceID;

#elif TARGET_OS_WATCH
    if (!deviceID || !deviceID.length)
        self.deviceID = NSUUID.UUID.UUIDString;
    else
        self.deviceID = deviceID;

#elif TARGET_OS_TV
    if (!deviceID || !deviceID.length)
        self.deviceID = NSUUID.UUID.UUIDString;
    else
        self.deviceID = deviceID;

#elif TARGET_OS_OSX
    if (!deviceID || !deviceID.length)
        self.deviceID = NSUUID.UUID.UUIDString;
    else if ([deviceID isEqualToString:CLYOpenUDID])
        self.deviceID = [Countly_OpenUDID value];
    else
        self.deviceID = deviceID;
#else
    self.deviceID = @"UnsupportedPlaftormDevice";
#endif

#pragma GCC diagnostic pop

    [CountlyPersistency.sharedInstance storeDeviceID:self.deviceID];
}

- (NSString *)zeroSafeIDFA
{
#if TARGET_OS_IOS
#ifndef COUNTLY_EXCLUDE_IDFA
    NSString* IDFA = ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString;
#else
    NSString* IDFA = UIDevice.currentDevice.identifierForVendor.UUIDString;
#endif
    //NOTE: Handle Limit Ad Tracking zero-IDFA problem
    if ([IDFA isEqualToString:kCountlyZeroIDFA])
        IDFA = UIDevice.currentDevice.identifierForVendor.UUIDString;

    return IDFA;
#else
    return nil;
#endif
}

#pragma mark -

+ (NSString *)device
{
#if TARGET_OS_OSX
    char *modelKey = "hw.model";
#else
    char *modelKey = "hw.machine";
#endif
    size_t size;
    sysctlbyname(modelKey, NULL, &size, NULL, 0);
    char *model = malloc(size);
    sysctlbyname(modelKey, model, &size, NULL, 0);
    NSString *modelString = @(model);
    free(model);
    return modelString;
}

+ (NSString *)architecture
{
    NSString* architecture = nil;

#if TARGET_OS_IOS
    size_t size;
    cpu_type_t type;

    size = sizeof(type);
    sysctlbyname("hw.cputype", &type, &size, NULL, 0);

    if (type == CPU_TYPE_ARM64)
        architecture = @"arm64";
    else if (type == CPU_TYPE_ARM)
    {
        NSString* device = CountlyDeviceInfo.device;
        NSInteger modelNo = [[device substringFromIndex:device.length - 1] integerValue];
        if (([device hasPrefix:@"iPhone5,"] && modelNo >= 1 && modelNo <= 4)  ||
           ([device hasPrefix:@"iPad3,"]   && modelNo >= 4 && modelNo <= 6))
            architecture = @"armv7s";
        else
            architecture = @"armv7";
    }
#endif
    return architecture;
}

+ (NSString *)osName
{
#if TARGET_OS_IOS
    return @"iOS";
#elif TARGET_OS_WATCH
    return @"watchOS";
#elif TARGET_OS_TV
    return @"tvOS";
#else
    return @"macOS";
#endif
}

+ (NSString *)osVersion
{
#if TARGET_OS_IOS
    return UIDevice.currentDevice.systemVersion;
#elif TARGET_OS_WATCH
    return WKInterfaceDevice.currentDevice.systemVersion;
#elif TARGET_OS_TV
    return UIDevice.currentDevice.systemVersion;
#else
    return [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"][@"ProductVersion"];
#endif
}

+ (NSString *)carrier
{
#if TARGET_OS_IOS
    return CountlyDeviceInfo.sharedInstance.networkInfo.subscriberCellularProvider.carrierName;
#endif
    return nil;
}

+ (NSString *)resolution
{
#if TARGET_OS_IOS
    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat scale = UIScreen.mainScreen.scale;
#elif TARGET_OS_WATCH
    CGRect bounds = WKInterfaceDevice.currentDevice.screenBounds;
    CGFloat scale = WKInterfaceDevice.currentDevice.screenScale;
#elif TARGET_OS_TV
    CGRect bounds = (CGRect){0,0,1920,1080};
    CGFloat scale = 1.0;
#else
    NSRect bounds = NSScreen.mainScreen.frame;
    CGFloat scale = NSScreen.mainScreen.backingScaleFactor;
#endif
    return [NSString stringWithFormat:@"%gx%g", bounds.size.width * scale, bounds.size.height * scale];
}

+ (NSString *)density
{
#if TARGET_OS_IOS
    CGFloat scale = UIScreen.mainScreen.scale;
#elif TARGET_OS_WATCH
    CGFloat scale = WKInterfaceDevice.currentDevice.screenScale;
#elif TARGET_OS_TV
    CGFloat scale = 1.0;
#else
    CGFloat scale = NSScreen.mainScreen.backingScaleFactor;
#endif
    return [NSString stringWithFormat:@"@%dx", (int)scale];
}

+ (NSString *)locale
{
    return NSLocale.currentLocale.localeIdentifier;
}

+ (NSString *)appVersion
{
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}

+ (NSString *)appBuild
{
    return [NSBundle.mainBundle objectForInfoDictionaryKey:(NSString*)kCFBundleVersionKey];
}

#if TARGET_OS_IOS
+ (NSInteger)hasWatch
{
    if (@available(iOS 9.0, *))
        return (NSInteger)WCSession.defaultSession.paired;

    return 0;
}

+ (NSInteger)installedWatchApp
{
    if (@available(iOS 9.0, *))
        return (NSInteger)WCSession.defaultSession.watchAppInstalled;

    return 0;
}
#endif

+ (NSString *)metrics
{
    NSMutableDictionary* metricsDictionary = NSMutableDictionary.new;
    metricsDictionary[kCountlyMetricKeyDevice] = CountlyDeviceInfo.device;
    metricsDictionary[kCountlyMetricKeyOS] = CountlyDeviceInfo.osName;
    metricsDictionary[kCountlyMetricKeyOSVersion] = CountlyDeviceInfo.osVersion;
    metricsDictionary[kCountlyMetricKeyAppVersion] = CountlyDeviceInfo.appVersion;

    NSString *carrier = CountlyDeviceInfo.carrier;
    if (carrier)
        metricsDictionary[kCountlyMetricKeyCarrier] = carrier;

    metricsDictionary[kCountlyMetricKeyResolution] = CountlyDeviceInfo.resolution;
    metricsDictionary[kCountlyMetricKeyDensity] = CountlyDeviceInfo.density;
    metricsDictionary[kCountlyMetricKeyLocale] = CountlyDeviceInfo.locale;

#if TARGET_OS_IOS
    if (CountlyCommon.sharedInstance.enableAppleWatch)
    {
        if (CountlyConsentManager.sharedInstance.consentForAppleWatch)
        {
            metricsDictionary[kCountlyMetricKeyHasWatch] = @(CountlyDeviceInfo.hasWatch);
            metricsDictionary[kCountlyMetricKeyInstalledWatchApp] = @(CountlyDeviceInfo.installedWatchApp);
        }
    }
#endif

    return [metricsDictionary cly_JSONify];
}

#pragma mark -

+ (NSUInteger)connectionType
{
    typedef enum : NSInteger
    {
        CLYConnectionNone,
        CLYConnectionWiFi,
        CLYConnectionCellNetwork,
        CLYConnectionCellNetwork2G,
        CLYConnectionCellNetwork3G,
        CLYConnectionCellNetworkLTE
    } CLYConnectionType;

    CLYConnectionType connType = CLYConnectionNone;

    @try
    {
        struct ifaddrs *interfaces, *i;

        if (!getifaddrs(&interfaces))
        {
            i = interfaces;

            while (i != NULL)
            {
                if (i->ifa_addr->sa_family == AF_INET)
                {
                    if ([[NSString stringWithUTF8String:i->ifa_name] isEqualToString:@"pdp_ip0"])
                    {
                        connType = CLYConnectionCellNetwork;

#if TARGET_OS_IOS
                        NSDictionary* connectionTypes =
                        @{
                            CTRadioAccessTechnologyGPRS: @(CLYConnectionCellNetwork2G),
                            CTRadioAccessTechnologyEdge: @(CLYConnectionCellNetwork2G),
                            CTRadioAccessTechnologyCDMA1x: @(CLYConnectionCellNetwork2G),
                            CTRadioAccessTechnologyWCDMA: @(CLYConnectionCellNetwork3G),
                            CTRadioAccessTechnologyHSDPA: @(CLYConnectionCellNetwork3G),
                            CTRadioAccessTechnologyHSUPA: @(CLYConnectionCellNetwork3G),
                            CTRadioAccessTechnologyCDMAEVDORev0: @(CLYConnectionCellNetwork3G),
                            CTRadioAccessTechnologyCDMAEVDORevA: @(CLYConnectionCellNetwork3G),
                            CTRadioAccessTechnologyCDMAEVDORevB: @(CLYConnectionCellNetwork3G),
                            CTRadioAccessTechnologyeHRPD: @(CLYConnectionCellNetwork3G),
                            CTRadioAccessTechnologyLTE: @(CLYConnectionCellNetworkLTE)
                        };

                        NSString* radioAccessTech = CountlyDeviceInfo.sharedInstance.networkInfo.currentRadioAccessTechnology;
                        if (connectionTypes[radioAccessTech])
                            connType = [connectionTypes[radioAccessTech] integerValue];
#endif
                    }
                    else if ([[NSString stringWithUTF8String:i->ifa_name] isEqualToString:@"en0"])
                    {
                        connType = CLYConnectionWiFi;
                        break;
                    }
                }

                i = i->ifa_next;
            }
        }

        freeifaddrs(interfaces);
    }
    @catch (NSException *exception)
    {
        COUNTLY_LOG(@"Connection type can not be retrieved: \n%@", exception);
    }

    return connType;
}

+ (unsigned long long)freeRAM
{
    vm_statistics_data_t vms;
    mach_msg_type_number_t ic = HOST_VM_INFO_COUNT;
    kern_return_t kr = host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&vms, &ic);
    if (kr != KERN_SUCCESS)
        return -1;

    return vm_page_size * (vms.free_count);
}

+ (unsigned long long)totalRAM
{
    return NSProcessInfo.processInfo.physicalMemory;
}

+ (unsigned long long)freeDisk
{
    return [[NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil][NSFileSystemFreeSize] longLongValue];
}

+ (unsigned long long)totalDisk
{
    return [[NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil][NSFileSystemSize] longLongValue];
}

+ (NSInteger)batteryLevel
{
#if TARGET_OS_IOS
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    return abs((int)(UIDevice.currentDevice.batteryLevel * 100));
#else
    return 100;
#endif
}

+ (NSString *)orientation
{
#if TARGET_OS_IOS
    NSArray *orientations = @[@"Unknown", @"Portrait", @"PortraitUpsideDown", @"LandscapeLeft", @"LandscapeRight", @"FaceUp", @"FaceDown"];
    return orientations[UIDevice.currentDevice.orientation];
#else
    return @"Unknown";
#endif

}


+ (NSString *)OpenGLESversion
{
#if TARGET_OS_IOS
    EAGLContext *aContext;

    aContext = [EAGLContext.alloc initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (aContext)
        return @"3.0";

    aContext = [EAGLContext.alloc initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (aContext)
        return @"2.0";

    return @"1.0";
#else
    return @"1.0";
#endif
}


+ (BOOL)isJailbroken
{
    FILE *f = fopen("/bin/bash", "r");
    BOOL isJailbroken = (f != NULL);
    fclose(f);
    return isJailbroken;
}

+ (BOOL)isInBackground
{
#if TARGET_OS_IOS
    return UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
#else
    return NO;
#endif
}

@end
