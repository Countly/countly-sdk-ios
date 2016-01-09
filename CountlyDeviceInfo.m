// CountlyDeviceInfo.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyDeviceInfo

+ (NSString *)udid
{
#if COUNTLY_PREFER_IDFA && (TARGET_OS_IOS || TARGET_OS_WATCH)
    return ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString;
#else
	return [Countly_OpenUDID value];
#endif
}

+ (NSString *)device
{
#if TARGET_OS_IOS
    char *modelKey = "hw.machine";
#else
    char *modelKey = "hw.model";
#endif
    size_t size;
    sysctlbyname(modelKey, NULL, &size, NULL, 0);
    char *model = malloc(size);
    sysctlbyname(modelKey, model, &size, NULL, 0);
    NSString *modelString = @(model);
    free(model);
    return modelString;
}

+ (NSString *)osName
{
#if TARGET_OS_IOS
	return @"iOS";
#else
	return @"OS X";
#endif
}

+ (NSString *)osVersion
{
#if TARGET_OS_IOS
    return [[UIDevice currentDevice] systemVersion];
#else
    return [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"][@"ProductVersion"];
#endif
}

+ (NSString *)carrier
{
#if TARGET_OS_IOS
	if (NSClassFromString(@"CTTelephonyNetworkInfo"))
	{
		CTTelephonyNetworkInfo *netinfo = [CTTelephonyNetworkInfo new];
		CTCarrier *carrier = [netinfo subscriberCellularProvider];
		return [carrier carrierName];
	}
#endif
	return nil;
}

+ (NSString *)resolution
{
#if TARGET_OS_IOS
	CGRect bounds = UIScreen.mainScreen.bounds;
	CGFloat scale = [UIScreen.mainScreen respondsToSelector:@selector(scale)] ? [UIScreen.mainScreen scale] : 1.f;
    return [NSString stringWithFormat:@"%gx%g", bounds.size.width * scale, bounds.size.height * scale];
#else
    NSRect screenRect = NSScreen.mainScreen.frame;
    CGFloat scale = [NSScreen.mainScreen backingScaleFactor];
    return [NSString stringWithFormat:@"%gx%g", screenRect.size.width * scale, screenRect.size.height * scale];
#endif
}

+ (NSString *)locale
{
	return NSLocale.currentLocale.localeIdentifier;
}

+ (NSString *)appVersion
{
    NSString *result = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (result.length == 0)
        result = [NSBundle.mainBundle objectForInfoDictionaryKey:(NSString*)kCFBundleVersionKey];
    
    return result;
}

+ (NSString *)bundleId
{
    return NSBundle.mainBundle.bundleIdentifier;
}

+ (NSString *)metrics
{
    NSMutableDictionary* metricsDictionary = NSMutableDictionary.new;
	metricsDictionary[@"_device"] = CountlyDeviceInfo.device;
	metricsDictionary[@"_os"] = CountlyDeviceInfo.osName;
	metricsDictionary[@"_os_version"] = CountlyDeviceInfo.osVersion;
    
	NSString *carrier = CountlyDeviceInfo.carrier;
	if (carrier)
        metricsDictionary[@"_carrier"] = carrier;

	metricsDictionary[@"_resolution"] = CountlyDeviceInfo.resolution;
	metricsDictionary[@"_locale"] = CountlyDeviceInfo.locale;
	metricsDictionary[@"_app_version"] = CountlyDeviceInfo.appVersion;
	
	return [metricsDictionary JSONify];
}

#pragma mark -

+ (NSUInteger)connectionType
{
    typedef enum:NSInteger
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
            
            while(i != NULL)
            {
                if(i->ifa_addr->sa_family == AF_INET)
                {
                    if([[NSString stringWithUTF8String:i->ifa_name] isEqualToString:@"pdp_ip0"])
                    {
                        connType = CLYConnectionCellNetwork;

#if TARGET_OS_IOS

                        if (NSFoundationVersionNumber >= NSFoundationVersionNumber_iOS_7_0)
                        {
                            CTTelephonyNetworkInfo *tni = CTTelephonyNetworkInfo.new;
                        
                            if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyGPRS])
                            {
                                connType = CLYConnectionCellNetwork2G;
                            }
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyEdge])
                            {
                                connType = CLYConnectionCellNetwork2G;
                            }
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyWCDMA])
                            {
                                connType = CLYConnectionCellNetwork3G;
                            }
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyHSDPA])
                            {
                                connType = CLYConnectionCellNetwork3G;
                            }
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyHSUPA])
                            {
                                connType = CLYConnectionCellNetwork3G;
                            }
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyCDMA1x])
                            {
                                connType = CLYConnectionCellNetwork2G;
                            }
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0])
                            {
                                connType = CLYConnectionCellNetwork3G;
                            } 
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA])
                            {
                                connType = CLYConnectionCellNetwork3G;
                            } 
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB])
                            {
                                connType = CLYConnectionCellNetwork3G;
                            } 
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyeHRPD])
                            {
                                connType = CLYConnectionCellNetwork3G;
                            } 
                            else if ([tni.currentRadioAccessTechnology isEqualToString:CTRadioAccessTechnologyLTE])
                            {
                                connType = CLYConnectionCellNetworkLTE;
                            }
                        }
#endif
                    }
                    else if([[NSString stringWithUTF8String:i->ifa_name] isEqualToString:@"en0"])
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
    
    }

    return connType;
}

+ (unsigned long long)freeRAM
{
    vm_statistics_data_t vms;
    mach_msg_type_number_t ic = HOST_VM_INFO_COUNT;
    kern_return_t kr = host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&vms, &ic);
    if(kr != KERN_SUCCESS)
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
    return abs((int)(UIDevice.currentDevice.batteryLevel*100));
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


+ (float)OpenGLESversion
{
#if TARGET_OS_IOS
    EAGLContext *aContext;
    
    aContext = [EAGLContext.alloc initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if(aContext)
        return 3.0;
    
    aContext = [EAGLContext.alloc initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if(aContext)
        return 2.0;
    
    return 1.0;
#else
    return 1.0;
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