// CountlyCommon.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#include <CommonCrypto/CommonDigest.h>
#include <stdatomic.h>

NSString* const kCountlyReservedEventOrientation = @"[CLY]_orientation";
NSString* const kCountlyOrientationKeyMode = @"mode";

NSString* const kCountlyVisibility = @"cly_v";

NSString* const kCountlyQSSdkLogsMessage = @"m";
NSString* const kCountlyQSSdkLogsLevel = @"l";
NSString* const kCountlyQSSDKLogsTimestamp = @"t";
NSString* const kCountlyQSSDKLogsGatherId = @"i";
NSString* const kCountlyQSSDKLogsDropCount = @"d";
NSString* const kCountlyQSSDKLogsBatchLines = @"l";

// undecided is the state the SDK starts in: it gathers on the chance that a directive will adopt the
// lines, which is the only way the init logs can ever be delivered
typedef NS_ENUM(NSInteger, CLYSDKLogsState)
{
    CLYSDKLogsStateUndecided = 0,
    CLYSDKLogsStateGathering,
    CLYSDKLogsStateOff,
};

static const NSInteger kCountlySDKLogsMaxMessageLength = 4096;
// How many lines are held at most, and so also the largest batch the server may ask for: a batch
// bigger than the buffer would never fill, and the SDK would drop lines forever without flushing.
// The buffer only reaches this while nothing is decided yet, since every captured line drains a
// whole batch once gathering is on. It is also what the ingestor takes in one upload
static const NSInteger kCountlySDKLogsMaxBufferedLines = 500;
static const NSInteger kCountlySDKLogsDefaultBatchSize = 100;
// a batch of one or two would upload a request per log line, and the lines the upload itself logs
// would keep it going. The server clamps to this too, nothing else stops a malformed directive
static const NSInteger kCountlySDKLogsMinBatchSize = 10;
// second ceiling, on the characters held: a line may be 4096 long, so a line count alone does not bound memory
static const NSInteger kCountlySDKLogsCharCeiling = 128 * 1024;
// long lines reach the character ceiling before a batch fills, so from here the buffer goes out as a partial batch
static const NSInteger kCountlySDKLogsDeliveryCharThreshold = kCountlySDKLogsCharCeiling * 3 / 4;
static NSString* const kCountlySDKLogsAllLevels = @"ewidv";
// gathering the log line that carries a batch would nest each batch inside the next one
static NSString* const kCountlySDKLogsTransportMarker = @"sdk_logs";
// the consent getter a line needs, NSNull for a line that needs both events and user details. Never part of an uploaded line
static NSString* const kCountlySDKLogsAwaitedConsent = @"consent";
// the characters of kCountlySDKLogsAllLevels, in its order, which indexes the drops counted while undecided
static const char kCountlySDKLogsLevelChars[] = "ewidv";
// a thread local and not the thread dictionary, since every captured line reads it
static __thread BOOL s_isSdkLogsTransportWork = NO;
static atomic_bool s_isSdkLogCaptureStoppedForCrash = false;
// set by halt until the next start, so what the app logs between a logout and the next user's start is not gathered for that user
static atomic_bool s_isSdkLogCapturePausedUntilStart = false;

@interface CountlyCommon ()
{
    NSCalendar* gregorianCalendar;
    NSTimeInterval startTime;
    // lines dropped while undecided, per level: only the levels the adopted directive asks for become part of 'd'
    NSInteger sdkLogsUndecidedDrops[sizeof(kCountlySDKLogsLevelChars) - 1];
}
@property long long lastTimestamp;

#if (TARGET_OS_IOS || TARGET_OS_VISION )
@property (nonatomic) NSString* lastInterfaceOrientation;
#endif

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV )
@property (nonatomic) UIBackgroundTaskIdentifier bgTask;
#endif

@property (nonatomic) NSMutableArray* sdkLogs;
// atomic: read on every log call without the lock, written under it
@property (atomic) CLYSDKLogsState sdkLogsState;
@property (nonatomic) NSInteger sdkLogsBatchSize;
@property (nonatomic) NSString *sdkLogsLevels;
// the bits of sdkLogsLevels, kept by its setter. Atomic: log calls read it without the lock to skip unwanted levels
@property (atomic) NSUInteger sdkLogsLevelMask;
@property (nonatomic) NSString *sdkLogsGatheringId;
@property (nonatomic) NSInteger sdkLogsDropCount;
@property (nonatomic) NSInteger sdkLogsChars;
// lines whose feature has no consent yet, kept apart from the buffer so they can never be uploaded before it is given
@property (nonatomic) NSMutableArray* sdkLogsAwaitingConsent;
@property (nonatomic) NSInteger sdkLogsAwaitingConsentChars;
// a lock of its own rather than the array, so every piece of gathering state shares one monitor
@property (nonatomic) NSObject* sdkLogsLock;
// batch-full deliveries run here and never on the capturing thread, which may be inside a persistency lock
@property (nonatomic) dispatch_queue_t sdkLogsDeliveryQueue;
// set while a delivery waits for the request queue to send the log batch it holds, so it waits once
@property (nonatomic) BOOL sdkLogsDeliveryAwaitsQueueDrain;
@property (nonatomic) NSURLSession* pinnedImmediateURLSession;
@end

/// The level character a gathered line carries for a log level.
static char CountlySDKLogsLevelChar(CLYInternalLogLevel level)
{
    static const char levelChars[] = {'n', 'e', 'w', 'i', 'd', 'v'};
    return level < sizeof(levelChars) ? levelChars[level] : 'n';
}

/// The bit of a level character in the gathered level mask, 0 for a character outside kCountlySDKLogsAllLevels.
static NSUInteger CountlySDKLogsLevelBit(char levelChar)
{
    const char* found = levelChar ? strchr(kCountlySDKLogsLevelChars, levelChar) : NULL;
    return found ? (NSUInteger)1 << (found - kCountlySDKLogsLevelChars) : 0;
}

/// The level mask of a level string.
static NSUInteger CountlySDKLogsLevelMask(NSString* levels)
{
    NSUInteger mask = 0;
    for (NSUInteger i = 0; i < levels.length; i++)
        mask |= CountlySDKLogsLevelBit((char)[levels characterAtIndex:i]);

    return mask;
}

NSString* const kCountlySDKVersion = @"26.8.0";
NSString* const kCountlySDKName = @"objc-native-ios";

NSString* const kCountlyErrorDomain = @"ly.count.ErrorDomain";

NSString* const kCountlyInternalLogPrefix = @"[Countly] ";


@implementation CountlyCommon

@synthesize lastTimestamp;

static CountlyCommon *s_sharedInstance = nil;
static dispatch_once_t onceToken;
+ (instancetype)sharedInstance
{
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        gregorianCalendar = [NSCalendar.alloc initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        startTime = NSDate.date.timeIntervalSince1970;
        
        self.lastTimestamp = 0;
        self.SDKVersion = kCountlySDKVersion;
        self.SDKName = kCountlySDKName;
        
        self.sdkLogs = NSMutableArray.new;
        self.sdkLogsAwaitingConsent = NSMutableArray.new;
        self.sdkLogsState = atomic_load(&s_isSdkLogCapturePausedUntilStart) ? CLYSDKLogsStateOff : CLYSDKLogsStateUndecided;
        self.sdkLogsBatchSize = kCountlySDKLogsDefaultBatchSize;
        self.sdkLogsLevels = kCountlySDKLogsAllLevels;
        self.sdkLogsGatheringId = @"";
        self.sdkLogsLock = NSObject.new;
        self.sdkLogsDeliveryQueue = dispatch_queue_create("ly.count.sdklogs.delivery", DISPATCH_QUEUE_SERIAL);
    }

    return self;
}

- (void)resetInstance {
    CLY_LOG_I(@"%s resetting shared state, sdkVersion: [%@], sdkName: [%@]", __FUNCTION__, kCountlySDKVersion, kCountlySDKName);
#if (TARGET_OS_IOS)
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
#endif
    _hasStarted = false;
    _hasFinishedInit       = false;
    // `startWithConfig:` only ever sets this flag to YES, so without clearing it here it
    // would survive a `halt:` and leak visibility segmentation into the next start.
    _enableVisibiltyTracking = NO;
    _maxKeyLength = kCountlyMaxKeyLength;
    _maxValueLength = kCountlyMaxValueSize;
    _maxValueLengthPicture = kCountlyMaxValueSizePicture;
    _maxSegmentationValues = kCountlyMaxSegmentationValues;
    //under the lock like every other write to it: a reset races the log lines that other threads are
    //still capturing, and mutating the array from two threads at once crashes
    atomic_store(&s_isSdkLogCapturePausedUntilStart, true);
    @synchronized (_sdkLogsLock) {
        [self setLogGatheringOffLocked];
    }
    [self invalidatePinnedImmediateURLSession];
    onceToken = 0;
    s_sharedInstance = nil;
 }

- (void)resumeSdkLogCaptureForStart
{
    if (!atomic_exchange(&s_isSdkLogCapturePausedUntilStart, false))
        return;

    @synchronized (_sdkLogsLock) {
        if (_sdkLogsState == CLYSDKLogsStateOff)
            _sdkLogsState = CLYSDKLogsStateUndecided;
    }
}


