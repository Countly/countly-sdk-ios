// CountlyUserDetails.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyUserDetails

NSString* const kCLYUserName = @"name";
NSString* const kCLYUserUsername = @"username";
NSString* const kCLYUserEmail = @"email";
NSString* const kCLYUserOrganization = @"organization";
NSString* const kCLYUserPhone = @"phone";
NSString* const kCLYUserGender = @"gender";
NSString* const kCLYUserPicture = @"picture";
NSString* const kCLYUserPicturePath = @"picturePath";
NSString* const kCLYUserBirthYear = @"byear";
NSString* const kCLYUserCustom = @"custom";

+ (CountlyUserDetails *)sharedInstance
{
    static CountlyUserDetails *s_CountlyUserDetails = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{s_CountlyUserDetails = CountlyUserDetails.new;});
    return s_CountlyUserDetails;
}

- (void)deserialize:(NSDictionary*)userDictionary
{
    if(userDictionary[kCLYUserName])
        self.name = userDictionary[kCLYUserName];
    if(userDictionary[kCLYUserUsername])
        self.username = userDictionary[kCLYUserUsername];
    if(userDictionary[kCLYUserEmail])
        self.email = userDictionary[kCLYUserEmail];
    if(userDictionary[kCLYUserOrganization])
        self.organization = userDictionary[kCLYUserOrganization];
    if(userDictionary[kCLYUserPhone])
        self.phone = userDictionary[kCLYUserPhone];
    if(userDictionary[kCLYUserGender])
        self.gender = userDictionary[kCLYUserGender];
    if(userDictionary[kCLYUserPicture])
        self.picture = userDictionary[kCLYUserPicture];
    if(userDictionary[kCLYUserPicturePath])
        self.picturePath = userDictionary[kCLYUserPicturePath];
    if(userDictionary[kCLYUserBirthYear])
        self.birthYear = [userDictionary[kCLYUserBirthYear] integerValue];
    if(userDictionary[kCLYUserCustom])
        self.custom = userDictionary[kCLYUserCustom];
}

- (NSString *)serialize
{
    NSMutableDictionary* userDictionary = NSMutableDictionary.new;
    if(self.name)
        userDictionary[kCLYUserName] = self.name;
    if(self.username)
        userDictionary[kCLYUserUsername] = self.username;
    if(self.email)
        userDictionary[kCLYUserEmail] = self.email;
    if(self.organization)
        userDictionary[kCLYUserOrganization] = self.organization;
    if(self.phone)
        userDictionary[kCLYUserPhone] = self.phone;
    if(self.gender)
        userDictionary[kCLYUserGender] = self.gender;
    if(self.picture)
        userDictionary[kCLYUserPicture] = self.picture;
    if(self.picturePath)
        userDictionary[kCLYUserPicturePath] = self.picturePath;
    if(self.birthYear!=0)
        userDictionary[kCLYUserBirthYear] = @(self.birthYear);
    if(self.custom)
        userDictionary[kCLYUserCustom] = self.custom;
    
    return [userDictionary JSONify];
}

- (NSString *)extractPicturePathFromURLString:(NSString*)URLString
{
    NSString* unescaped = [URLString stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    unescaped = [unescaped stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSRange rPicturePathKey = [unescaped rangeOfString:kCLYUserPicturePath];
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
@end