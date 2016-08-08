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

+ (CountlyUserDetails *)sharedInstance
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
    [CountlyConnectionManager.sharedInstance sendUserDetails:[CountlyUserDetails.sharedInstance serialize]];
    
    if(self.pictureLocalPath && !self.pictureURL)
    {
        [CountlyConnectionManager.sharedInstance sendUserDetails:[@{kCountlyLocalPicturePath:self.pictureLocalPath} JSONify]];
    }
}

- (NSString *)serialize
{
    NSMutableDictionary* userDictionary = NSMutableDictionary.new;
    if(self.name)
        userDictionary[@"name"] = self.name;
    if(self.username)
        userDictionary[@"username"] = self.username;
    if(self.email)
        userDictionary[@"email"] = self.email;
    if(self.organization)
        userDictionary[@"organization"] = self.organization;
    if(self.phone)
        userDictionary[@"phone"] = self.phone;
    if(self.gender)
        userDictionary[@"gender"] = self.gender;
    if(self.pictureURL)
        userDictionary[@"picture"] = self.pictureURL;
    if(self.birthYear)
        userDictionary[@"byear"] = self.birthYear;
    if(self.custom)
        userDictionary[@"custom"] = self.custom;

    return [userDictionary JSONify];
}

- (NSData *)pictureUploadDataForRequest:(NSString *)requestString
{
#if TARGET_OS_IOS
    NSString* unescaped = [requestString stringByRemovingPercentEncoding];
    NSRange rLocalPicturePath = [unescaped rangeOfString:kCountlyLocalPicturePath];
    if (rLocalPicturePath.location == NSNotFound)
        return nil;

    NSString* pathString = [unescaped substringFromIndex:rLocalPicturePath.location-2];
    NSDictionary* pathDictionary = [NSJSONSerialization JSONObjectWithData:[pathString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSString* localPicturePath = pathDictionary[kCountlyLocalPicturePath];
    if(!localPicturePath || [localPicturePath isEqualToString:@""])
        return nil;

    COUNTLY_LOG(@"Local picture path successfully extracted from query string: %@", localPicturePath);

    NSArray* allowedFileTypes = @[@"gif", @"png", @"jpg", @"jpeg"];
    NSString* fileExt = localPicturePath.pathExtension.lowercaseString;
    NSInteger fileExtIndex = [allowedFileTypes indexOfObject:fileExt];

    if(fileExtIndex == NSNotFound)
        return nil;
    
    NSData* imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:localPicturePath]];

    if (!imageData)
    {
        COUNTLY_LOG(@"Local picture data can not be read!");
        return nil;
    }

    COUNTLY_LOG(@"Local picture data read successfully.");

    //NOTE: png file data read directly from disk somehow fails on upload, this fixes it
    if (fileExtIndex == 1)
        imageData = UIImagePNGRepresentation([UIImage imageWithData:imageData]);

    //NOTE: for mime type jpg -> jpeg
    if (fileExtIndex == 2)
        fileExtIndex = 3;

    NSMutableData* uploadData = NSMutableData.new;
    [uploadData appendStringUTF8:[NSString stringWithFormat:@"--%@\r\n", CountlyConnectionManager.sharedInstance.boundary]];
    [uploadData appendStringUTF8:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"pictureFile\"; filename=\"%@\"\r\n", localPicturePath.lastPathComponent]];
    [uploadData appendStringUTF8:[NSString stringWithFormat:@"Content-Type: image/%@\r\n\r\n", allowedFileTypes[fileExtIndex]]];
    [uploadData appendData:imageData];
    [uploadData appendStringUTF8:[NSString stringWithFormat:@"\r\n--%@--\r\n", CountlyConnectionManager.sharedInstance.boundary]];

    return uploadData;
#endif
    return nil;
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
    [self incrementBy:key value:1];
}

- (void)incrementBy:(NSString *)key value:(NSInteger)value
{
    self.modifications[key] = @{@"$inc":@(value)};
}

- (void)multiply:(NSString *)key value:(NSInteger)value
{
    self.modifications[key] = @{@"$mul":@(value)};
}

- (void)max:(NSString *)key value:(NSInteger)value
{
    self.modifications[key] = @{@"$max":@(value)};
}

- (void)min:(NSString *)key value:(NSInteger)value
{
    self.modifications[key] = @{@"$min":@(value)};
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
    NSDictionary* custom = @{@"custom":self.modifications};

    [CountlyConnectionManager.sharedInstance sendUserDetails:[custom JSONify]];

    [self.modifications removeAllObjects];
}

@end