- (BOOL)hasStarted
{
    if (!_hasStarted)
        CountlyPrint(@"SDK should be started first!");

    return _hasStarted;
}

//NOTE: This is an equivalent of hasStarted, but without internal logging.
- (BOOL)hasStarted_
{
    return _hasStarted;
}

BOOL CountlyInternalLogIsEnabled(CLYInternalLogLevel level)
{
    CountlyCommon* common = CountlyCommon.sharedInstance;
    if (!common.enableDebug && !common.loggerDelegate)
        return NO;

    return level <= common.internalLogLevel;
}

BOOL CountlyInternalLogIsWanted(CLYInternalLogLevel level)
{
    return CountlyInternalLogIsEnabled(level) || [CountlyCommon.sharedInstance isCapturingSdkLogLevel:level];
}

void CountlyInternalLog(CLYInternalLogLevel level, NSString *format, ...)
{
    if (level == CLYInternalLogLevelError) {
        [CountlyHealthTracker.sharedInstance logError];
    } else if(level == CLYInternalLogLevelWarning) {
        [CountlyHealthTracker.sharedInstance logWarning];
    }

    CountlyCommon* common = CountlyCommon.sharedInstance;
    // gathering has to work while console logging is off, but when nothing wants the line it must not be formatted at all
    BOOL wantsConsole = CountlyInternalLogIsEnabled(level);
    BOOL wantsCapture = [common isCapturingSdkLogLevel:level];
    if (!wantsConsole && !wantsCapture)
        return;

    va_list args;
    va_start(args, format);
    NSString* logString = [NSString.alloc initWithFormat:format arguments:args];
    va_end(args);

    // before the level prefix is added: a gathered line carries its level in its own field, and the
    // dashboard renders that, so a prefix here would only be the same level a second time
    if (wantsCapture)
        [common captureSdkLogLine:logString level:CountlySDKLogsLevelChar(level)];

    if (!wantsConsole)
        return;

    NSArray<NSString *> *logLevelPrefixes =
    @[
        @"None",
        @"Error",
        @"Warning",
        @"Info",
        @"Debug",
        @"Verbose",
    ];

    logString = [NSString stringWithFormat:@"[%@] %@", logLevelPrefixes[level], logString];

#if DEBUG
    if (common.enableDebug)
        CountlyPrint(logString);
#endif

    if ([common.loggerDelegate respondsToSelector:@selector(internalLog:withLevel:)])
    {
        NSString* logStringWithPrefix = [NSString stringWithFormat:@"%@%@", kCountlyInternalLogPrefix, logString];
        [common.loggerDelegate internalLog:logStringWithPrefix withLevel:level];
    }
}

- (BOOL)isCapturingSdkLogs
{
    return self.sdkLogsState != CLYSDKLogsStateOff && !atomic_load(&s_isSdkLogCaptureStoppedForCrash);
}

void CountlySDKLogsStopCaptureForCrash(void)
{
    atomic_store(&s_isSdkLogCaptureStoppedForCrash, true);
}

- (BOOL)isCapturingSdkLogLevel:(CLYInternalLogLevel)level
{
    return self.isCapturingSdkLogs && (self.sdkLogsLevelMask & CountlySDKLogsLevelBit(CountlySDKLogsLevelChar(level))) != 0;
}

/// Sets the gathered levels and the mask that log calls read without taking the lock.
- (void)setSdkLogsLevels:(NSString *)sdkLogsLevels
{
    _sdkLogsLevels = sdkLogsLevels;
    self.sdkLogsLevelMask = CountlySDKLogsLevelMask(sdkLogsLevels);
}

/// The CountlyConsentManager getter a gathered line needs, keyed by the class that writes it, or by "Class selector" where one class serves several features.
static NSDictionary<NSString *, NSString *>* CountlySDKLogsConsentByOwner(void)
{
    static NSDictionary* consentByOwner;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString* sessions = NSStringFromSelector(@selector(consentForSessions));
        NSString* events = NSStringFromSelector(@selector(consentForEvents));
        NSString* users = NSStringFromSelector(@selector(consentForUserDetails));
        NSString* crashes = NSStringFromSelector(@selector(consentForCrashReporting));
        NSString* push = NSStringFromSelector(@selector(consentForPushNotifications));
        NSString* location = NSStringFromSelector(@selector(consentForLocation));
        NSString* views = NSStringFromSelector(@selector(consentForViewTracking));
        NSString* attribution = NSStringFromSelector(@selector(consentForAttribution));
        NSString* apm = NSStringFromSelector(@selector(consentForPerformanceMonitoring));
        NSString* feedback = NSStringFromSelector(@selector(consentForFeedback));
        NSString* remoteConfig = NSStringFromSelector(@selector(consentForRemoteConfig));
        NSString* content = NSStringFromSelector(@selector(consentForContent));
        NSString* metrics = NSStringFromSelector(@selector(consentForMetrics));

        consentByOwner = @{
            @"CountlyViewTracking": views,
            @"CountlyViewTrackingInternal": views,
            @"CountlyViewData": views,
            @"CountlyUserDetails": users,
            @"CountlyCrashReporter": crashes,
            @"CountlyCrashData": crashes,
            @"CountlyExceptionHandler": crashes,
            @"CountlyPushNotifications": push,
            @"CountlyLocationManager": location,
            @"CountlyPerformanceMonitoring": apm,
            @"CountlyFeedbacks": feedback,
            @"CountlyFeedbacksInternal": feedback,
            @"CountlyFeedbackWidget": feedback,
            @"CountlyRemoteConfig": remoteConfig,
            @"CountlyRemoteConfigInternal": remoteConfig,
            @"CountlyRCData": remoteConfig,
            @"CountlyExperimentInformation": remoteConfig,
            @"CountlyContentBuilder": content,
            @"CountlyContentBuilderInternal": content,

            @"Countly recordEvent": events,
            @"Countly recordReservedEvent": events,
            @"Countly isReservedEvent": events,
            @"Countly processSegmentation": events,
            @"Countly journeyTriggerCallback": events,
            @"Countly startEvent": events,
            @"Countly endEvent": events,
            @"Countly cancelEvent": events,
            @"Countly beginSession": sessions,
            @"Countly updateSession": sessions,
            @"Countly endSession": sessions,
            @"Countly recordMetrics": metrics,
            @"Countly askForNotificationPermission": push,
            @"Countly askForNotificationPermissionWithOptions": push,
            @"Countly recordActionForNotification": push,
            @"Countly recordPushNotificationToken": push,
            @"Countly clearPushNotificationToken": push,
            @"Countly recordLocation": location,
            @"Countly disableLocationInfo": location,
            @"Countly recordException": crashes,
            @"Countly recordError": crashes,
            @"Countly recordCrashLog": crashes,
            @"Countly clearCrashLogs": crashes,
            @"Countly crashLog": crashes,
            @"Countly askForStarRating": feedback,
            @"Countly presentRatingWidgetWithID": feedback,
            @"Countly recordRatingWidgetWithID": feedback,
            @"Countly recordDirectAttributionWithCampaignType": attribution,
            @"Countly recordIndirectAttribution": attribution,
            @"Countly recordNetworkTrace": apm,
            @"Countly startCustomTrace": apm,
            @"Countly endCustomTrace": apm,
            @"Countly cancelCustomTrace": apm,
            @"Countly clearAllCustomTraces": apm,
            @"Countly appLoadingFinished": apm,
        };
    });

    return consentByOwner;
}

