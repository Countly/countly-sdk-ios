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
            // Negative byear is sent as null on the wire (Android behavior).
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

    CLY_LOG_D(@"%s user details serialized, fields: [%@], customPropertyCount: [%lu]", __FUNCTION__, userDictionary.allKeys, (unsigned long)customAll.count);
    CLY_LOG_D(@"%s serialized user details dictionary value detail, dictionary: [%@]", __FUNCTION__, userDictionary);

    if (userDictionary.count > 0)
        return [userDictionary cly_JSONify];

    return nil;
}

- (void)clearUserDetails
{
    CLY_LOG_D(@"%s user details will be cleared, customPropertyCount: [%lu], modificationCount: [%lu]", __FUNCTION__, (unsigned long)self.customProperties.count, (unsigned long)self.customMods.count);

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
    CLY_LOG_I(@"%s custom user property will be set with a string value, key: [%@], valueLength: [%lu]", __FUNCTION__, key, (unsigned long)value.length);
    CLY_LOG_D(@"%s custom user property string value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self setCustomProperty:key value:value];
}

- (void)set:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s custom user property will be set with a number value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s custom user property number value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self setCustomProperty:key value:value];
}

- (void)set:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s custom user property will be set with a bool value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s custom user property bool value detail, key: [%@], value: [%@]", __FUNCTION__, key, @(value));
    [self setCustomProperty:key value:@(value)];
}

- (void)setCustomProperty:(NSString *)key value:(id)value
{
    if (key == nil || value == nil)
    {
        CLY_LOG_E(@"%s call will be ignored as key or value is nil, keyProvided: [%@]", __FUNCTION__, (key != nil) ? @"YES" : @"NO");
        return;
    }
    if (![CountlyServerConfig.sharedInstance shouldRecordUserProperty:key]) {
        CLY_LOG_D(@"%s custom property key is filtered out by server config user property filter, key: [%@], omitting call", __FUNCTION__, key);
        return;
    }
    if (![self isValidDataType:value]) {
        CLY_LOG_W(@"%s custom property value type is not supported, key: [%@], type: [%@], omitting call",
                  __FUNCTION__, key, NSStringFromClass([value class]));
        CLY_LOG_D(@"%s rejected custom property value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
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
    CLY_LOG_D(@"%s custom user property stored, key: [%@], totalCustomProperties: [%lu]", __FUNCTION__, truncatedKey, (unsigned long)self.customProperties.count);
    CLY_LOG_D(@"%s stored custom user property value detail, key: [%@], value: [%@]", __FUNCTION__, truncatedKey, value);
    // No auto-flush — legacy `set:` preserves pre-existing event-flush timing.
}

- (void)setOnce:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s setOnce will be applied with a string value, key: [%@], valueLength: [%lu]", __FUNCTION__, key, (unsigned long)value.length);
    CLY_LOG_D(@"%s setOnce string value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierSetOnce key:key value:value];
}

- (void)setOnce:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s setOnce will be applied with a number value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s setOnce number value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierSetOnce key:key value:value];
}

- (void)setOnce:(NSString *)key boolValue:(BOOL)value;
{
    CLY_LOG_I(@"%s setOnce will be applied with a bool value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s setOnce bool value detail, key: [%@], value: [%@]", __FUNCTION__, key, @(value));
    [self doModification:kCountlyUDKeyModifierSetOnce key:key value:@(value)];
}

// Legacy custom-only unsetter. Always treats key as a custom user property; does
// not clear predefined fields like `name`/`email`. Preserves pre-`setProperty:`
// wire format. Clear named fields via direct property assignment to NSNull.null.
- (void)unSet:(NSString *)key
{
    CLY_LOG_I(@"%s custom user property will be unset, key: [%@]", __FUNCTION__, key);

    if (key == nil)
    {
        CLY_LOG_E(@"%s unset call will be ignored as key is nil", __FUNCTION__);
        return;
    }

    NSString *truncatedKey = [key cly_truncatedKey:@"unSet"];
    self.customProperties[truncatedKey] = NSNull.null;
    // No auto-flush — legacy `unSet:` preserves pre-existing event-flush timing.
}

- (void)increment:(NSString *)key
{
    CLY_LOG_I(@"%s user property will be incremented by [1], key: [%@]", __FUNCTION__, key);

    [self incrementBy:key value:@1];
}

