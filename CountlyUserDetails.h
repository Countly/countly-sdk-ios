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

#pragma mark -

- (void)set:(NSString*)key value:(NSString*)value;
- (void)setOnce:(NSString*)key value:(NSString*)value;
- (void)unSet:(NSString*)key;
- (void)increment:(NSString*)key;
- (void)incrementBy:(NSString*)key value:(NSInteger)value;
- (void)multiply:(NSString*)key value:(NSInteger)value;
- (void)max:(NSString*)key value:(NSInteger)value;
- (void)min:(NSString*)key value:(NSInteger)value;
- (void)push:(NSString*)key value:(NSString*)value;
- (void)push:(NSString*)key values:(NSArray*)value;
- (void)pushUnique:(NSString*)key value:(NSString*)value;
- (void)pushUnique:(NSString*)key values:(NSArray*)value;
- (void)pull:(NSString*)key value:(NSString*)value;
- (void)pull:(NSString*)key values:(NSArray*)value;
- (void)save;
@end