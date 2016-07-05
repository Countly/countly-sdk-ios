// CountlyUserDetails.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
@protocol CountlyUserDetailsNullableString <NSObject>
@end
@interface NSString (NSStringWithCountlyUserDetailsNullableString) <CountlyUserDetailsNullableString>
@end
@interface NSNull (NSNullWithCountlyUserDetailsNullableString) <CountlyUserDetailsNullableString>
@end


@protocol CountlyUserDetailsNullableDictionary <NSObject>
@end
@interface NSDictionary (NSDictionaryWithCountlyUserDetailsNullableDictionary) <CountlyUserDetailsNullableDictionary>
@end
@interface NSNull (NSNullWithCountlyUserDetailsNullableDictionary) <CountlyUserDetailsNullableDictionary>
@end


@protocol CountlyUserDetailsNullableNumber <NSObject>
@end
@interface NSNumber (NSDictionaryWithCountlyUserDetailsNullableNumber) <CountlyUserDetailsNullableNumber>
@end
@interface NSNull (NSNullWithCountlyUserDetailsNullableNumber) <CountlyUserDetailsNullableNumber>
@end


@interface CountlyUserDetails : NSObject

@property(nonatomic, strong) id<CountlyUserDetailsNullableString> name;
@property(nonatomic, strong) id<CountlyUserDetailsNullableString> username;
@property(nonatomic, strong) id<CountlyUserDetailsNullableString> email;
@property(nonatomic, strong) id<CountlyUserDetailsNullableString> organization;
@property(nonatomic, strong) id<CountlyUserDetailsNullableString> phone;
@property(nonatomic, strong) id<CountlyUserDetailsNullableString> gender;
@property(nonatomic, strong) id<CountlyUserDetailsNullableString> pictureURL;
@property(nonatomic, strong) id<CountlyUserDetailsNullableString> pictureLocalPath;
@property(nonatomic, assign) id<CountlyUserDetailsNullableNumber> birthYear;
@property(nonatomic, strong) id<CountlyUserDetailsNullableDictionary> custom;

+ (CountlyUserDetails *)sharedInstance;
- (void)recordUserDetails;
- (NSString *)serialize;
- (NSData *)pictureUploadDataForRequest:(NSString *)requestString;

#pragma mark -

- (void)set:(NSString *)key value:(NSString *)value;
- (void)setOnce:(NSString *)key value:(NSString *)value;
- (void)unSet:(NSString *)key;
- (void)increment:(NSString *)key;
- (void)incrementBy:(NSString *)key value:(NSInteger)value;
- (void)multiply:(NSString *)key value:(NSInteger)value;
- (void)max:(NSString *)key value:(NSInteger)value;
- (void)min:(NSString *)key value:(NSInteger)value;
- (void)push:(NSString *)key value:(NSString *)value;
- (void)push:(NSString *)key values:(NSArray *)value;
- (void)pushUnique:(NSString *)key value:(NSString *)value;
- (void)pushUnique:(NSString *)key values:(NSArray *)value;
- (void)pull:(NSString *)key value:(NSString *)value;
- (void)pull:(NSString *)key values:(NSArray *)value;
- (void)save;
@end

