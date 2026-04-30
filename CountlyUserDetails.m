// CountlyUserDetails.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyUserDetails ()
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
NSString* const kCountlyUDKeyPicturePath   = @"picturePath";

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
    kCountlyUDKeyPicturePath,
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
        self.customMods = NSMutableDictionary.new;
        self.customProperties = NSMutableDictionary.new;
    }

    return self;
}

- (NSString *)serializedUserDetails
{
    NSMutableDictionary* userDictionary = NSMutableDictionary.new;
    [self serializeStringField:self.name key:kCountlyUDKeyName explanation:@"User details name" into:userDictionary picture:NO];
    [self serializeStringField:self.username key:kCountlyUDKeyUsername explanation:@"User details username" into:userDictionary picture:NO];
    [self serializeStringField:self.email key:kCountlyUDKeyEmail explanation:@"User details email" into:userDictionary picture:NO];
    [self serializeStringField:self.organization key:kCountlyUDKeyOrganization explanation:@"User details organization" into:userDictionary picture:NO];
    [self serializeStringField:self.phone key:kCountlyUDKeyPhone explanation:@"User details phone" into:userDictionary picture:NO];
    [self serializeStringField:self.gender key:kCountlyUDKeyGender explanation:@"User details gender" into:userDictionary picture:NO];
    [self serializeStringField:self.pictureURL key:kCountlyUDKeyPicture explanation:@"User details picture" into:userDictionary picture:YES];

    if (self.birthYear) {
        if ([self.birthYear isKindOfClass:NSNumber.class] && ((NSNumber *)self.birthYear).integerValue < 0) {
            // Negative byear means "clear on server" — match Android semantics.
            userDictionary[kCountlyUDKeyBirthyear] = NSNull.null;
        } else {
            userDictionary[kCountlyUDKeyBirthyear] = self.birthYear;
        }
    }

    NSMutableDictionary* customAll = NSMutableDictionary.new;
    
    if ([self.custom isKindOfClass:NSDictionary.class])
    {
        NSMutableDictionary *customMutable = [((NSDictionary *)self.custom) mutableCopy];
        [self filterAndLimitUserProperties:customMutable];
        NSDictionary* customTruncated = [customMutable cly_truncated:@"User details custom dictionary"];
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
    
    return userDetailsChanged || self.customProperties.count > 0 || self.customMods.count > 0;
}



#pragma mark -

// Legacy custom-only setter. Treats every key as a custom user property — never
// routes to predefined fields like `name`/`email`/etc. This preserves the
// pre-`setProperty:` wire format. Use `-setProperty:value:` for the named-aware path.
- (void)set:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self setCustomProperty:key value:value];
}

- (void)set:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);
    [self setCustomProperty:key value:value];
}

- (void)set:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);
    [self setCustomProperty:key value:@(value)];
}

