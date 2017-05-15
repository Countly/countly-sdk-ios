// CountlyUserDetails.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyUserDetails ()
@property (nonatomic, strong) NSMutableDictionary* modifications;
@end

NSString* const kCountlyLocalPicturePath = @"kCountlyLocalPicturePath";

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

- (void)recordUserDetails
{
    [self save];
}

- (NSString *)serializedUserDetails
{
    NSMutableDictionary* userDictionary = NSMutableDictionary.new;
    if (self.name)
        userDictionary[@"name"] = self.name;
    if (self.username)
        userDictionary[@"username"] = self.username;
    if (self.email)
        userDictionary[@"email"] = self.email;
    if (self.organization)
        userDictionary[@"organization"] = self.organization;
    if (self.phone)
        userDictionary[@"phone"] = self.phone;
    if (self.gender)
        userDictionary[@"gender"] = self.gender;
    if (self.pictureURL)
        userDictionary[@"picture"] = self.pictureURL;
    if (self.birthYear)
        userDictionary[@"byear"] = self.birthYear;
    if (self.custom)
        userDictionary[@"custom"] = self.custom;

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
    self.modifications[key] = value;
}

- (void)setOnce:(NSString *)key value:(NSString *)value
{
    self.modifications[key] = @{@"$setOnce":value};
}

- (void)unSet:(NSString *)key
{
    self.modifications[key] = NSNull.null;
}

- (void)increment:(NSString *)key
{
    [self incrementBy:key value:@1];
}

- (void)incrementBy:(NSString *)key value:(NSNumber *)value
{
    self.modifications[key] = @{@"$inc":value};
}

- (void)multiply:(NSString *)key value:(NSNumber *)value
{
    self.modifications[key] = @{@"$mul":value};
}

- (void)max:(NSString *)key value:(NSNumber *)value
{
    self.modifications[key] = @{@"$max":value};
}

- (void)min:(NSString *)key value:(NSNumber *)value
{
    self.modifications[key] = @{@"$min":value};
}

- (void)push:(NSString *)key value:(NSString *)value
{
    self.modifications[key] = @{@"$push":value};
}

- (void)push:(NSString *)key values:(NSArray *)value
{
    self.modifications[key] = @{@"$push":value};
}

- (void)pushUnique:(NSString *)key value:(NSString *)value
{
    self.modifications[key] = @{@"$addToSet":value};
}

- (void)pushUnique:(NSString *)key values:(NSArray *)value
{
    self.modifications[key] = @{@"$addToSet":value};
}

- (void)pull:(NSString *)key value:(NSString *)value
{
    self.modifications[key] = @{@"$pull":value};
}

- (void)pull:(NSString *)key values:(NSArray *)value
{
    self.modifications[key] = @{@"$pull":value};
}

- (void)save
{
    NSString* userDetails = [CountlyUserDetails.sharedInstance serializedUserDetails];
    if (userDetails)
        [CountlyConnectionManager.sharedInstance sendUserDetails:userDetails];

    if (self.pictureLocalPath && !self.pictureURL)
        [CountlyConnectionManager.sharedInstance sendUserDetails:[@{kCountlyLocalPicturePath:self.pictureLocalPath} cly_JSONify]];

    if (self.modifications.count)
        [CountlyConnectionManager.sharedInstance sendUserDetails:[@{@"custom":self.modifications} cly_JSONify]];

    [self clearUserDetails];
}

@end
