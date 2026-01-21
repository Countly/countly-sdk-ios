// CountlyUserDetails.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyUserDetails ()
@property (nonatomic) NSMutableDictionary* predefined;
@property (nonatomic) NSMutableDictionary* customMods;
@property (nonatomic) NSMutableDictionary* customProperties;

- (BOOL)isValidDataType:(id) value;
@end

NSString* const kCountlyLocalPicturePath = @"kCountlyLocalPicturePath";

NSString* const kCountlyUDKeyName          = @"name";
NSString* const kCountlyUDKeyUsername      = @"username";
NSString* const kCountlyUDKeyEmail         = @"email";
NSString* const kCountlyUDKeyOrganization  = @"organization";
NSString* const kCountlyUDKeyPhone         = @"phone";
NSString* const kCountlyUDKeyGender        = @"gender";
NSString* const kCountlyUDKeyPicture       = @"picture";
NSString* const kCountlyUDKeyBirthyear     = @"byear";
NSString* const kCountlyUDKeyCustom        = @"custom";

NSString* const kCountlyUDKeyModifierSetOnce    = @"$setOnce";
NSString* const kCountlyUDKeyModifierIncrement  = @"$inc";
NSString* const kCountlyUDKeyModifierMultiply   = @"$mul";
NSString* const kCountlyUDKeyModifierMax        = @"$max";
NSString* const kCountlyUDKeyModifierMin        = @"$min";
NSString* const kCountlyUDKeyModifierPush       = @"$push";
NSString* const kCountlyUDKeyModifierAddToSet   = @"$addToSet";
NSString* const kCountlyUDKeyModifierPull       = @"$pull";

static NSString* const kCountlyUDNamedFields[] = {
    kCountlyUDKeyName,
    kCountlyUDKeyUsername,
    kCountlyUDKeyEmail,
    kCountlyUDKeyOrganization,
    kCountlyUDKeyPhone,
    kCountlyUDKeyGender,
    kCountlyUDKeyPicture,
    kCountlyUDKeyBirthyear
};

static const NSUInteger kCountlyUDNamedFieldsCount = sizeof(kCountlyUDNamedFields) / sizeof(kCountlyUDNamedFields[0]);

@implementation CountlyUserDetails

+ (instancetype)sharedInstance
{
    static CountlyUserDetails *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.predefined = NSMutableDictionary.new;
        self.customMods = NSMutableDictionary.new;
        self.customProperties = NSMutableDictionary.new;
    }

    return self;
}

- (NSString *)serializedUserDetails
{
    NSMutableDictionary* userDictionary = NSMutableDictionary.new;
    if (self.name)
        userDictionary[kCountlyUDKeyName] =
                ![self.name isKindOfClass:NSString.class] ? self.name :
                        [(NSString *)self.name cly_truncatedValue:@"User details name"];

    if (self.username)
        userDictionary[kCountlyUDKeyUsername] =
                ![self.username isKindOfClass:NSString.class] ? self.username :
                        [(NSString *)self.username cly_truncatedValue:@"User details username"];

    if (self.email)
        userDictionary[kCountlyUDKeyEmail] =
                ![self.email isKindOfClass:NSString.class] ? self.email :
                        [(NSString *)self.email cly_truncatedValue:@"User details email"];

    if (self.organization)
        userDictionary[kCountlyUDKeyOrganization] =
                ![self.organization isKindOfClass:NSString.class] ? self.organization :
                        [(NSString *)self.organization cly_truncatedValue:@"User details organization"];

    if (self.phone)
        userDictionary[kCountlyUDKeyPhone] =
                ![self.phone isKindOfClass:NSString.class] ? self.phone :
                        [(NSString *)self.phone cly_truncatedValue:@"User details phone"];

    if (self.gender)
        userDictionary[kCountlyUDKeyGender] =
                ![self.gender isKindOfClass:NSString.class] ? self.gender :
                        [(NSString *)self.gender cly_truncatedValue:@"User details gender"];

    if (self.pictureURL)
        userDictionary[kCountlyUDKeyPicture] = self.pictureURL;

    if (self.birthYear)
        userDictionary[kCountlyUDKeyBirthyear] = self.birthYear;

    NSMutableDictionary* customAll = NSMutableDictionary.new;
    
    if ([self.custom isKindOfClass:NSDictionary.class])
    {
        NSDictionary* customTruncated = [((NSDictionary *)self.custom) cly_truncated:@"User details custom dictionary"];
        [customAll addEntriesFromDictionary:[customTruncated cly_limited:@"User details custom dictionary"]];
    }
    
    if(self.customProperties.count > 0){
        [customAll addEntriesFromDictionary:[self.customProperties cly_limited:@"User details custom dictionary"]];
    }
    
    if(self.customMods.count > 0){
        [customAll addEntriesFromDictionary:self.customMods];
    }

    if (customAll.count > 0)
        userDictionary[kCountlyUDKeyCustom] = customAll;

    if (userDictionary.count > 0)
        return [userDictionary cly_JSONify];

    return nil;
}

