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
@property(nonatomic, strong) NSString* pictureURL;
@property(nonatomic, strong) NSString* pictureLocalPath;
@property(nonatomic, assign) NSInteger birthYear;
@property(nonatomic, strong) NSDictionary* custom;

+ (CountlyUserDetails *)sharedInstance;
- (void)recordUserDetails;
- (NSString *)serialize;
- (NSString *)extractPicturePathFromURLString:(NSString*)URLString;
@end