- (void)setCustomProperty:(NSString *)key value:(id)value
{
    if (key == nil || value == nil) return;
    if (![CountlyServerConfig.sharedInstance shouldRecordUserProperty:key]) {
        CLY_LOG_D(@"%s key [%@] is filtered out by user property filter, omitting call", __FUNCTION__, key);
        return;
    }
    if (![self isValidDataType:value]) {
        CLY_LOG_D(@"%s unsupported type for key [%@], type [%@], omitting call",
                  __FUNCTION__, key, NSStringFromClass([value class]));
        return;
    }
    NSString* truncatedLog = [NSString stringWithFormat:@"%s",__FUNCTION__];
    if ([value isKindOfClass:[NSString class]]) {
        BOOL isPicture = [key isEqualToString:kCountlyUDKeyPicture] || [key isEqualToString:kCountlyUDKeyPicturePath];
        value = isPicture ? [(NSString *)value cly_truncatedPictureValue:truncatedLog]
                          : [(NSString *)value cly_truncatedValue:truncatedLog];
    }
    NSString *truncatedKey = [key cly_truncatedKey:truncatedLog];
    self.customProperties[truncatedKey] = value;
    // No auto-flush — legacy `set:` preserves pre-existing event-flush timing.
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

// Legacy custom-only unsetter. Always treats key as a custom user property; does
// not clear predefined fields like `name`/`email`. Preserves pre-`setProperty:`
// wire format. Clear named fields via direct property assignment to NSNull.null.
- (void)unSet:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);
    if (key == nil) return;

    NSString *truncatedKey = [key cly_truncatedKey:@"unSet"];
    self.customProperties[truncatedKey] = NSNull.null;
    // No auto-flush — legacy `unSet:` preserves pre-existing event-flush timing.
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
    if (![self isValidDataType:value]) {
        CLY_LOG_W(@"%s unsupported value type for key [%@] mod [%@], type [%@], omitting call",
                  __FUNCTION__, key, mod, NSStringFromClass([value class]));
        return;
    }
    if (![CountlyServerConfig.sharedInstance shouldRecordUserProperty:key]) {
        CLY_LOG_D(@"%s key [%@] is filtered out by user property filter, omitting call", __FUNCTION__, key);
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
        self.customMods[truncatedKey] = @{mod: value};
    } else if (self.customMods[truncatedKey] && self.customMods[truncatedKey][mod]) {
        id existing = self.customMods[truncatedKey][mod];
        NSMutableArray *array = [existing isKindOfClass:[NSArray class]] ? [existing mutableCopy] : [NSMutableArray arrayWithObject:existing];
        if ([value isKindOfClass:[NSArray class]]) {
            [array addObjectsFromArray:value];
        } else {
            [array addObject:value];
        }
        self.customMods[truncatedKey] = @{mod: array};
    } else {
        self.customMods[truncatedKey] = @{mod: value};
    }
    // Note: legacy modifier methods (setOnce/push/pull/etc.) deliberately do
    // NOT auto-flush events — preserves pre-existing request-timing behavior
    // for callers still on the legacy API. Auto-flush is opt-in via the new
    // -setProperty:/setProperties: path.
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

    NSString* truncatedLog = [NSString stringWithFormat:@"%s",__FUNCTION__];
    BOOL anyChange = NO;

    for (NSString *key in data) {
        id value = data[key];

        if (value == nil || value == [NSNull null]) {
            CLY_LOG_W(@"%s provided value for key [%@] is 'null'", __FUNCTION__, key);
            continue;
        }

        if ([value isKindOfClass:[NSString class]]) {
            BOOL isPicture = [key isEqualToString:kCountlyUDKeyPicture] || [key isEqualToString:kCountlyUDKeyPicturePath];
            value = isPicture ? [[value description] cly_truncatedPictureValue:truncatedLog]
                              : [[value description] cly_truncatedValue:truncatedLog];
        }

        BOOL isNamed = NO;
        for (NSUInteger i = 0; i < kCountlyUDNamedFieldsCount; i++) {
            if ([kCountlyUDNamedFields[i] isEqualToString:key]) {
                isNamed = YES;
                [self assignNamedField:key value:value];
                anyChange = YES;
                break;
            }
        }

        if (!isNamed) {
            if (![CountlyServerConfig.sharedInstance shouldRecordUserProperty:key]) {
                CLY_LOG_D(@"%s key [%@] is filtered out by user property filter, omitting call", __FUNCTION__, key);
                continue;
            }
            NSString* truncatedKey = [[key description] cly_truncatedKey:truncatedLog];
            if ([self isValidDataType:value]) {
                self.customProperties[truncatedKey] = value;
                anyChange = YES;
            } else {
                CLY_LOG_D(@"%s provided an unsupported type for key: [%@], value: [%@], type: [%@], omitting call",__FUNCTION__,
                      key, value, NSStringFromClass([value class]));
            }
        }
    }

    if (anyChange) [self userPropertiesChanged];
}

- (void)serializeStringField:(id)field
                         key:(NSString *)key
                 explanation:(NSString *)explanation
                        into:(NSMutableDictionary *)userDictionary
                     picture:(BOOL)isPicture
{
    if (!field) return;

    if (![field isKindOfClass:NSString.class]) {
        // NSNull — explicit clear.
        userDictionary[key] = field;
        return;
    }

    NSString *str = (NSString *)field;
    if (str.length == 0) {
        // Empty string means "clear on server" — match Android semantics.
        userDictionary[key] = NSNull.null;
        return;
    }

    userDictionary[key] = isPicture ? [str cly_truncatedPictureValue:explanation]
                                    : [str cly_truncatedValue:explanation];
}