- (void)clearUserDetails
{
    self.name = nil;
    self.username = nil;
    self.email = nil;
    self.organization = nil;
    self.phone = nil;
    self.gender = nil;
    self.pictureURL = nil;
    self.pictureLocalPath = nil;
    self.birthYear = nil;
    self.custom = nil;

    [self.predefined removeAllObjects];
    [self.customMods removeAllObjects];
    [self.customProperties removeAllObjects];
}

- (BOOL)hasUnsyncedChanges
{
    NSArray<NSNumber *> *userDetailsFlags = @[
        @(self.name != nil),
        @(self.username != nil),
        @(self.email != nil),
        @(self.organization != nil),
        @(self.phone != nil),
        @(self.gender != nil),
        @(self.pictureURL != nil),
        @(self.pictureLocalPath != nil),
        @(self.birthYear != nil),
        @(self.custom != nil)
    ];
    
    __block BOOL userDetailsChanged = NO;
    [userDetailsFlags enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.boolValue) {
            userDetailsChanged = YES;
            *stop = YES;
        }
    }];
    
    return userDetailsChanged || self.predefined.count > 0 || self.customProperties.count > 0 || self.customMods.count > 0;
}



#pragma mark -

- (void)set:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self setProperty:key value:value];
}

- (void)set:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self setProperty:key value:value];
}

- (void)set:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);
    [self setProperty:key value:@(value)];
}

- (void)setOnce:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierSetOnce key:key value:value];
}

- (void)setOnce:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierSetOnce key:key value:value];
}

- (void)setOnce:(NSString *)key boolValue:(BOOL)value;
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierSetOnce key:key value:@(value)];
}

- (void)unSet:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);
    if(key != nil){
        if(self.customProperties[key]) {
            self.customProperties[key] = NSNull.null;
        }
        
        if(self.customMods[key]) {
            self.customMods[key] = NSNull.null;
        }
        
        if(self.predefined[key]) {
            self.predefined[key] = NSNull.null;
        }
    }
}

- (void)increment:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);

    [self incrementBy:key value:@1];
}

- (void)incrementBy:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierIncrement key:key value:value];
}

- (void)multiply:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierMultiply key:key value:value];
}

- (void)max:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierMax key:key value:value];
}

- (void)min:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierMin key:key value:value];}

- (void)push:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPush key:key value:value];
}

- (void)push:(NSString *)key numberValue:(NSNumber *)value;
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPush key:key value:value];
}

- (void)push:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPush key:key value:@(value)];
}

- (void)push:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPush key:key value:value];
}

- (void)pushUnique:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierAddToSet key:key value:value];
}

- (void)pushUnique:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierAddToSet key:key value:value];
}

- (void)pushUnique:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierAddToSet key:key value:@(value)];
}

- (void)pushUnique:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierAddToSet key:key value:value];
}

- (void)pull:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPull key:key value:value];
}

- (void)pull:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPull key:key value:value];
}

- (void)pull:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPull key:key value:@(value)];
}

- (void)pull:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPull key:key value:value];
}

