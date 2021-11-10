// CountlyUserDetails.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyUserDetails ()
@property (nonatomic) NSMutableDictionary* modifications;
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
        self.modifications = NSMutableDictionary.new;
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

    if ([self.custom isKindOfClass:NSDictionary.class])
        self.custom = [((NSDictionary *)self.custom) cly_truncated:@"User details custom dictionary"];

    if (self.custom)
        userDictionary[kCountlyUDKeyCustom] = self.custom;

    if (userDictionary.allKeys.count)
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

    [self.modifications removeAllObjects];
}

#pragma mark -

- (void)set:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    self.modifications[key] = value.copy;
}

- (void)set:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    self.modifications[key] = value.copy;
}

- (void)set:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);

    self.modifications[key] = @(value);
}

- (void)setOnce:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierSetOnce: value.copy};
}

- (void)setOnce:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierSetOnce: value.copy};
}

- (void)setOnce:(NSString *)key boolValue:(BOOL)value;
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);

    self.modifications[key] = @{kCountlyUDKeyModifierSetOnce: @(value)};
}

- (void)unSet:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);

    self.modifications[key] = NSNull.null;
}

- (void)increment:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);

    [self incrementBy:key value:@1];
}

- (void)incrementBy:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierIncrement: value};
}

- (void)multiply:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierMultiply: value};
}

- (void)max:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierMax: value};
}

- (void)min:(NSString *)key value:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierMin: value};
}

- (void)push:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierPush: value.copy};
}

- (void)push:(NSString *)key numberValue:(NSNumber *)value;
{
    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierPush: value.copy};
}

- (void)push:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);

    self.modifications[key] = @{kCountlyUDKeyModifierPush: @(value)};
}

- (void)push:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierPush: value.copy};
}

- (void)pushUnique:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierAddToSet: value.copy};
}

- (void)pushUnique:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierAddToSet: value.copy};
}

- (void)pushUnique:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);

    self.modifications[key] = @{kCountlyUDKeyModifierAddToSet: @(value)};
}

- (void)pushUnique:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierAddToSet: value.copy};
}

- (void)pull:(NSString *)key value:(NSString *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierPull: value.copy};
}

- (void)pull:(NSString *)key numberValue:(NSNumber *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierPull: value.copy};
}

- (void)pull:(NSString *)key boolValue:(BOOL)value
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, key, value);

    self.modifications[key] = @{kCountlyUDKeyModifierPull: @(value)};
}

- (void)pull:(NSString *)key values:(NSArray *)value
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, key, value);

    if (!value)
    {
        CLY_LOG_W(@"%s call will be ignored as value is nil!", __FUNCTION__);
        return;
    }

    self.modifications[key] = @{kCountlyUDKeyModifierPull: value.copy};
}

- (void)save
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    if (!CountlyCommon.sharedInstance.hasStarted)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForUserDetails)
        return;

    NSString* userDetails = [self serializedUserDetails];
    if (userDetails)
        [CountlyConnectionManager.sharedInstance sendUserDetails:userDetails];

    if (self.pictureLocalPath && !self.pictureURL)
        [CountlyConnectionManager.sharedInstance sendUserDetails:[@{kCountlyLocalPicturePath: self.pictureLocalPath} cly_JSONify]];

    if (self.modifications.count)
        [CountlyConnectionManager.sharedInstance sendUserDetails:[@{kCountlyUDKeyCustom: self.modifications} cly_JSONify]];

    [self clearUserDetails];
}

@end