/// Whether a character can be part of a class or selector name in __FUNCTION__.
static BOOL CountlySDKLogsIsNameCharacter(unichar character)
{
    return (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || character == '_';
}

/// The consent getter a gathered line needs, or nil for a line no single feature owns, such as a queued request or a stored state.
/// Every line opens with __FUNCTION__ ("-[Class selector]", "+[Class selector]", "-[Class(Category) selector]", "__12-[Class selector]_block_invoke"
/// in a block, or the bare name of a C function) or with "[Class]".
static NSString* CountlySDKLogsConsentForLine(NSString* line)
{
    // a character scan rather than a regular expression, since this runs for every captured line
    unichar prefix[128];
    NSUInteger length = MIN(line.length, sizeof(prefix) / sizeof(prefix[0]));
    [line getCharacters:prefix range:NSMakeRange(0, length)];

    NSUInteger index = 0;
    if (length > 2 && prefix[0] == '_' && prefix[1] == '_')
    {
        index = 2;
        while (index < length && prefix[index] >= '0' && prefix[index] <= '9')
            index++;

        if (index == 2)
            return nil;
    }

    if (index < length && (prefix[index] == '-' || prefix[index] == '+'))
        index++;

    NSDictionary<NSString *, NSString *>* consentByOwner = CountlySDKLogsConsentByOwner();
    if (index == 0 && length > 0 && prefix[0] != '[')
    {
        // a C function, such as the crash handler, opens with its bare name
        while (index < length && CountlySDKLogsIsNameCharacter(prefix[index]))
            index++;

        return index > 0 ? consentByOwner[[NSString stringWithCharacters:prefix length:index]] : nil;
    }

    if (index >= length || prefix[index] != '[')
        return nil;

    NSUInteger classStart = ++index;
    while (index < length && CountlySDKLogsIsNameCharacter(prefix[index]))
        index++;

    if (index == classStart)
        return nil;

    NSString* className = [NSString stringWithCharacters:prefix + classStart length:index - classStart];
    // a method a category adds to a system class, such as the swizzled push and view callbacks, belongs to the module
    // the category is named after
    if (index < length && prefix[index] == '(')
    {
        NSUInteger categoryStart = ++index;
        while (index < length && CountlySDKLogsIsNameCharacter(prefix[index]))
            index++;

        if (index > categoryStart)
            className = [NSString stringWithCharacters:prefix + categoryStart length:index - categoryStart];

        if (index < length && prefix[index] == ')')
            index++;
    }

    // the Countly class is the only owner keyed by selector, it serves every feature through its public methods
    if ([className isEqualToString:@"Countly"] && index < length && prefix[index] == ' ')
    {
        NSUInteger selectorStart = ++index;
        while (index < length && CountlySDKLogsIsNameCharacter(prefix[index]))
            index++;

        if (index > selectorStart)
        {
            NSString* selectorName = [NSString stringWithCharacters:prefix + selectorStart length:index - selectorStart];
            NSString* methodConsent = consentByOwner[[@"Countly " stringByAppendingString:selectorName]];
            if (methodConsent)
                return methodConsent;
        }
    }

    return consentByOwner[className];
}

/// The one character level string of a gathered line. A boxed char would go on the wire as a number, @('e') as 101.
static NSString* CountlySDKLogsLevelString(char levelChar)
{
    switch (levelChar)
    {
        case 'e': return @"e";
        case 'w': return @"w";
        case 'i': return @"i";
        case 'd': return @"d";
        case 'v': return @"v";
        default: return [NSString stringWithFormat:@"%c", levelChar];
    }
}

/// The message of a gathered line, cut to the longest message the server keeps.
static NSString* CountlySDKLogsTrimmedMessage(NSString* logString)
{
    if (logString.length <= kCountlySDKLogsMaxMessageLength)
        return logString;

    // never split a surrogate pair, a lone surrogate would make the whole batch unserialisable
    NSRange boundary = [logString rangeOfComposedCharacterSequenceAtIndex:kCountlySDKLogsMaxMessageLength];
    return [logString substringToIndex:boundary.location];
}

/// Whether a line needing the given consent getter may be gathered now. Always when consent is not required, never before
/// the SDK has started, and a line of no single feature (NSNull) needs both the events and the user details consent.
static BOOL CountlySDKLogsConsentGiven(id consent)
{
    CountlyConsentManager* consentManager = CountlyConsentManager.sharedInstance;
    if (!consentManager)
        return NO;

    if (!consentManager.requiresConsent)
        return YES;

    if (![consent isKindOfClass:NSString.class])
        return consentManager.consentForEvents && consentManager.consentForUserDetails;

    return [[consentManager valueForKey:consent] boolValue];
}

/// A copy of the line carrying the consent it needs, or, with nil, the line as it is uploaded.
static NSDictionary* CountlySDKLogsLineWithConsent(NSDictionary* line, id consent)
{
    NSMutableDictionary* copy = line.mutableCopy;
    copy[kCountlySDKLogsAwaitedConsent] = consent;
    return copy;
}

/// The batch as it goes on the wire, its lines without the consent they were gathered under.
static NSDictionary* CountlySDKLogsUploadableBatch(NSDictionary* batch)
{
    NSMutableArray* lines = NSMutableArray.new;
    for (NSDictionary* line in batch[kCountlyQSSDKLogsBatchLines])
        [lines addObject:CountlySDKLogsLineWithConsent(line, nil)];

    NSMutableDictionary* uploadable = batch.mutableCopy;
    uploadable[kCountlyQSSDKLogsBatchLines] = lines;
    return uploadable;
}

/// Marks init as finished or not. Finishing decides the consent of the lines captured while init ran, under the lock the
/// capture reads this flag in, so every line is decided either here or when it is captured.
- (void)setHasFinishedInit:(BOOL)hasFinishedInit
{
    @synchronized (_sdkLogsLock) {
        _hasFinishedInit = hasFinishedInit;
        if (hasFinishedInit)
            [self redecideSdkLogLinesConsentLocked];
    }
}

- (void)captureSdkLogLine:(NSString *)logString level:(char)levelChar {
    if (!self.isCapturingSdkLogs)
        return;

    // this thread is delivering or sending a batch, so anything it logs is this feature's own transport commentary
    if (s_isSdkLogsTransportWork)
        return;

    // checked on every thread, because a queued batch is sent, and logged in full, by whichever
    // thread happens to drain the request queue later on
    if ([logString rangeOfString:kCountlySDKLogsTransportMarker options:NSLiteralSearch].location != NSNotFound)
        return;

    // while nothing is decided the wanted levels are unknown, so every level is gathered and the
    // buffer is filtered again once a directive names them. Checked again under the lock
    if (!(self.sdkLogsLevelMask & CountlySDKLogsLevelBit(levelChar)))
        return;

    // built before taking the lock, which every logging thread contends for
    NSString* message = CountlySDKLogsTrimmedMessage(logString);
    // every line keeps its consent so a later withdrawal can send it back to wait, init lines are decided when init finishes
    id consent = CountlySDKLogsConsentForLine(message) ?: NSNull.null;
    NSDictionary* line = @{
        kCountlyQSSDKLogsTimestamp: @((long long)floor((CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970) * 1000)),
        kCountlyQSSdkLogsMessage: message,
        kCountlyQSSdkLogsLevel: CountlySDKLogsLevelString(levelChar),
        kCountlySDKLogsAwaitedConsent: consent
    };

    BOOL isDeliveryDue = NO;
    BOOL includePartialBatch = NO;

    @synchronized (_sdkLogsLock) {
        if (_sdkLogsState == CLYSDKLogsStateOff)
            return;

        if (!(_sdkLogsLevelMask & CountlySDKLogsLevelBit(levelChar)))
            return;

        if (_hasFinishedInit && !CountlySDKLogsConsentGiven(consent))
        {
            [_sdkLogsAwaitingConsent addObject:line];
            _sdkLogsAwaitingConsentChars += message.length;
            [self trimSdkLogsAwaitingConsentLocked];
            return;
        }

        NSInteger bufferedBefore = (NSInteger)_sdkLogs.count;
        NSInteger charsBefore = _sdkLogsChars;
        [_sdkLogs addObject:line];
        _sdkLogsChars += message.length;
        [self trimSdkLogsBufferLocked];

        isDeliveryDue = [self isSdkLogsDeliveryDueLockedFromCount:bufferedBefore chars:charsBefore includePartialBatch:&includePartialBatch];
    }

    // never on this thread: delivering touches the request queue and logs, which comes straight back
    // into this method, and the caller may be inside a persistency lock
    if (isDeliveryDue)
        [self scheduleSdkLogsDelivery:includePartialBatch];
}

/// Characters of one gathered line's message, the unit the character ceiling counts.
static NSInteger CountlySDKLogsLineLength(NSDictionary* line)
{
    return (NSInteger)((NSString *)line[kCountlyQSSdkLogsMessage]).length;
}

/// Characters of the messages of all the given lines.
static NSInteger CountlySDKLogsLength(NSArray* lines)
{
    NSInteger chars = 0;
    for (NSDictionary* line in lines)
        chars += CountlySDKLogsLineLength(line);

    return chars;
}

/// Keeps only the lines of the given levels and returns the characters of what is kept.
static NSInteger CountlySDKLogsKeepLevels(NSMutableArray* lines, NSString* levels)
{
    [lines filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary* line, NSDictionary* bindings) {
        return [levels containsString:line[kCountlyQSSdkLogsLevel]];
    }]];

    return CountlySDKLogsLength(lines);
}

/// Appends every line whose consent is given to buffered and every other line to awaiting, in the order of the given lines.
static void CountlySDKLogsSplitByConsent(NSArray* lines, NSMutableArray* buffered, NSMutableArray* awaiting)
{
    for (NSDictionary* line in lines)
    {
        if (CountlySDKLogsConsentGiven(line[kCountlySDKLogsAwaitedConsent]))
            [buffered addObject:line];
        else
            [awaiting addObject:line];
    }
}

/// Drops the oldest lines until both the line and the character ceiling hold. While gathering they count into the drop count,
/// while undecided per level, so that only the levels a directive adopts are reported. Call under the lock.
- (void)trimSdkLogsBufferLocked
{
    while ((NSInteger)_sdkLogs.count > kCountlySDKLogsMaxBufferedLines || (_sdkLogsChars > kCountlySDKLogsCharCeiling && _sdkLogs.count > 1))
    {
        NSDictionary* dropped = _sdkLogs.firstObject;
        _sdkLogsChars -= CountlySDKLogsLineLength(dropped);
        [_sdkLogs removeObjectAtIndex:0];

        if (_sdkLogsState == CLYSDKLogsStateGathering)
            _sdkLogsDropCount++;
        else
            [self countUndecidedSdkLogDropLocked:dropped];
    }
}