- (void)save
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    if (!CountlyCommon.sharedInstance.hasStarted)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForUserDetails)
        return;

    // Returns early if user properties values are not changed
    if (![self hasUnsyncedChanges])
        return;
    
    [CountlyConnectionManager.sharedInstance sendEvents];

    NSString* userDetails = [self serializedUserDetails];
    if (userDetails)
        [CountlyConnectionManager.sharedInstance sendUserDetails:userDetails];

    if (self.pictureLocalPath && !self.pictureURL)
        [CountlyConnectionManager.sharedInstance sendUserDetails:[@{kCountlyLocalPicturePath: self.pictureLocalPath} cly_JSONify]];

    [self clearUserDetails];
}

- (void)doModification:(NSString *)mod key:(NSString *)key  value:(id)value {
    if (value == nil)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }
    NSString* truncatedLog = [NSString stringWithFormat:@"%s",__FUNCTION__];
    
    // If the value is NSString, apply truncation rules
    if ([value isKindOfClass:[NSString class]]) {
        value = [[value description] cly_truncatedValue:truncatedLog];
    }
    
    NSString* truncatedKey = [[key description] cly_truncatedKey:truncatedLog];
    if (![mod isEqualToString:@"$pull"] &&
        ![mod isEqualToString:@"$push"] &&
        ![mod isEqualToString:@"$addToSet"]) {
        self.customMods[truncatedKey] = @{mod: value};;
    } else {
        if(self.customMods[truncatedKey] && self.customMods[truncatedKey][mod]){
            NSMutableArray *array = [self.customMods[key][mod] mutableCopy];
            [array addObject:value];
            self.customMods[truncatedKey] = @{mod: array};
        } else {
            self.customMods[truncatedKey] = @{mod: value};
        }
    }
    
}

/**
 * This mainly performs the filtering of provided values.
 * This single call is used for both predefined properties and custom user properties.
 *
 * @param data Dictionary of user properties
 */
- (void)setPropertiesInternal:(NSDictionary<NSString *, id> *)data {
    if (data.count == 0) {
        CLY_LOG_I(@"%s no data was provided", __FUNCTION__);
        return;
    }
    
    for (NSString *key in data) {
        id value = data[key];
        
        if (value == nil || value == [NSNull null]) {
            CLY_LOG_W(@"%s provided value for key [%@] is 'null'", __FUNCTION__, key);
            continue;
        }
    
        NSString* truncatedLog = [NSString stringWithFormat:@"%s",__FUNCTION__];
        if ([value isKindOfClass:[NSString class]]) {
            value = [[value description] cly_truncatedValue:truncatedLog];
        }
        
        BOOL isNamed = NO;
        
        for (NSUInteger i = 0; i < kCountlyUDNamedFieldsCount; i++) {
            if ([kCountlyUDNamedFields[i] isEqualToString:key]) {
                isNamed = YES;
                self.predefined[key] = [value description];
                break;
            }
        }
        
        // Handle custom fields
        if (!isNamed) {
            NSString* truncatedKey = [[key description] cly_truncatedKey:truncatedLog];
            if ([self isValidDataType:value]) {
                self.customProperties[truncatedKey] = value;
            } else {
                CLY_LOG_D(@"%s provided an unsupported type for key: [%@], value: [%@], type: [%@], omitting call",__FUNCTION__,
                      key, value, NSStringFromClass([value class]));
            }
        }
    }
}


- (BOOL)isValidDataType:(id) value {
    if ([value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSString class]] ||
        ([value isKindOfClass:[NSArray class]] && (value = [(NSArray *)value cly_filterSupportedDataTypes]))) {
        return YES;
    }
    return NO;
}

// Set a single user property. It can be either a custom one or one of the predefined ones.
- (void)setProperty:(NSString *)key value:(id)value {
    NSLog(@"[UserProfile] Calling 'setProperty'");

    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (key != nil && value != nil) {
        data[key] = value;
    }
    
    [self setPropertiesInternal:data];
}

// Provide a map of user properties to set.
// Those can be either custom user properties or predefined user properties
- (void)setProperties:(NSDictionary<NSString *,  NSObject *> *)data {
    NSLog(@"[UserProfile] Calling 'setProperties'");

    if (data == nil) {
        NSLog(@"[UserProfile] Provided data can not be 'null'");
        return;
    }
    
    [self setPropertiesInternal:data];
}
@end