- (void)incrementBy:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s user property will be incremented, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s increment operand value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierIncrement key:key value:value];
}

- (void)multiply:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s user property will be multiplied, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s multiply operand value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierMultiply key:key value:value];
}

- (void)max:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s max modifier will be applied to user property, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s max operand value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierMax key:key value:value];
}

- (void)min:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s min modifier will be applied to user property, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s min operand value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierMin key:key value:value];}

- (void)push:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s push will be applied with a string value, key: [%@], valueLength: [%lu]", __FUNCTION__, key, (unsigned long)value.length);
    CLY_LOG_D(@"%s push string value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPush key:key value:value];
}

- (void)push:(NSString *)key numberValue:(NSNumber *)value;
{
    CLY_LOG_I(@"%s push will be applied with a number value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s push number value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPush key:key value:value];
}

- (void)push:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s push will be applied with a bool value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s push bool value detail, key: [%@], value: [%@]", __FUNCTION__, key, @(value));
    [self doModification:kCountlyUDKeyModifierPush key:key value:@(value)];
}

- (void)push:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s push will be applied with multiple values, key: [%@], elementCount: [%lu]", __FUNCTION__, key, (unsigned long)value.count);
    CLY_LOG_D(@"%s push array elements detail, key: [%@], values: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPush key:key value:value];
}

- (void)pushUnique:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s pushUnique will be applied with a string value, key: [%@], valueLength: [%lu]", __FUNCTION__, key, (unsigned long)value.length);
    CLY_LOG_D(@"%s pushUnique string value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierAddToSet key:key value:value];
}

- (void)pushUnique:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s pushUnique will be applied with a number value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s pushUnique number value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierAddToSet key:key value:value];
}

- (void)pushUnique:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s pushUnique will be applied with a bool value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s pushUnique bool value detail, key: [%@], value: [%@]", __FUNCTION__, key, @(value));
    [self doModification:kCountlyUDKeyModifierAddToSet key:key value:@(value)];
}

- (void)pushUnique:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s pushUnique will be applied with multiple values, key: [%@], elementCount: [%lu]", __FUNCTION__, key, (unsigned long)value.count);
    CLY_LOG_D(@"%s pushUnique array elements detail, key: [%@], values: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierAddToSet key:key value:value];
}

- (void)pull:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s pull will be applied with a string value, key: [%@], valueLength: [%lu]", __FUNCTION__, key, (unsigned long)value.length);
    CLY_LOG_D(@"%s pull string value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPull key:key value:value];
}

- (void)pull:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s pull will be applied with a number value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s pull number value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPull key:key value:value];
}

- (void)pull:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s pull will be applied with a bool value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_D(@"%s pull bool value detail, key: [%@], value: [%@]", __FUNCTION__, key, @(value));
    [self doModification:kCountlyUDKeyModifierPull key:key value:@(value)];
}

- (void)pull:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s pull will be applied with multiple values, key: [%@], elementCount: [%lu]", __FUNCTION__, key, (unsigned long)value.count);
    CLY_LOG_D(@"%s pull array elements detail, key: [%@], values: [%@]", __FUNCTION__, key, value);
    [self doModification:kCountlyUDKeyModifierPull key:key value:value];
}