/// Counts a line dropped while undecided under its level. Call under the lock.
- (void)countUndecidedSdkLogDropLocked:(NSDictionary *)line
{
    NSString* level = line[kCountlyQSSdkLogsLevel];
    const char* found = level.length == 1 ? strchr(kCountlySDKLogsLevelChars, (char)[level characterAtIndex:0]) : NULL;
    if (found && *found)
        sdkLogsUndecidedDrops[found - kCountlySDKLogsLevelChars]++;
}

/// Adds the lines dropped while undecided to the drop count, for the given levels only, and clears every level's count. Call under the lock.
- (void)adoptUndecidedSdkLogDropsLocked:(NSString *)levels
{
    NSUInteger mask = CountlySDKLogsLevelMask(levels);
    for (size_t i = 0; i < sizeof(sdkLogsUndecidedDrops) / sizeof(sdkLogsUndecidedDrops[0]); i++)
    {
        if (mask & ((NSUInteger)1 << i))
            _sdkLogsDropCount += sdkLogsUndecidedDrops[i];

        sdkLogsUndecidedDrops[i] = 0;
    }
}

/// Drops the oldest lines awaiting consent until both ceilings hold. Call under the lock.
- (void)trimSdkLogsAwaitingConsentLocked
{
    // not counted into the drop count: a line that never had its consent was never gathered
    while ((NSInteger)_sdkLogsAwaitingConsent.count > kCountlySDKLogsMaxBufferedLines || (_sdkLogsAwaitingConsentChars > kCountlySDKLogsCharCeiling && _sdkLogsAwaitingConsent.count > 1))
    {
        _sdkLogsAwaitingConsentChars -= CountlySDKLogsLineLength(_sdkLogsAwaitingConsent.firstObject);
        [_sdkLogsAwaitingConsent removeObjectAtIndex:0];
    }
}

/// Whether the buffer grown from the given counts calls for a delivery, setting includePartialBatch when only the character threshold does. Call under the lock.
- (BOOL)isSdkLogsDeliveryDueLockedFromCount:(NSInteger)bufferedBefore chars:(NSInteger)charsBefore includePartialBatch:(BOOL *)includePartialBatch
{
    // only the line that completes a batch schedules a delivery, so a full buffer held back by tracking does not queue one per line
    BOOL completesBatch = _sdkLogsState == CLYSDKLogsStateGathering && bufferedBefore < _sdkLogsBatchSize && (NSInteger)_sdkLogs.count >= _sdkLogsBatchSize;
    BOOL reachesCharThreshold = !completesBatch && _sdkLogsState == CLYSDKLogsStateGathering && charsBefore < kCountlySDKLogsDeliveryCharThreshold && _sdkLogsChars >= kCountlySDKLogsDeliveryCharThreshold;

    *includePartialBatch = reachesCharThreshold;
    return completesBatch || reachesCharThreshold;
}

/// Moves lines into the buffer or the awaiting list by their consent, oldest first, and returns NO when none moved. Call under the lock.
- (BOOL)redecideSdkLogLinesConsentLocked
{
    NSMutableArray* buffered = NSMutableArray.new;
    NSMutableArray* awaiting = NSMutableArray.new;

    CountlySDKLogsSplitByConsent(_sdkLogs, buffered, awaiting);
    NSUInteger withdrawnCount = awaiting.count;
    CountlySDKLogsSplitByConsent(_sdkLogsAwaitingConsent, buffered, awaiting);

    if (withdrawnCount == 0 && awaiting.count == _sdkLogsAwaitingConsent.count)
        return NO;

    NSComparator byCaptureTime = ^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        return [a[kCountlyQSSDKLogsTimestamp] compare:b[kCountlyQSSDKLogsTimestamp]];
    };
    [buffered sortWithOptions:NSSortStable usingComparator:byCaptureTime];
    [awaiting sortWithOptions:NSSortStable usingComparator:byCaptureTime];

    [_sdkLogs setArray:buffered];
    _sdkLogsChars = CountlySDKLogsLength(_sdkLogs);
    [_sdkLogsAwaitingConsent setArray:awaiting];
    _sdkLogsAwaitingConsentChars = CountlySDKLogsLength(_sdkLogsAwaitingConsent);

    [self trimSdkLogsBufferLocked];
    [self trimSdkLogsAwaitingConsentLocked];
    return YES;
}

- (void)redecideSdkLogLinesConsent
{
    BOOL isDeliveryDue = NO;
    BOOL includePartialBatch = NO;

    @synchronized (_sdkLogsLock) {
        // the lines captured during init are decided when init finishes, the consent state is incomplete before that
        if (!_hasFinishedInit)
            return;

        NSInteger bufferedBefore = (NSInteger)_sdkLogs.count;
        NSInteger charsBefore = _sdkLogsChars;
        if (![self redecideSdkLogLinesConsentLocked])
            return;

        isDeliveryDue = [self isSdkLogsDeliveryDueLockedFromCount:bufferedBefore chars:charsBefore includePartialBatch:&includePartialBatch];
    }

    if (isDeliveryDue)
        [self scheduleSdkLogsDelivery:includePartialBatch];
}

- (void)countEvictedSdkLogRequest:(NSString *)queryString
{
    NSString* payload = [queryString cly_valueForQueryStringKey:kCountlyQSSdkLogs];
    id batch = payload ? [NSJSONSerialization JSONObjectWithData:[payload cly_dataUTF8] options:0 error:nil] : nil;
    if (![batch isKindOfClass:NSDictionary.class] || ![batch[kCountlyQSSDKLogsBatchLines] isKindOfClass:NSArray.class] || ![batch[kCountlyQSSDKLogsDropCount] isKindOfClass:NSNumber.class])
        return;

    [self countSdkLogBatchAsDropped:batch];
}

/// Queues a delivery run on the delivery queue. Nothing is uploaded before init finishes, the init lines go out from there.
- (void)scheduleSdkLogsDelivery:(BOOL)includePartialBatch
{
    if (!self.hasFinishedInit)
        return;

    dispatch_async(self.sdkLogsDeliveryQueue, ^{
        [self deliverSdkLogBatches:includePartialBatch drainAll:NO];
    });
}

- (void)flushSdkLogs {
    [self deliverSdkLogBatches:YES drainAll:YES];
}

- (void)scheduleSdkLogsFlush
{
    [self scheduleSdkLogsDelivery:YES];
}

- (void)stopSdkLogGatheringForDeviceIDChange
{
    if (!self.isCapturingSdkLogs)
        return;

    // a delivery already running on the delivery queue would otherwise send the old user's lines under the new device ID
    dispatch_semaphore_t delivered = dispatch_semaphore_create(0);
    dispatch_async(self.sdkLogsDeliveryQueue, ^{
        dispatch_semaphore_signal(delivered);
    });
    dispatch_semaphore_wait(delivered, dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC));

    [self flushSdkLogs];
    [self updateLogGatheringState:NO levels:nil batch:0 lgid:nil];
}

/// Uploads held lines on the calling thread: one batch while no other waits in the request queue, or with drainAll every
/// held line. Lines stay buffered while tracking is off.
- (void)deliverSdkLogBatches:(BOOL)includePartialBatch drainAll:(BOOL)drainAll
{
    if (!self.hasFinishedInit)
        return;

    // marks everything logged until the sends return as this feature's own transport work
    BOOL callerTransportWork = self.isSdkLogsTransportWork;
    [self setSdkLogsTransportWork:YES];
    [self deliverSdkLogBatchesMarked:includePartialBatch drainAll:drainAll];
    [self setSdkLogsTransportWork:callerTransportWork];
}

/// The delivery loop proper, run with the transport marker already set on this thread so its own lines are not gathered.
- (void)deliverSdkLogBatchesMarked:(BOOL)includePartialBatch drainAll:(BOOL)drainAll
{
    if (!CountlyServerConfig.sharedInstance.trackingEnabled)
    {
        // the request queue refuses everything while tracking is off, taking the lines out now would only lose them
        CLY_LOG_D(@"%s, tracking is disabled, keeping the gathered lines buffered", __FUNCTION__);
        return;
    }

    if (!drainAll)
    {
        // one batch waits in the request queue at a time, so the lines held while requests fail stay in the capped
        // buffer instead of crowding the queue
        if ([CountlyPersistency.sharedInstance queueContainsSdkLogs])
        {
            CLY_LOG_D(@"%s, a gathered log batch is still waiting in the request queue, the rest goes out once it is sent", __FUNCTION__);
            [self resumeSdkLogsDeliveryWhenQueueDrains];
            return;
        }

        // no batch waits, so a wait armed earlier and lost with its runnable must not hold up the next one
        @synchronized (_sdkLogsLock) {
            _sdkLogsDeliveryAwaitsQueueDrain = NO;
        }
    }

    BOOL takePartial = includePartialBatch;
    NSDictionary* batch;
    while ((batch = [self takeSdkLogBatch:takePartial]))
    {
        // draining takes the partial tail too, a single delivery takes only its first batch
        takePartial = drainAll;
        CLY_LOG_D(@"%s, delivering [ %lu ] gathered log lines, [ %@ ] dropped", __FUNCTION__, (unsigned long)((NSArray *)batch[kCountlyQSSDKLogsBatchLines]).count, batch[kCountlyQSSDKLogsDropCount]);

        NSString* payload = CountlyJSONFromObject(CountlySDKLogsUploadableBatch(batch));
        if (!payload)
        {
            // putting an unserialisable batch back would make it the head of every later delivery, so it is lost and counted
            CLY_LOG_W(@"%s, a gathered log batch could not be serialised, dropping it", __FUNCTION__);
            [self countSdkLogBatchAsDropped:batch];
            continue;
        }

        if (![CountlyConnectionManager.sharedInstance sendSdkLogs:payload])
        {
            // the queue refused it, so the lines are still ours
            [self restoreSdkLogBatch:batch];
            return;
        }

        if (!drainAll)
        {
            // the next delivery finds this batch waiting in the queue and resumes once it is sent
            BOOL nextIncludesPartialBatch = NO;
            if ([self isSdkLogsDeliveryDueBeforeTheTimer:&nextIncludesPartialBatch])
                [self scheduleSdkLogsDelivery:nextIncludesPartialBatch];

            return;
        }
    }
}