- (void)assignNamedField:(NSString *)key value:(id)value {
    BOOL isNull = (value == [NSNull null]);
    id stringOrNull = isNull ? NSNull.null : [value description];

    if ([key isEqualToString:kCountlyUDKeyName]) {
        self.name = stringOrNull;
    } else if ([key isEqualToString:kCountlyUDKeyUsername]) {
        self.username = stringOrNull;
    } else if ([key isEqualToString:kCountlyUDKeyEmail]) {
        self.email = stringOrNull;
    } else if ([key isEqualToString:kCountlyUDKeyOrganization]) {
        self.organization = stringOrNull;
    } else if ([key isEqualToString:kCountlyUDKeyPhone]) {
        self.phone = stringOrNull;
    } else if ([key isEqualToString:kCountlyUDKeyGender]) {
        self.gender = stringOrNull;
    } else if ([key isEqualToString:kCountlyUDKeyPicture]) {
        self.pictureURL = stringOrNull;
    } else if ([key isEqualToString:kCountlyUDKeyPicturePath]) {
        if (isNull) {
            self.pictureLocalPath = nil;
        } else {
            NSString *path = [value description];
            // Match Android: drop the path with a warning if the file isn't readable.
            if (path.length > 0 && ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
                CLY_LOG_W(@"%s provided picture path file [%@] can not be opened", __FUNCTION__, path);
                self.pictureLocalPath = nil;
            } else {
                self.pictureLocalPath = path;
            }
        }
    } else if ([key isEqualToString:kCountlyUDKeyBirthyear]) {
        if (isNull) {
            self.birthYear = NSNull.null;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            self.birthYear = (NSNumber *)value;
        } else if ([value isKindOfClass:[NSString class]]) {
            NSNumberFormatter *formatter = [NSNumberFormatter new];
            NSNumber *parsed = [formatter numberFromString:(NSString *)value];
            if (parsed) {
                self.birthYear = parsed;
            } else {
                CLY_LOG_W(@"%s incorrect byear number format: %@", __FUNCTION__, value);
            }
        }
    }
}

- (void)filterAndLimitUserProperties:(NSMutableDictionary *)properties
{
    NSInteger limit = CountlyServerConfig.sharedInstance.userPropertyCacheLimit;
    BOOL shouldApplyLimit = limit > 0;
    NSInteger kept = 0;

    for (NSString *key in properties.allKeys) {
        if (![CountlyServerConfig.sharedInstance shouldRecordUserProperty:key]) {
            CLY_LOG_D(@"Filtering out user property '%@' by server config user property filter", key);
            [properties removeObjectForKey:key];
        }
        else if (shouldApplyLimit && ++kept > limit) {
            CLY_LOG_D(@"Removing user property '%@' due to cache limit (%ld)", key, (long)limit);
            [properties removeObjectForKey:key];
        }
    }
}

// Match Android's `onUserPropertiesChanged`: when user properties change, flush any
// pending events first so they reach the server before the next user-details request.
- (void)userPropertiesChanged
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return;
    [CountlyConnectionManager.sharedInstance sendEvents];
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
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (key != nil && value != nil) {
        data[key] = value;
    }

    [self setPropertiesInternal:data];
}

// Provide a map of user properties to set.
// Those can be either custom user properties or predefined user properties
- (void)setProperties:(NSDictionary<NSString *,  NSObject *> *)data {
    CLY_LOG_I(@"%s", __FUNCTION__);

    if (data == nil) {
        CLY_LOG_W(@"%s provided data can not be 'null'", __FUNCTION__);
        return;
    }

    [self setPropertiesInternal:data];
}

- (void)clear {
    CLY_LOG_I(@"%s", __FUNCTION__);
    [self clearUserDetails];
}
@end
