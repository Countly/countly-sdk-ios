// CountlyUserDetails.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

/**
 * A placeholder type specifier which accepts only @c NSString or @c NSNull for @c CountlyUserDetails default properties.
 */
@protocol CountlyUserDetailsNullableString <NSObject>
@end
@interface NSString (NSStringWithCountlyUserDetailsNullableString) <CountlyUserDetailsNullableString>
@end
@interface NSNull (NSNullWithCountlyUserDetailsNullableString) <CountlyUserDetailsNullableString>
@end


/**
 * A placeholder type specifier which accepts only @c NSDictionary or @c NSNull for @c CountlyUserDetails default properties.
 */
@protocol CountlyUserDetailsNullableDictionary <NSObject>
@end
@interface NSDictionary (NSDictionaryWithCountlyUserDetailsNullableDictionary) <CountlyUserDetailsNullableDictionary>
@end
@interface NSNull (NSNullWithCountlyUserDetailsNullableDictionary) <CountlyUserDetailsNullableDictionary>
@end


/**
 * A placeholder type specifier which accepts only @c NSNumber or @c NSNull for @c CountlyUserDetails default properties.
 */
@protocol CountlyUserDetailsNullableNumber <NSObject>
@end
@interface NSNumber (NSDictionaryWithCountlyUserDetailsNullableNumber) <CountlyUserDetailsNullableNumber>
@end
@interface NSNull (NSNullWithCountlyUserDetailsNullableNumber) <CountlyUserDetailsNullableNumber>
@end

extern NSString* const kCountlyLocalPicturePath;

@interface CountlyUserDetails : NSObject

/**
 * Default @c name property for user's name in User Profiles.
 * @discussion It can be set to an @c NSString, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableString> name;

/**
 * Default @c username property for user's username in User Profiles.
 * @discussion It can be set to an @c NSString, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableString> username;

/**
 * Default @c email property for user's e-mail in User Profiles.
 * @discussion It can be set to an @c NSString, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableString> email;

/**
 * Default @c organization property for user's organization/company in User Profiles.
 * @discussion It can be set to an @c NSString, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableString> organization;

/**
 * Default @c phone property for user's phone number in User Profiles.
 * @discussion It can be set to an @c NSString, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableString> phone;

/**
 * Default @c gender property for user's gender in User Profiles.
 * @discussion It can be set to an @c NSString, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 * @discussion If it is set to case-insensitive @c m or @c f, it is displayed as @c Male or @c Female. Otherwise it will displayed as @c Unknown.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableString> gender;

/**
 * Default @c pictureURL property for user's profile photo in User Profiles.
 * @discussion It can be set to an @c NSString, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 * @discussion It should be a publicly accessible URL string to user's profile photo, so server can download it.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableString> pictureURL;

/**
 * Default @c pictureLocalPath property for user's profile photo in User Profiles.
 * @discussion It can be set to an @c NSString, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 * @discussion It should be a valid local path string to user's profile photo on the device, so it can be uploaded to server.
 * If @c pictureURL is also set at the same time, @c pictureLocalPath will be ignored and @c pictureURL will be used.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableString> pictureLocalPath;

/**
 * Default @c birthYear property for user's birth year in User Profiles.
 * @discussion It can be set to an @c NSNumber, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableNumber> birthYear;

/**
 * @c custom property for user's custom information as key-value pairs in User Profiles.
 * @discussion It can be set to an @c NSDictionary, or @c NSNull for clearing it on server.
 * It will be sent to server when @c recordUserDetails method is called.
 * @discussion Key-value pairs in @c custom property can also be modified using custom property modifier methods.
 */
@property (nonatomic, strong) id<CountlyUserDetailsNullableDictionary> custom;

/**
 * Returns @c CountlyUserDetails singleton to be used throughout the app.
 * @return The shared @c CountlyUserDetails object
 * @discussion @c Countly.user convenience accessor can also be used.
 */
+ (instancetype)sharedInstance;

/**
 * @c recordUserDetails method is deprecated. Please use @c save method instead.
 * @discussion Currently all calls to @c recordUserDetails method is redirected to @c save method automatically.
 * @discussion But it is strongly recommended to replace it with @c save method.
 */
- (void)recordUserDetails DEPRECATED_MSG_ATTRIBUTE("Use 'save' method instead!");

#pragma mark -

/**
 * Custom user details property modifier for setting a key-value pair.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property key-value pair
 * @param value Value for custom property key-value pair
 */
- (void)set:(NSString *)key value:(NSString *)value;

/**
 * Custom user details property modifier for setting a key-value pair if not set before.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property key-value pair
 * @param value Value for custom property key-value pair
 */
- (void)setOnce:(NSString *)key value:(NSString *)value;

/**
 * Custom user details property modifier for unsetting a key-value pair.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property key-value pair
 */
- (void)unSet:(NSString *)key;

/**
 * Custom user details property modifier for incrementing a key-value pair's value by 1.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property key-value pair
 */
- (void)increment:(NSString *)key;

/**
 * Custom user details property modifier for incrementing a key-value pair's value by specified amount.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property key-value pair
 * @param value Amount of increment
 */
- (void)incrementBy:(NSString *)key value:(NSNumber *)value;

/**
 * Custom user details property modifier for multiplying a key-value pair's value by specified multiplier.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property key-value pair
 * @param value Multiplier
 */
- (void)multiply:(NSString *)key value:(NSNumber *)value;

/**
 * Custom user details property modifier for setting a key-value pair's value if it is less than specified value.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property key-value pair
 * @param value Value to be compared against current value
 */
- (void)max:(NSString *)key value:(NSNumber *)value;

/**
 * Custom user details property modifier for setting a key-value pair's value if it is more than specified value.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property key-value pair
 * @param value Value to be compared against current value
 */
- (void)min:(NSString *)key value:(NSNumber *)value;

/**
 * Custom user details property modifier for adding specified value to the array for specified key.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property of array type
 * @param value Value to be added to the array
 */
- (void)push:(NSString *)key value:(NSString *)value;

/**
 * Custom user details property modifier for adding specified values to the array for specified key.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property of array type
 * @param value An array of values to be added to the array
 */
- (void)push:(NSString *)key values:(NSArray *)value;

/**
 * Custom user details property modifier for adding specified value to the array for specified key, if it does not exist.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property of array type
 * @param value Value to be added to the array
 */
- (void)pushUnique:(NSString *)key value:(NSString *)value;

/**
 * Custom user details property modifier for adding specified values to the array for specified key, if they do not exist.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property of array type
 * @param value An array of values to be added to the array
 */
- (void)pushUnique:(NSString *)key values:(NSArray *)value;

/**
 * Custom user details property modifier for removing specified value from the array for specified key.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property of array type
 * @param value Value to be removed from the array
 */
- (void)pull:(NSString *)key value:(NSString *)value;

/**
 * Custom user details property modifier for removing specified values from the array for specified key.
 * @discussion When called, this modifier is added to a non-persistent queue and sent to server only when @c save method is called.
 * @param key Key for custom property of array type
 * @param value An array of values to be removed from the array
 */
- (void)pull:(NSString *)key values:(NSArray *)value;

/**
 * Records user details and sends them to server.
 * @discussion Once called, default user details properties and custom user details property modifiers are reset. If sending them to server fails, they are stored peristenly in request queue, to be tried again later.
 */
- (void)save;
@end