/// Whether held lines call for a delivery before the timer's: a full batch, or a buffer near the character ceiling, which
/// then goes as a partial batch. A smaller remainder waits for the timer, background or terminate, since the request path
/// logs a line or two per send on threads the transport mark does not cover, and chasing those would send a tiny batch
/// per round trip of the queue.
- (BOOL)isSdkLogsDeliveryDueBeforeTheTimer:(BOOL *)includePartialBatch
{
    @synchronized (_sdkLogsLock) {
        if (_sdkLogsState != CLYSDKLogsStateGathering)
            return NO;

        *includePartialBatch = _sdkLogsChars >= kCountlySDKLogsDeliveryCharThreshold;
        return *includePartialBatch || (NSInteger)_sdkLogs.count >= _sdkLogsBatchSize;
    }
}

/// Runs a delivery again once the request queue has sent what it holds, the waiting log batch included, so a backlog goes
/// out one batch at a time. Only one such wait is armed at a time.
- (void)resumeSdkLogsDeliveryWhenQueueDrains
{
    @synchronized (_sdkLogsLock) {
        if (_sdkLogsDeliveryAwaitsQueueDrain)
            return;

        _sdkLogsDeliveryAwaitsQueueDrain = YES;
    }

    __weak CountlyCommon* weakSelf = self;
    [CountlyConnectionManager.sharedInstance addQueueFlushRunnable:^{
        [weakSelf resumeSdkLogsDeliveryAfterQueueDrain];
    }];

    // the queue may have been sent between the check and the registration, and then only its next request would run it
    if (![CountlyPersistency.sharedInstance queueContainsSdkLogs])
        [self resumeSdkLogsDeliveryAfterQueueDrain];
}

/// Ends the armed wait and schedules the delivery it held back, once for each wait, when held lines call for one before the timer.
- (void)resumeSdkLogsDeliveryAfterQueueDrain
{
    @synchronized (_sdkLogsLock) {
        if (!_sdkLogsDeliveryAwaitsQueueDrain)
            return;

        _sdkLogsDeliveryAwaitsQueueDrain = NO;
    }

    BOOL includePartialBatch = NO;
    if ([self isSdkLogsDeliveryDueBeforeTheTimer:&includePartialBatch])
        [self scheduleSdkLogsDelivery:includePartialBatch];
}

/// Accounts a batch that can never be sent as dropped lines, so the loss still reaches the operator with the next batch.
- (void)countSdkLogBatchAsDropped:(NSDictionary *)batch
{
    @synchronized (_sdkLogsLock) {
        if (_sdkLogsState != CLYSDKLogsStateGathering || ![_sdkLogsGatheringId isEqualToString:batch[kCountlyQSSDKLogsGatherId]])
            return;

        _sdkLogsDropCount += ((NSArray *)batch[kCountlyQSSDKLogsBatchLines]).count + ((NSNumber *)batch[kCountlyQSSDKLogsDropCount]).integerValue;
    }
}

/// Takes up to one batch of the oldest lines out of the buffer as the 'sdk_logs' payload, or nil when there is nothing to upload.
- (NSDictionary *)takeSdkLogBatch:(BOOL)includePartialBatch
{
    @synchronized (_sdkLogsLock) {
        if (_sdkLogsState != CLYSDKLogsStateGathering)
            return nil;

        // a consent setter redecides only after its own side effects, whose log lines can complete a batch in between
        [self redecideSdkLogLinesConsentLocked];
        if (_sdkLogs.count == 0)
            return nil;
        if (!includePartialBatch && (NSInteger)_sdkLogs.count < _sdkLogsBatchSize)
            return nil;

        NSInteger count = MIN((NSInteger)_sdkLogs.count, _sdkLogsBatchSize);
        NSArray* lines = [_sdkLogs subarrayWithRange:NSMakeRange(0, count)];
        [_sdkLogs removeObjectsInRange:NSMakeRange(0, count)];
        for (NSDictionary* line in lines)
            _sdkLogsChars -= CountlySDKLogsLineLength(line);

        NSDictionary* batch = @{
            kCountlyQSSDKLogsGatherId: _sdkLogsGatheringId,
            kCountlyQSSDKLogsDropCount: @(_sdkLogsDropCount),
            kCountlyQSSDKLogsBatchLines: lines
        };
        // the loss is reported once, with the batch that follows it
        _sdkLogsDropCount = 0;
        return batch;
    }
}

/// Puts a batch the queue refused back at the front of the buffer, oldest first, drop count included.
- (void)restoreSdkLogBatch:(NSDictionary *)batch
{
    @synchronized (_sdkLogsLock) {
        if (_sdkLogsState != CLYSDKLogsStateGathering || ![_sdkLogsGatheringId isEqualToString:batch[kCountlyQSSDKLogsGatherId]])
            return;

        NSArray* lines = batch[kCountlyQSSDKLogsBatchLines];
        [_sdkLogs insertObjects:lines atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, lines.count)]];
        for (NSDictionary* line in lines)
            _sdkLogsChars += CountlySDKLogsLineLength(line);
        _sdkLogsDropCount += ((NSNumber *)batch[kCountlyQSSDKLogsDropCount]).integerValue;
        [self trimSdkLogsBufferLocked];
    }
}

- (void)setSdkLogsTransportWork:(BOOL)transporting
{
    s_isSdkLogsTransportWork = transporting;
}

- (BOOL)isSdkLogsTransportWork
{
    return s_isSdkLogsTransportWork;
}

- (void)decideLogGatheringOffIfUndecided:(NSString *)reason
{
    // one critical section: a directive landing between a check and a separate write would be wiped out
    @synchronized (_sdkLogsLock) {
        if (_sdkLogsState != CLYSDKLogsStateUndecided)
            return;
        [self setLogGatheringOffLocked];
    }

    CLY_LOG_D(@"%s, %@, log gathering is off, anything gathered so far has been discarded", __FUNCTION__, reason);
}

/// Arms a gather with the given directive, leaving the buffer as it is. Call under the lock.
- (void)setLogGatheringOnLocked:(NSString *)levels batch:(NSInteger)batch gatheringId:(NSString *)gatheringId
{
    _sdkLogsState = CLYSDKLogsStateGathering;
    self.sdkLogsLevels = levels;
    _sdkLogsBatchSize = batch;
    _sdkLogsGatheringId = gatheringId;
}

/// Off with an empty buffer and default directive values. Call under the lock.
- (void)setLogGatheringOffLocked
{
    _sdkLogsState = CLYSDKLogsStateOff;
    _sdkLogsBatchSize = kCountlySDKLogsDefaultBatchSize;
    self.sdkLogsLevels = kCountlySDKLogsAllLevels;
    _sdkLogsGatheringId = @"";
    [_sdkLogs removeAllObjects];
    _sdkLogsDropCount = 0;
    memset(sdkLogsUndecidedDrops, 0, sizeof(sdkLogsUndecidedDrops));
    _sdkLogsChars = 0;
    [_sdkLogsAwaitingConsent removeAllObjects];
    _sdkLogsAwaitingConsentChars = 0;
}

/// Takes every held line as one batch of the running gather, deciding consent again first, or nil when none is held. Call under the lock.
- (NSDictionary *)takeAllSdkLogLinesLocked
{
    [self redecideSdkLogLinesConsentLocked];
    if (_sdkLogs.count == 0 || _sdkLogsGatheringId.length == 0)
        return nil;

    return @{
        kCountlyQSSDKLogsGatherId: _sdkLogsGatheringId,
        kCountlyQSSDKLogsDropCount: @(_sdkLogsDropCount),
        kCountlyQSSDKLogsBatchLines: _sdkLogs.copy
    };
}

