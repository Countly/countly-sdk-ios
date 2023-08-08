// CountlyViewTracking.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyViewTracking : NSObject

+ (instancetype)sharedInstance;

- (void)setGlobalViewSegmentation:(NSDictionary *)segmentation;
- (void)updateGlobalViewSegmentation:(NSDictionary *)segmentation;

- (NSString *)recordView:(NSString *)viewName;
- (NSString *)recordView:(NSString *)viewName segmentation:(NSDictionary *)segmentation;

- (NSString *)startView:(NSString *)viewName;
- (NSString *)startView:(NSString *)viewName segmentation:(NSDictionary *)segmentation;

- (void)stopViewWithName:(NSString *)viewName;
- (void)stopViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation;

- (void)stopViewWithID:(NSString *)viewID;
- (void)stopViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation;

- (void)pauseViewWithID:(NSString *)viewID;
- (void)resumeViewWithID:(NSString *)viewID;


@end
