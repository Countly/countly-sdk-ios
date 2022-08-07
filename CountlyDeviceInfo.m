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

#if (TARGET_OS_IOS)
#if (!TARGET_OS_MACCATALYST)
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#endif
#elif (TARGET_OS_OSX)
#import <IOKit/ps/IOPowerSources.h>
#endif

CLYMetricKey const CLYMetricKeyDevice             = @"_device";
CLYMetricKey const CLYMetricKeyDeviceType         = @"_device_type";
CLYMetricKey const CLYMetricKeyOS                 = @"_os";
CLYMetricKey const CLYMetricKeyOSVersion          = @"_os_version";
CLYMetricKey const CLYMetricKeyAppVersion         = @"_app_version";
CLYMetricKey const CLYMetricKeyCarrier            = @"_carrier";
CLYMetricKey const CLYMetricKeyResolution         = @"_resolution";
CLYMetricKey const CLYMetricKeyDensity            = @"_density";
CLYMetricKey const CLYMetricKeyLocale             = @"_locale";
CLYMetricKey const CLYMetricKeyHasWatch           = @"_has_watch";
CLYMetricKey const CLYMetricKeyInstalledWatchApp  = @"_installed_watch_app";

@interface CountlyDeviceInfo ()
@property (nonatomic) BOOL isInBackground;
#if (TARGET_OS_IOS)
#if (!TARGET_OS_MACCATALYST)
@property (nonatomic) CTTelephonyNetworkInfo* networkInfo;
#endif
#endif
@end

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
        self.deviceID = [CountlyPersistency.sharedInstance retrieveDeviceID];
#if (TARGET_OS_IOS)
#if (!TARGET_OS_MACCATALYST)
        self.networkInfo = CTTelephonyNetworkInfo.new;
#endif
#endif

#if (TARGET_OS_IOS || TARGET_OS_TV)
        self.isInBackground = (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground);

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationDidEnterBackground:)
                                                   name:UIApplicationDidEnterBackgroundNotification
                                                 object:nil];

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillEnterForeground:)
                                                   name:UIApplicationWillEnterForegroundNotification
                                                 object:nil];
#endif
    }

    return self;
}

//NOTE: Using this flag instead of a direct call to UIApplication's applicationState method
//      in order to avoid making a UI call on a non-main thread at the moment of a crash.
- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    self.isInBackground = YES;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    self.isInBackground = NO;
}

- (void)initializeDeviceID:(NSString *)deviceID
{
    self.deviceID = [self ensafeDeviceID:deviceID];

    [CountlyPersistency.sharedInstance storeDeviceID:self.deviceID];
}

- (NSString *)ensafeDeviceID:(NSString *)deviceID
{
    if (deviceID.length)
        return deviceID;

#if (TARGET_OS_IOS || TARGET_OS_TV)
    return UIDevice.currentDevice.identifierForVendor.UUIDString;
#else
    NSString* UUID = [CountlyPersistency.sharedInstance retrieveNSUUID];
    if (!UUID)
    {
        UUID = NSUUID.UUID.UUIDString;
        [CountlyPersistency.sharedInstance storeNSUUID:UUID];
    }

    return UUID;
#endif
}

- (BOOL)isDeviceIDTemporary
{
    return [self.deviceID isEqualToString:CLYTemporaryDeviceID];
}

- (CLYDeviceIDTypeValue)deviceIDTypeValue
{
    CLYDeviceIDType deviceIDType = Countly.sharedInstance.deviceIDType;

    if ([deviceIDType isEqual:CLYDeviceIDTypeCustom])
        return CLYDeviceIDTypeValueCustom;

    if ([deviceIDType isEqual:CLYDeviceIDTypeIDFV])
        return CLYDeviceIDTypeValueIDFV;

    if ([deviceIDType isEqual:CLYDeviceIDTypeNSUUID])
        return CLYDeviceIDTypeValueNSUUID;

    if ([deviceIDType isEqual:CLYDeviceIDTypeTemporary])
        return CLYDeviceIDTypeValueTemporary;

    CLY_LOG_E(@"Device ID type is not one of the defined types.");

    return (CLYDeviceIDTypeValue)-1;
}

#pragma mark -