/// Hands the last batch of a stopped gather to the request queue, once. Its lines are gone if the queue refuses it.
- (void)uploadSdkLogsTailBatch:(NSDictionary *)batch
{
    if (!self.hasFinishedInit)
        return;

    NSString* payload = CountlyJSONFromObject(CountlySDKLogsUploadableBatch(batch));
    if (!payload)
        return;

    BOOL callerTransportWork = self.isSdkLogsTransportWork;
    [self setSdkLogsTransportWork:YES];
    BOOL isQueued = [CountlyConnectionManager.sharedInstance sendSdkLogs:payload];
    [self setSdkLogsTransportWork:callerTransportWork];

    CLY_LOG_D(@"%s, the last [ %lu ] lines of the stopped gather %@", __FUNCTION__, (unsigned long)((NSArray *)batch[kCountlyQSSDKLogsBatchLines]).count, isQueued ? @"are queued" : @"are dropped, the request queue refused them");
}

- (void)updateLogGatheringState:(BOOL)enabled levels:(nullable NSString *)levels batch:(NSInteger)batch lgid:(nullable NSString *)lgid {
    // batches without a gather id can not be attributed to a capture and the server rejects them all
    if (enabled && lgid.length == 0) {
        CLY_LOG_W(@"%s, log gathering was enabled without a gather id, not gathering", __FUNCTION__);
        enabled = NO;
    }

    NSString* sanitizedLevels = [self sanitizeLogGatheringLevels:levels];
    NSInteger sanitizedBatch = MIN(MAX(batch > 0 ? batch : kCountlySDKLogsDefaultBatchSize, kCountlySDKLogsMinBatchSize), kCountlySDKLogsMaxBufferedLines);
    NSUInteger held = 0;
    BOOL wasGathering = NO;
    NSDictionary* tailBatch = nil;

    @synchronized (_sdkLogsLock) {
        // held lines belong to the previous gather and the server rejects them. This can not fire while
        // undecided, where the provisional lines belong to whichever gather adopts them
        BOOL belongToAnotherGather = _sdkLogsState != CLYSDKLogsStateUndecided && ![_sdkLogsGatheringId isEqualToString:lgid];
        wasGathering = _sdkLogsState == CLYSDKLogsStateGathering;

        if (!enabled) {
            // a stopped gather's held lines go out once under its id, the server still takes them for a while.
            // Lines held while undecided belong to no gather and are dropped
            if (wasGathering && _hasFinishedInit)
                tailBatch = [self takeAllSdkLogLinesLocked];
            [self setLogGatheringOffLocked];
        } else if (belongToAnotherGather) {
            [self setLogGatheringOffLocked];
            [self setLogGatheringOnLocked:sanitizedLevels batch:sanitizedBatch gatheringId:lgid];
        } else {
            [self setLogGatheringOnLocked:sanitizedLevels batch:sanitizedBatch gatheringId:lgid];
            [self adoptUndecidedSdkLogDropsLocked:sanitizedLevels];
            // adoption: the provisional lines were gathered at every level, so apply the filter now
            _sdkLogsChars = CountlySDKLogsKeepLevels(_sdkLogs, sanitizedLevels);
            [self trimSdkLogsBufferLocked];
            _sdkLogsAwaitingConsentChars = CountlySDKLogsKeepLevels(_sdkLogsAwaitingConsent, sanitizedLevels);
            held = _sdkLogs.count;
        }
    }

    if (tailBatch)
        [self uploadSdkLogsTailBatch:tailBatch];

    if (enabled) {
        CLY_LOG_D(@"%s, log gathering on, id:[ %@ ] levels:[ %@ ] batch:[ %ld ], holding [ %lu ] lines", __FUNCTION__, lgid, sanitizedLevels, (long)sanitizedBatch, (unsigned long)held);
        // adoption may hand over a buffer that is already past the batch size, partial batches wait for the timer
        if (!wasGathering)
            [self scheduleSdkLogsDelivery:NO];
    } else {
        CLY_LOG_D(@"%s, log gathering is off, the held lines of a stopped gather went out once and the rest is discarded", __FUNCTION__);
    }
}

/// Keeps only the level characters this SDK knows, lowercased, in the order sent, without duplicates.
/// Falls back to every level when nothing usable is left, an armed gather that captures nothing would look like a broken feature.
- (NSString *)sanitizeLogGatheringLevels:(nullable NSString *)levels
{
    NSMutableString* filtered = NSMutableString.new;
    for (NSUInteger i = 0; i < levels.length; i++)
    {
        NSString* level = [[levels substringWithRange:NSMakeRange(i, 1)] lowercaseString];
        if ([kCountlySDKLogsAllLevels containsString:level] && ![filtered containsString:level])
            [filtered appendString:level];
    }

    return filtered.length > 0 ? filtered.copy : kCountlySDKLogsAllLevels;
}

void CountlyPrint(NSString *stringToPrint)
{
    NSLog(@"%@%@", kCountlyInternalLogPrefix, stringToPrint);
}

void CountlyRunOnMainThread(dispatch_block_t block)
{
    if (NSThread.isMainThread)
        block();
    else
        dispatch_async(dispatch_get_main_queue(), block);
}

#pragma mark - Time/Date related methods
- (NSInteger)hourOfDay
{
    NSDateComponents* components = [gregorianCalendar components:NSCalendarUnitHour fromDate:NSDate.date];
    return components.hour;
}

- (NSInteger)dayOfWeek
{
    NSDateComponents* components = [gregorianCalendar components:NSCalendarUnitWeekday fromDate:NSDate.date];
    return components.weekday - 1;
}

- (NSInteger)timeZone
{
    return NSTimeZone.systemTimeZone.secondsFromGMT / 60;
}

- (NSInteger)timeSinceLaunch
{
    return (int)NSDate.date.timeIntervalSince1970 - startTime;
}

- (NSTimeInterval)uniqueTimestamp
{
    long long now = floor(NSDate.date.timeIntervalSince1970 * 1000);

    if (now <= self.lastTimestamp)
        self.lastTimestamp++;
    else
        self.lastTimestamp = now;

    return (NSTimeInterval)(self.lastTimestamp / 1000.0);
}

- (NSString *)randomEventID
{
    const int size = 6;
    void *randomBuffer = malloc(size);
    arc4random_buf(randomBuffer, size);
    NSData* randomData = [NSData dataWithBytesNoCopy:randomBuffer length:size freeWhenDone:YES];
    NSString* randomBase64 = [randomData base64EncodedStringWithOptions:0];
    NSTimeInterval timestamp = self.uniqueTimestamp;
    NSString* randomEventID = [NSString stringWithFormat:@"%@%lld", randomBase64, (long long)(timestamp * 1000)];
    return randomEventID;
}

#pragma mark - Orientation

- (void)observeDeviceOrientationChanges
{
#if (TARGET_OS_IOS)
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(deviceOrientationDidChange:) name:UIDeviceOrientationDidChangeNotification object:nil];
#endif
}

- (void)deviceOrientationDidChange:(NSNotification *)notification
{
    if (!self.enableOrientationTracking)
        return;

    //NOTE: Delay is needed for interface orientation change animation to complete. Otherwise old interface orientation value is returned.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(recordOrientation) object:nil];
    [self performSelector:@selector(recordOrientation) withObject:nil afterDelay:0.5];
}

- (void)recordOrientation
{
#if (TARGET_OS_IOS)
    if (!self.enableOrientationTracking)
        return;
    
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        CLY_LOG_D(@"%s app is in the background, orientation recording will be ignored", __FUNCTION__);
        return;
    }
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    UIInterfaceOrientation interfaceOrientation = UIApplication.sharedApplication.statusBarOrientation;
#pragma GCC diagnostic pop

    NSString* mode = nil;
    if (UIInterfaceOrientationIsPortrait(interfaceOrientation))
        mode = @"portrait";
    else if (UIInterfaceOrientationIsLandscape(interfaceOrientation))
        mode = @"landscape";

    if (!mode)
    {
        CLY_LOG_D(@"%s interface orientation is neither landscape nor portrait, orientation event will be skipped", __FUNCTION__);
        return;
    }

    if ([mode isEqualToString:self.lastInterfaceOrientation])
    {
        CLY_LOG_V(@"%s interface orientation did not change, orientation event will be skipped, mode: [%@]", __FUNCTION__, self.lastInterfaceOrientation);
        return;
    }

    CLY_LOG_D(@"%s interface orientation changed, previousMode: [%@], mode: [%@]", __FUNCTION__, self.lastInterfaceOrientation, mode);

    if (!CountlyConsentManager.sharedInstance.consentForUserDetails)
        return;
    
    self.lastInterfaceOrientation = mode;

    [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventOrientation segmentation:@{kCountlyOrientationKeyMode: mode}];
#endif
}

#pragma mark - Others

- (void)startBackgroundTask
{
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
    if (self.bgTask != UIBackgroundTaskInvalid)
        return;

    self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }];
#endif
}

