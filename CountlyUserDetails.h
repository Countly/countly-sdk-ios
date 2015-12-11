// CountlyUserDetails.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyUserDetails : NSObject

@property(nonatomic, strong) NSString* name;
@property(nonatomic, strong) NSString* username;
@property(nonatomic, strong) NSString* email;
@property(nonatomic, strong) NSString* organization;
@property(nonatomic, strong) NSString* phone;
@property(nonatomic, strong) NSString* gender;
@property(nonatomic, strong) NSString* picture;
@property(nonatomic, strong) NSString* picturePath;
@property(nonatomic, assign) NSInteger birthYear;
@property(nonatomic, strong) NSDictionary* custom;

+ (CountlyUserDetails *)sharedInstance;
- (void)deserialize:(NSDictionary*)userDictionary;
- (NSString *)serialize;
- (NSString *)extractPicturePathFromURLString:(NSString*)URLString;

extern NSString* const kCLYUserName;
extern NSString* const kCLYUserUsername;
extern NSString* const kCLYUserEmail;
extern NSString* const kCLYUserOrganization;
extern NSString* const kCLYUserPhone;
extern NSString* const kCLYUserGender;
extern NSString* const kCLYUserPicture;
extern NSString* const kCLYUserPicturePath;
extern NSString* const kCLYUserBirthYear;
extern NSString* const kCLYUserCustom;

@end