- (void)save
{
    CLY_LOG_I(@"%s user details will be saved", __FUNCTION__);

    if (!CountlyCommon.sharedInstance.hasStarted)
    {
        CLY_LOG_W(@"%s user details save will be ignored as SDK is not initialized yet", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForUserDetails)
    {
        CLY_LOG_D(@"%s no consent for user details, save will be skipped", __FUNCTION__);
        return;
    }

    // Returns early if user properties values are not changed
    if (![self hasUnsyncedChanges])
    {
        CLY_LOG_D(@"%s no unsynced user details changes, save will be skipped", __FUNCTION__);
        return;
    }
    
    [CountlyConnectionManager.sharedInstance sendEvents];

    NSString* userDetails = [self serializedUserDetails];
    if (userDetails)
    {
        CLY_LOG_D(@"%s serialized user details request will be sent, payloadLength: [%lu]", __FUNCTION__, (unsigned long)userDetails.length);
        CLY_LOG_D(@"%s serialized user details payload detail, payload: [%@]", __FUNCTION__, userDetails);
        [CountlyConnectionManager.sharedInstance sendUserDetails:userDetails];
    }

    if (self.pictureLocalPath && !self.pictureURL)
    {
        CLY_LOG_D(@"%s local picture path will be sent in a separate request, valueType: [%@]", __FUNCTION__, NSStringFromClass([self.pictureLocalPath class]));
        CLY_LOG_D(@"%s local picture path value detail, value: [%@]", __FUNCTION__, self.pictureLocalPath);
        [CountlyConnectionManager.sharedInstance sendUserDetails:[@{kCountlyLocalPicturePath: self.pictureLocalPath} cly_JSONify]];
    }

    [self clearUserDetails];
}

- (void)doModification:(NSString *)mod key:(NSString *)key  value:(id)value {
    if (value == nil)
    {
        CLY_LOG_W(@"%s modification will be ignored as value is nil, modifier: [%@], key: [%@]", __FUNCTION__, mod, key);
        return;
    }
    if (![self isValidDataType:value]) {
        CLY_LOG_W(@"%s modifier value type is not supported, modifier: [%@], key: [%@], type: [%@], omitting call",
                  __FUNCTION__, mod, key, NSStringFromClass([value class]));
        CLY_LOG_D(@"%s rejected modifier value detail, modifier: [%@], key: [%@], value: [%@]", __FUNCTION__, mod, key, value);
        return;
    }
    if (![CountlyServerConfig.sharedInstance shouldRecordUserProperty:key]) {
        CLY_LOG_D(@"%s modifier key is filtered out by server config user property filter, key: [%@], omitting call", __FUNCTION__, key);
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
    CLY_LOG_D(@"%s modification stored, modifier: [%@], key: [%@], totalModifications: [%lu]", __FUNCTION__, mod, truncatedKey, (unsigned long)self.customMods.count);
    CLY_LOG_D(@"%s stored modification value detail, modifier: [%@], key: [%@], value: [%@]", __FUNCTION__, mod, truncatedKey, value);
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
        CLY_LOG_W(@"%s call will be ignored as no data was provided", __FUNCTION__);
        return;
    }

    CLY_LOG_I(@"%s user properties will be applied, keys: [%@], count: [%lu]", __FUNCTION__, data.allKeys, (unsigned long)data.count);
    CLY_LOG_D(@"%s user properties value detail, data: [%@]", __FUNCTION__, data);

    NSString* truncatedLog = [NSString stringWithFormat:@"%s",__FUNCTION__];
    BOOL anyChange = NO;

    for (NSString *key in data) {
        id value = data[key];

        if (value == nil || value == [NSNull null]) {
            CLY_LOG_D(@"%s provided value is null, key: [%@], skipping this entry", __FUNCTION__, key);
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
                if ([self assignNamedField:key value:value])
                    anyChange = YES;
                break;
            }
        }

        if (!isNamed) {
            if (![CountlyServerConfig.sharedInstance shouldRecordUserProperty:key]) {
                CLY_LOG_D(@"%s key is filtered out by server config user property filter while setting properties, key: [%@], omitting entry", __FUNCTION__, key);
                continue;
            }
            NSString* truncatedKey = [[key description] cly_truncatedKey:truncatedLog];
            if ([self isValidDataType:value]) {
                self.customProperties[truncatedKey] = value;
                anyChange = YES;
            } else {
                CLY_LOG_D(@"%s provided value type is not supported, key: [%@], type: [%@], omitting entry", __FUNCTION__,
                      key, NSStringFromClass([value class]));
                CLY_LOG_D(@"%s rejected user property entry value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);
            }
        }
    }

    CLY_LOG_D(@"%s user properties processing finished, anyChange: [%@]", __FUNCTION__, anyChange ? @"YES" : @"NO");
    if (anyChange) [self userPropertiesChanged];
}

- (void)serializeStringField:(id)field
                         key:(NSString *)key
                 explanation:(NSString *)explanation
                        into:(NSMutableDictionary *)userDictionary
                     picture:(BOOL)isPicture
{
    if (!field) return;

    CLY_LOG_D(@"%s user details string field value detail, explanation: [%@], key: [%@], value: [%@]", __FUNCTION__, explanation, key, field);

    if (![field isKindOfClass:NSString.class]) {
        // NSNull — explicit clear.
        userDictionary[key] = field;
        return;
    }

    NSString *str = (NSString *)field;
    // Empty strings are sent to the server as-is: the server clears a field
    // on "" but ignores null, so converting "" to null (Android behavior)
    // would defeat the clear.
    userDictionary[key] = isPicture ? [str cly_truncatedPictureValue:explanation]
                                    : [str cly_truncatedValue:explanation];
}

// Returns YES when the field was actually assigned, NO when the value was
// rejected — so the caller only marks a change (and flushes events) for
// values that will end up in the next user-details request.
- (BOOL)assignNamedField:(NSString *)key value:(id)value {
    BOOL isNull = (value == [NSNull null]);
    id stringOrNull = isNull ? NSNull.null : [value description];

    CLY_LOG_D(@"%s predefined user property will be assigned, key: [%@], isNull: [%@]", __FUNCTION__, key, isNull ? @"YES" : @"NO");
    CLY_LOG_D(@"%s predefined user property value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);

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
            // drop the path with a warning if the file isn't readable.
            if (path.length > 0 && ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
                CLY_LOG_W(@"%s provided picture path file can not be opened, pathLength: [%lu], value will be dropped", __FUNCTION__, (unsigned long)path.length);
                CLY_LOG_D(@"%s unreadable picture path value detail, path: [%@]", __FUNCTION__, path);
                self.pictureLocalPath = nil;
            } else {
                self.pictureLocalPath = path;
            }
        }
    } else if ([key isEqualToString:kCountlyUDKeyBirthyear]) {
        if (isNull) {
            self.birthYear = NSNull.null;
        } else {
            NSNumber *parsed = nil;
            if ([value isKindOfClass:[NSNumber class]]) {
                parsed = (NSNumber *)value;
            } else if ([value isKindOfClass:[NSString class]]) {
                NSNumberFormatter *formatter = [NSNumberFormatter new];
                parsed = [formatter numberFromString:(NSString *)value];
                if (!parsed) {
                    CLY_LOG_W(@"%s provided byear value can not be parsed as a number, valueLength: [%lu]", __FUNCTION__, (unsigned long)((NSString *)value).length);
                    CLY_LOG_D(@"%s unparsable byear value detail, value: [%@]", __FUNCTION__, value);
                    return NO;
                }
            } else {
                return NO;
            }

            self.birthYear = parsed;
        }
    } else {
        return NO;
    }

    return YES;
}

