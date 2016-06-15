// CountlyUserDetails.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyUserDetails ()
@property (nonatomic, strong) NSMutableDictionary* modifications;
@end

@implementation CountlyUserDetails

NSString* const kCountlyUserName = @"name";
NSString* const kCountlyUserUsername = @"username";
NSString* const kCountlyUserEmail = @"email";
NSString* const kCountlyUserOrganization = @"organization";
NSString* const kCountlyUserPhone = @"phone";
NSString* const kCountlyUserGender = @"gender";
NSString* const kCountlyUserPictureURL = @"picture";
NSString* const kCountlyUserPictureLocalPath = @"picturePath";
NSString* const kCountlyUserBirthYear = @"byear";
NSString* const kCountlyUserCustom = @"custom";

+ (CountlyUserDetails *)sharedInstance
{
    static CountlyUserDetails *s_CountlyUserDetails = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{s_CountlyUserDetails = CountlyUserDetails.new;});
    return s_CountlyUserDetails;
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
    [CountlyConnectionManager.sharedInstance sendUserDetails:[CountlyUserDetails.sharedInstance serialize]];
}

- (NSString *)serialize
{
    NSMutableDictionary* userDictionary = NSMutableDictionary.new;
    if(self.name)
        userDictionary[kCountlyUserName] = self.name;
    if(self.username)
        userDictionary[kCountlyUserUsername] = self.username;
    if(self.email)
        userDictionary[kCountlyUserEmail] = self.email;
    if(self.organization)
        userDictionary[kCountlyUserOrganization] = self.organization;
    if(self.phone)
        userDictionary[kCountlyUserPhone] = self.phone;
    if(self.gender)
        userDictionary[kCountlyUserGender] = self.gender;
    if(self.pictureURL)
        userDictionary[kCountlyUserPictureURL] = self.pictureURL;
    if(self.pictureLocalPath)
        userDictionary[kCountlyUserPictureLocalPath] = self.pictureLocalPath;
    if(self.birthYear!=0)
        userDictionary[kCountlyUserBirthYear] = @(self.birthYear);
    if(self.custom)
        userDictionary[kCountlyUserCustom] = self.custom;

    return [userDictionary JSONify];
}

- (NSString *)extractPicturePathFromURLString:(NSString*)URLString
{
    NSString* unescaped = [URLString stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    unescaped = [unescaped stringByRemovingPercentEncoding];
    NSRange rPicturePathKey = [unescaped rangeOfString:kCountlyUserPictureLocalPath];
    if (rPicturePathKey.location == NSNotFound)
        return nil;

    NSString* picturePath = nil;

    @try
    {
        NSRange rSearchForEnding = (NSRange){0,unescaped.length};
        rSearchForEnding.location = rPicturePathKey.location+rPicturePathKey.length+3;
        rSearchForEnding.length = rSearchForEnding.length - rSearchForEnding.location;
        NSRange rEnding = [unescaped rangeOfString:@"\",\"" options:0 range:rSearchForEnding];
        picturePath = [unescaped substringWithRange:(NSRange){rSearchForEnding.location,rEnding.location-rSearchForEnding.location}];
        picturePath = [picturePath stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    }
    @catch (NSException *exception)
    {
        COUNTLY_LOG(@"Cannot extract picture path!");
        picturePath = @"";
    }

    COUNTLY_LOG(@"Extracted picturePath: %@", picturePath);
    return picturePath;
}


#pragma mark -

- (void)set:(NSString*)key value:(NSString*)value
{
    self.modifications[key] = value;
}

- (void)setOnce:(NSString*)key value:(NSString*)value
{
    self.modifications[key] = @{@"$setOnce":value};
}

- (void)unSet:(NSString*)key
{
    self.modifications[key] = NSNull.null;
}

- (void)increment:(NSString*)key
{
    [self incrementBy:key value:1];
}

- (void)incrementBy:(NSString*)key value:(NSInteger)value
{
    self.modifications[key] = @{@"$inc":@(value)};
}

- (void)multiply:(NSString*)key value:(NSInteger)value
{
    self.modifications[key] = @{@"$mul":@(value)};
}

- (void)max:(NSString*)key value:(NSInteger)value
{
    self.modifications[key] = @{@"$max":@(value)};
}

- (void)min:(NSString*)key value:(NSInteger)value
{
    self.modifications[key] = @{@"$min":@(value)};
}

- (void)push:(NSString*)key value:(NSString*)value
{
    self.modifications[key] = @{@"$push":value};
}

- (void)push:(NSString*)key values:(NSArray*)value
{
    self.modifications[key] = @{@"$push":value};
}

- (void)pushUnique:(NSString*)key value:(NSString*)value
{
    self.modifications[key] = @{@"$addToSet":value};
}

- (void)pushUnique:(NSString*)key values:(NSArray*)value
{
    self.modifications[key] = @{@"$addToSet":value};
}

- (void)pull:(NSString*)key value:(NSString*)value
{
    self.modifications[key] = @{@"$pull":value};
}

- (void)pull:(NSString*)key values:(NSArray*)value
{
    self.modifications[key] = @{@"$pull":value};
}

- (void)save
{
    NSDictionary* custom = @{@"custom":self.modifications};

    [CountlyConnectionManager.sharedInstance sendUserDetails:[custom JSONify]];

    [self.modifications removeAllObjects];
}

@end