+ (NSString *)device
{
#if (TARGET_OS_OSX)
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

+ (NSString *)deviceType
{
#if (TARGET_OS_IOS)
#if (TARGET_OS_MACCATALYST)
    return @"desktop";
#else
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
        return @"tablet";

    return @"mobile";
#endif
#elif (TARGET_OS_WATCH)
    return @"wearable";
#elif (TARGET_OS_TV)
    return @"smarttv";
#elif (TARGET_OS_OSX)
    return @"desktop";
#endif

    return nil;
}

+ (NSString *)architecture
{
    cpu_type_t type;
    size_t size = sizeof(type);
    sysctlbyname("hw.cputype", &type, &size, NULL, 0);

    if (type == CPU_TYPE_ARM64)
        return @"arm64";

    if (type == CPU_TYPE_ARM)
        return @"armv7";

    if (type == CPU_TYPE_ARM64_32)
        return @"arm64_32";

    if (type == CPU_TYPE_X86)
        return @"x86_64";

    return nil;
}

+ (NSString *)osName
{
#if (TARGET_OS_IOS)
    return @"iOS";
#elif (TARGET_OS_WATCH)
    return @"watchOS";
#elif (TARGET_OS_TV)
    return @"tvOS";
#elif (TARGET_OS_OSX)
    return @"macOS";
#endif

    return nil;
}

+ (NSString *)osVersion
{
#if (TARGET_OS_IOS || TARGET_OS_TV)
    return UIDevice.currentDevice.systemVersion;
#elif (TARGET_OS_WATCH)
    return WKInterfaceDevice.currentDevice.systemVersion;
#elif (TARGET_OS_OSX)
    return [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"][@"ProductVersion"];
#endif

    return nil;
}

+ (NSString *)carrier
{
#if (TARGET_OS_IOS)
#if (!TARGET_OS_MACCATALYST)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return CountlyDeviceInfo.sharedInstance.networkInfo.subscriberCellularProvider.carrierName;
#pragma GCC diagnostic pop
#endif
#endif
    //NOTE: it is not possible to get carrier info on Apple Watches as CoreTelephony is not available.
    return nil;
}

+ (NSString *)resolution
{
#if (TARGET_OS_IOS || TARGET_OS_TV)
    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat scale = UIScreen.mainScreen.scale;
#elif (TARGET_OS_WATCH)
    CGRect bounds = WKInterfaceDevice.currentDevice.screenBounds;
    CGFloat scale = WKInterfaceDevice.currentDevice.screenScale;
#elif (TARGET_OS_OSX)
    NSRect bounds = NSScreen.mainScreen.frame;
    CGFloat scale = NSScreen.mainScreen.backingScaleFactor;
#else
    return nil;
#endif

    return [NSString stringWithFormat:@"%gx%g", bounds.size.width * scale, bounds.size.height * scale];
}

+ (NSString *)density
{
#if (TARGET_OS_IOS || TARGET_OS_TV)
    CGFloat scale = UIScreen.mainScreen.scale;
#elif (TARGET_OS_WATCH)
    CGFloat scale = WKInterfaceDevice.currentDevice.screenScale;
#elif (TARGET_OS_OSX)
    CGFloat scale = NSScreen.mainScreen.backingScaleFactor;
#else
    return nil;
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

+ (NSString *)metrics
{
    NSMutableDictionary* metricsDictionary = NSMutableDictionary.new;
    metricsDictionary[CLYMetricKeyDevice] = CountlyDeviceInfo.device;
    metricsDictionary[CLYMetricKeyDeviceType] = CountlyDeviceInfo.deviceType;
    metricsDictionary[CLYMetricKeyOS] = CountlyDeviceInfo.osName;
    metricsDictionary[CLYMetricKeyOSVersion] = CountlyDeviceInfo.osVersion;
    metricsDictionary[CLYMetricKeyAppVersion] = CountlyDeviceInfo.appVersion;

    NSString *carrier = CountlyDeviceInfo.carrier;
    if (carrier)
        metricsDictionary[CLYMetricKeyCarrier] = carrier;

    metricsDictionary[CLYMetricKeyResolution] = CountlyDeviceInfo.resolution;
    metricsDictionary[CLYMetricKeyDensity] = CountlyDeviceInfo.density;
    metricsDictionary[CLYMetricKeyLocale] = CountlyDeviceInfo.locale;

    [metricsDictionary addEntriesFromDictionary:CountlyDeviceInfo.sharedInstance.customMetrics];

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
        CLY_LOG_W(@"Connection type can not be retrieved: \n%@", exception);
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
     NSDictionary *homeDirectory = [NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    return [homeDirectory[NSFileSystemFreeSize] longLongValue];
}

+ (unsigned long long)totalDisk
{
    NSDictionary *homeDirectory = [NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    return [homeDirectory[NSFileSystemSize] longLongValue];
}

+ (NSInteger)batteryLevel
{
#if (TARGET_OS_IOS)
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    return abs((int)(UIDevice.currentDevice.batteryLevel * 100));
#elif (TARGET_OS_WATCH)
    return abs((int)(WKInterfaceDevice.currentDevice.batteryLevel * 100));
#elif (TARGET_OS_OSX)
    CFTypeRef sourcesInfo = IOPSCopyPowerSourcesInfo();
    NSArray *sources = (__bridge NSArray*)IOPSCopyPowerSourcesList(sourcesInfo);
    NSDictionary *source = sources.firstObject;
    if (!source)
        return 100;

    NSInteger currentLevel = ((NSNumber *)(source[@kIOPSCurrentCapacityKey])).integerValue;
    NSInteger maxLevel = ((NSNumber *)(source[@kIOPSMaxCapacityKey])).integerValue;
    return (currentLevel / (float)maxLevel) * 100;
#endif

    return 100;
}

+ (NSString *)orientation
{
#if (TARGET_OS_IOS)
    NSArray *orientations = @[@"Unknown", @"Portrait", @"PortraitUpsideDown", @"LandscapeLeft", @"LandscapeRight", @"FaceUp", @"FaceDown"];
    UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    if (orientation >= 0 && orientation < orientations.count)
        return orientations[orientation];
#elif (TARGET_OS_WATCH)
    NSArray *orientations = @[@"CrownLeft", @"CrownRight"];
    WKInterfaceDeviceCrownOrientation orientation = WKInterfaceDevice.currentDevice.crownOrientation;
    if (orientation >= 0 && orientation < orientations.count)
        return orientations[orientation];
#endif

    return nil;
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
    return CountlyDeviceInfo.sharedInstance.isInBackground;
}

@end