- (void)filterAndLimitUserProperties:(NSMutableDictionary *)properties
{
    NSInteger limit = CountlyServerConfig.sharedInstance.userPropertyCacheLimit;
    BOOL shouldApplyLimit = limit > 0;
    NSInteger kept = 0;

    for (NSString *key in properties.allKeys) {
        if (![CountlyServerConfig.sharedInstance shouldRecordUserProperty:key]) {
            CLY_LOG_D(@"%s user property is filtered out by server config user property filter, key: [%@], removing", __FUNCTION__, key);
            [properties removeObjectForKey:key];
        }
        else if (shouldApplyLimit && ++kept > limit) {
            CLY_LOG_D(@"%s user property will be removed due to cache limit [%ld], key: [%@]", __FUNCTION__, (long)limit, key);
            [properties removeObjectForKey:key];
        }
    }
}

// when user properties change, flush any
// pending events first so they reach the server before the next user-details request.
- (void)userPropertiesChanged
{
    if (!CountlyCommon.sharedInstance.hasStarted)
    {
        CLY_LOG_D(@"%s SDK is not started yet, pending events will not be flushed", __FUNCTION__);
        return;
    }
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
    CLY_LOG_I(@"%s user property will be set, key: [%@], valueType: [%@]", __FUNCTION__, key, (value != nil) ? NSStringFromClass([value class]) : @"nil");
    CLY_LOG_D(@"%s single user property value detail, key: [%@], value: [%@]", __FUNCTION__, key, value);

    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (key != nil && value != nil) {
        data[key] = value;
    }

    [self setPropertiesInternal:data];
}

// Provide a map of user properties to set.
// Those can be either custom user properties or predefined user properties
- (void)setProperties:(NSDictionary<NSString *,  NSObject *> *)data {
    if (data == nil) {
        CLY_LOG_E(@"%s call will be ignored as provided data is nil", __FUNCTION__);
        return;
    }

    [self setPropertiesInternal:data];
}

- (void)clear {
    CLY_LOG_I(@"%s all user details and modifications will be cleared", __FUNCTION__);
    [self clearUserDetails];
}
@end