- (void)finishBackgroundTask
{
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
    if (self.bgTask != UIBackgroundTaskInvalid && !CountlyConnectionManager.sharedInstance.connection)
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif
}

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
+ (UIWindow *)keyWindow
{
    if (@available(iOS 13.0, *))
    {
        // connectedScenes is an unordered NSSet, so never rely on iteration order: search
        // explicitly for the correct window rather than acting on whichever scene comes first.
        NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;

        // 1) The key window of the foreground-active scene (the one the user is interacting with).
        for (UIScene *scene in scenes)
        {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]])
            {
                for (UIWindow *window in ((UIWindowScene *)scene).windows)
                    if (window.isKeyWindow)
                        return window;
            }
        }

        // 2) Any key window across all scenes.
        for (UIScene *scene in scenes)
        {
            if ([scene isKindOfClass:[UIWindowScene class]])
            {
                for (UIWindow *window in ((UIWindowScene *)scene).windows)
                    if (window.isKeyWindow)
                        return window;
            }
        }

        // 3) Fall back to the first window of a foreground-active scene.
        for (UIScene *scene in scenes)
        {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]])
            {
                UIWindow *window = ((UIWindowScene *)scene).windows.firstObject;
                if (window)
                    return window;
            }
        }
    }
#if (TARGET_OS_VISION)
    return nil;
#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.keyWindow;
#pragma GCC diagnostic pop
#endif
}

+ (CGRect)screenBounds
{
    UIWindow *window = [self keyWindow];
    if (window)
        return window.bounds;
#if (TARGET_OS_VISION)
    return CGRectZero;
#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return UIScreen.mainScreen.bounds;
#pragma GCC diagnostic pop
#endif
}

- (UIViewController *)topViewController
{
    UIViewController* topVC = CountlyCommon.keyWindow.rootViewController;

    while (YES)
    {
        if (topVC.presentedViewController)
            topVC = topVC.presentedViewController;
        else if ([topVC isKindOfClass:UINavigationController.class])
            topVC = ((UINavigationController *)topVC).topViewController;
        else if ([topVC isKindOfClass:UITabBarController.class])
            topVC = ((UITabBarController *)topVC).selectedViewController;
        else
            break;
    }

    return topVC;
}

- (void)tryPresentingViewController:(UIViewController *)viewController
{
    [self tryPresentingViewController:viewController withCompletion:nil];
}

- (void)tryPresentingViewController:(UIViewController *)viewController withCompletion:(void (^ __nullable) (void))completion
{
    UIViewController* topVC = self.topViewController;

    if (topVC)
    {
        [topVC presentViewController:viewController animated:YES completion:^
        {
            if (completion)
                completion();
        }];

        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        [self tryPresentingViewController:viewController];
    });
}
#endif

- (NSURLSession *)URLSession
{
    if (CountlyConnectionManager.sharedInstance.URLSessionConfiguration)
    {
        return [NSURLSession sessionWithConfiguration:CountlyConnectionManager.sharedInstance.URLSessionConfiguration];
    }
    else
    {
        return NSURLSession.sharedSession;
    }
}

- (NSURLSession *)ImmediateURLSession
{
    // one lock for the check, the copy and the creation, or a header change between them finds nothing to drop
    @synchronized (self) {
        CountlyConnectionManager* connectionManager = CountlyConnectionManager.sharedInstance;
        BOOL usesPinnedCertificates = connectionManager.pinnedCertificates.count > 0;
        if (usesPinnedCertificates && self.pinnedImmediateURLSession)
            return self.pinnedImmediateURLSession;

        // Base on the user-provided URLSessionConfiguration so that things like
        // protocolClasses (test mocks), cookie policy, etc. are preserved.
        // If none was provided, fall back to default session configuration.
        NSURLSessionConfiguration *userConfig = connectionManager.URLSessionConfiguration;
        NSURLSessionConfiguration *immediateConfig = userConfig ? [userConfig copy] : [NSURLSessionConfiguration defaultSessionConfiguration];

        // Immediate requests must not be constrained by the SDK's configured
        // request timeout, so they get the system defaults.
        immediateConfig.timeoutIntervalForRequest = 60;
        immediateConfig.timeoutIntervalForResource = 7 * 24 * 60 * 60;

        if (!usesPinnedCertificates)
            return [NSURLSession sessionWithConfiguration:immediateConfig];

        // the connection manager checks the pinned certificates, and one session is kept since a delegate session lives until invalidated
        self.pinnedImmediateURLSession = [NSURLSession sessionWithConfiguration:immediateConfig delegate:connectionManager delegateQueue:nil];
        return self.pinnedImmediateURLSession;
    }
}

- (NSURLSessionDataTask *)immediateDataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
    @synchronized (self) {
        return [self.ImmediateURLSession dataTaskWithRequest:request completionHandler:completionHandler];
    }
}

- (void)invalidatePinnedImmediateURLSession
{
    @synchronized (self) {
        if (!self.pinnedImmediateURLSession)
            return;

        CLY_LOG_D(@"%s the immediate session kept for pinned certificates is dropped, the next immediate request builds a new one", __FUNCTION__);
        [self.pinnedImmediateURLSession finishTasksAndInvalidate];
        self.pinnedImmediateURLSession = nil;
    }
}

#if (TARGET_OS_IOS || TARGET_OS_VISION)
- (bool) hasTopNotch:(UIEdgeInsets)safeArea
{
    return safeArea.top >= 44;
}
#endif

- (CGSize)getWindowSize{
#if (TARGET_OS_IOS || TARGET_OS_VISION)
    UIWindow *window = [CountlyCommon keyWindow];

    if (!window) return CGSizeZero;

    CGSize size = window.bounds.size;

    if (@available(iOS 11.0, *)) {
        UIEdgeInsets safeArea = window.safeAreaInsets;
        if([self hasTopNotch:safeArea] || CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == SAFE_AREA){
            size.height -= (safeArea.top); // always respect notch
        }
        if(CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == SAFE_AREA){
            size.height -= safeArea.bottom;
        }
        size.width -= MAX(safeArea.left, safeArea.right); // regardles of given safe area, act for cutout
    }

    return size;
#else
    return CGSizeZero;
#endif
}

#if (TARGET_OS_IOS || TARGET_OS_VISION)
- (UIInterfaceOrientation)interfaceOrientation
{
    if (@available(iOS 13.0, *))
    {
        UIWindowScene *windowScene = [CountlyCommon keyWindow].windowScene;
        if (windowScene)
            return windowScene.interfaceOrientation;
    }
#if (TARGET_OS_IOS)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.statusBarOrientation;
#pragma GCC diagnostic pop
#else
    return UIInterfaceOrientationPortrait;
#endif
}
#endif


@end


#pragma mark - Internal ViewController
#if (TARGET_OS_IOS || TARGET_OS_VISION)
@implementation CLYInternalViewController : UIViewController

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];

    if (self.webView)
    {
        CGRect frame = CGRectInset(self.view.bounds, 20.0, 20.0);

        UIEdgeInsets insets = UIEdgeInsetsZero;
        if (@available(iOS 11.0, *))
        {
            insets = CountlyCommon.keyWindow.safeAreaInsets;
        }

        self.webView.navigationDelegate = self;
        frame = UIEdgeInsetsInsetRect(frame, insets);
        self.webView.frame = frame;
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *contentURL = navigationAction.request.URL;
    if ([contentURL.absoluteString containsString:@"cly_x_int=1"]) {
        CLY_LOG_I(@"%s content url is marked for the external browser and will be handed over, host: [%@], path: [%@]", __FUNCTION__, contentURL.host, contentURL.path);
        CLY_LOG_D(@"%s external browser handover content url detail, contentURL: [%@]", __FUNCTION__, contentURL.absoluteString);
        [[UIApplication sharedApplication] openURL:contentURL options:@{} completionHandler:^(BOOL success) {
            if (success) {
                CLY_LOG_I(@"[CLYInternalViewController] openURL completion, external browser accepted the content url, host: [%@], path: [%@]", contentURL.host, contentURL.path);
                CLY_LOG_D(@"[CLYInternalViewController] openURL completion detail, the content url accepted by the external browser, contentURL: [%@]", contentURL.absoluteString);
            }
            else {
                CLY_LOG_W(@"[CLYInternalViewController] openURL completion, external browser could not open the content url, host: [%@], path: [%@]", contentURL.host, contentURL.path);
                CLY_LOG_D(@"[CLYInternalViewController] openURL completion detail, the content url rejected by the external browser, contentURL: [%@]", contentURL.absoluteString);
            }
        }];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(null_unspecified WKNavigation *)navigation
{
    CLY_LOG_D(@"%s internal web view started loading", __FUNCTION__);

}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    CLY_LOG_D(@"%s internal web view finished loading", __FUNCTION__);
}


@end


@implementation CLYButton : UIButton

const CGFloat kCountlyDismissButtonSize = 30.0;
const CGFloat kCountlyDismissButtonMargin = 10.0;
const CGFloat kCountlyDismissButtonStandardStatusBarHeight = 20.0;

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        [self addTarget:self action:@selector(touchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    }

    return self;
}

- (void)touchUpInside:(id)sender
{
    if (self.onClick)
        self.onClick(self);
}

+ (CLYButton *)dismissAlertButton:(NSString * _Nullable)closeButtonText
{
    if (!closeButtonText) {
        closeButtonText = @"x";
    }
    CLYButton* dismissButton = [CLYButton buttonWithType:UIButtonTypeCustom];
    dismissButton.frame = (CGRect){CGPointZero, kCountlyDismissButtonSize, kCountlyDismissButtonSize};
    [dismissButton setTitle:closeButtonText forState:UIControlStateNormal];
    [dismissButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    dismissButton.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.5];
    dismissButton.layer.cornerRadius = dismissButton.bounds.size.width * 0.5;
    dismissButton.layer.borderColor = [UIColor.blackColor colorWithAlphaComponent:0.7].CGColor;
    dismissButton.layer.borderWidth = 1.0;
    dismissButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    
    return dismissButton;
}

+ (CLYButton *)dismissAlertButton
{
    return [CLYButton dismissAlertButton:nil];
}

- (void)positionToTopRight
{
    [self positionToTopRight:NO];
}

- (void)positionToTopRightConsideringStatusBar
{
    [self positionToTopRight:YES];
}

- (void)positionToTopRight:(BOOL)shouldConsiderStatusBar
{
    CGRect rect = self.frame;
    rect.origin.x = self.superview.bounds.size.width - self.bounds.size.width - kCountlyDismissButtonMargin;
    rect.origin.y = kCountlyDismissButtonMargin;

    if (shouldConsiderStatusBar)
    {
        if (@available(iOS 11.0, *))
        {
            CGFloat top = CountlyCommon.keyWindow.safeAreaInsets.top;

            if (top)
            {
                rect.origin.y += top;
            }
            else
            {
                rect.origin.y += kCountlyDismissButtonStandardStatusBarHeight;
            }
        }
        else
        {
            rect.origin.y += kCountlyDismissButtonStandardStatusBarHeight;
        }
    }

    self.frame = rect;
}

@end
#endif


#pragma mark - Proxy Object
@implementation CLYDelegateInterceptor

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    return [self.originalDelegate methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    if ([self.originalDelegate respondsToSelector:invocation.selector])
        [invocation invokeWithTarget:self.originalDelegate];
    else
        [super forwardInvocation:invocation];
}
@end



#pragma mark - Categories
/// Whether the value is a number JSON can represent: NaN and the infinities are numbers too, but fail a whole serialization.
static BOOL CountlyIsSupportedNumber(id value)
{
    return [value isKindOfClass:NSNumber.class] && isfinite(((NSNumber *)value).doubleValue);
}

NSString* CountlyJSONFromObject(id object)
{
    if (!object)
        return nil;

    if (![NSJSONSerialization isValidJSONObject:object])
    {
        CLY_LOG_E(@"%s object can not be represented as JSON and will be dropped, objectType: [%@]", __FUNCTION__, [object class]);
        return nil;
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (error)
    {
        CLY_LOG_E(@"%s JSON serialization failed and the data will be lost, objectType: [%@], error: [%@]", __FUNCTION__, [object class], error.localizedDescription);
    }

    return [data cly_stringUTF8];
}

@implementation NSString (Countly)
- (NSString *)cly_URLEscaped
{
    NSCharacterSet* charset = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    return [self stringByAddingPercentEncodingWithAllowedCharacters:charset];
}

- (NSString *)cly_SHA256
{
    const char* s = [self UTF8String];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(s, (CC_LONG)strlen(s), digest);

    NSMutableString* hash = NSMutableString.new;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hash appendFormat:@"%02x", digest[i]];

    return hash;
}

- (NSData *)cly_dataUTF8
{
    return [self dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)cly_valueForQueryStringKey:(NSString *)key
{
    NSString* tempURLString = [@"http://example.com/path?" stringByAppendingString:self];
    NSURLComponents* URLComponents = [NSURLComponents componentsWithString:tempURLString];
    for (NSURLQueryItem* queryItem in URLComponents.queryItems)
    {
        if ([queryItem.name isEqualToString:key])
        {
            return queryItem.value;
        }
    }

    return nil;
}

- (NSString *)cly_truncatedKey:(NSString *)explanation
{
    if (self.length > CountlyCommon.sharedInstance.maxKeyLength)
    {
        CLY_LOG_D(@"%s key exceeds the SDK key length limit and will be truncated, target: [%@], key: [%@], keyLength: [%lu], truncatedTo: [%lu]", __FUNCTION__, explanation, self, (unsigned long)self.length, (unsigned long)CountlyCommon.sharedInstance.maxKeyLength);
        return [self substringToIndex:CountlyCommon.sharedInstance.maxKeyLength];
    }

    return self;
}

- (NSString *)cly_truncatedPictureValue:(NSString *)explanation
{
    NSUInteger limit = CountlyCommon.sharedInstance.maxValueLengthPicture;
    if (self.length > limit)
    {
        CLY_LOG_D(@"%s value exceeds the SDK picture value limit and will be truncated, target: [%@], valueLength: [%lu], truncatedTo: [%lu]", __FUNCTION__, explanation, (unsigned long)self.length, (unsigned long)limit);
        CLY_LOG_D(@"%s truncated picture value detail, target: [%@], fullValue: [%@]", __FUNCTION__, explanation, self);
        return [self substringToIndex:limit];
    }
    return self;
}

- (NSString *)cly_truncatedValue:(NSString *)explanation
{
    if (self.length > CountlyCommon.sharedInstance.maxValueLength)
    {
        CLY_LOG_D(@"%s value exceeds the SDK value length limit and will be truncated, target: [%@], valueLength: [%lu], truncatedTo: [%lu]", __FUNCTION__, explanation, (unsigned long)self.length, (unsigned long)CountlyCommon.sharedInstance.maxValueLength);
        CLY_LOG_D(@"%s truncated value detail, target: [%@], fullValue: [%@]", __FUNCTION__, explanation, self);
        return [self substringToIndex:CountlyCommon.sharedInstance.maxValueLength];
    }

    return self;
}

@end

@implementation NSArray (Countly)
- (NSString *)cly_JSONify
{
    return [CountlyJSONFromObject(self) cly_URLEscaped];
}

- (NSArray *) cly_filterSupportedDataTypes {
    NSMutableArray *filteredArray = [NSMutableArray array];
    for (id obj in self) {
        if (CountlyIsSupportedNumber(obj) || [obj isKindOfClass:[NSString class]]) {
            [filteredArray addObject:obj];
        } else {
            CLY_LOG_D(@"%s dropping array element with an unsupported type, only NSNumber and NSString are allowed, receivedType: [%@]", __FUNCTION__, [obj class]);
        }
    }
    return filteredArray.copy;
}
@end

@implementation NSDictionary (Countly)
- (NSString *)cly_JSONify
{
    return [CountlyJSONFromObject(self) cly_URLEscaped];
}

- (NSDictionary *)cly_truncated:(NSString *)explanation
{
    NSMutableDictionary* truncatedDict = self.mutableCopy;
    [self enumerateKeysAndObjectsUsingBlock:^(NSString * key, id obj, BOOL * stop)
    {
        NSString* truncatedKey = [key cly_truncatedKey:[explanation stringByAppendingString:@" key"]];
        if (![truncatedKey isEqualToString:key])
        {
            truncatedDict[truncatedKey] = obj;
            [truncatedDict removeObjectForKey:key];
        }

        if ([obj isKindOfClass:NSString.class])
        {
            NSString* truncatedValue = [obj cly_truncatedValue:[explanation stringByAppendingString:@" value"]];
            if (![truncatedValue isEqualToString:obj])
            {
                truncatedDict[truncatedKey] = truncatedValue;
            }
        }
    }];

    return truncatedDict.copy;
}

- (NSDictionary *)cly_limited:(NSString *)explanation
{
    NSArray* allKeys = self.allKeys;

    if (allKeys.count <= CountlyCommon.sharedInstance.maxSegmentationValues)
        return self;

    NSMutableArray* excessKeys = allKeys.mutableCopy;
    [excessKeys removeObjectsInRange:(NSRange){0, CountlyCommon.sharedInstance.maxSegmentationValues}];

    CLY_LOG_D(@"%s segmentation exceeds the SDK segmentation value limit and will be trimmed, target: [%@], keyCount: [%lu], trimmedTo: [%lu], droppedKeyCount: [%lu], droppedKeys: [%@]", __FUNCTION__, explanation, (unsigned long)allKeys.count, (unsigned long)CountlyCommon.sharedInstance.maxSegmentationValues, (unsigned long)excessKeys.count, excessKeys);

    NSMutableDictionary* limitedDict = self.mutableCopy;
    [limitedDict removeObjectsForKeys:excessKeys];

    return limitedDict.copy;
}

- (NSMutableDictionary *) cly_filterSupportedDataTypes
{
    NSMutableDictionary<NSString *, id> *filteredDictionary = [NSMutableDictionary dictionary];
    
    for (NSString *key in self) {
        id value = [self objectForKey:key];
        
        if (CountlyIsSupportedNumber(value) ||
            [value isKindOfClass:[NSString class]] ||
            ([value isKindOfClass:[NSArray class]] && (value = [(NSArray *)value cly_filterSupportedDataTypes]))) {
            [filteredDictionary setObject:value forKey:key];
        } else {
            CLY_LOG_D(@"%s dropping dictionary entry with an unsupported value type, key: [%@], receivedType: [%@]", __FUNCTION__, key, [value class]);
        }
    }
    
    return filteredDictionary.mutableCopy;
}

@end

@implementation NSData (Countly)
- (NSString *)cly_stringUTF8
{
    return [NSString.alloc initWithData:self encoding:NSUTF8StringEncoding];
}
@end
