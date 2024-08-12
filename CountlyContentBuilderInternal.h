// CountlyContent.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CountlyContentBuilderInternal: NSObject

@property (nonatomic, strong) NSArray<NSString *> *currentTags;
@property (nonatomic, strong) NSString *latestChecksum;
@property (nonatomic, assign) BOOL isContentConsentGiven;
@property (nonatomic, assign) CGFloat density;
@property (nonatomic, assign) NSTimeInterval requestInterval;

+ (instancetype)sharedInstance;

- (void)openForContent:(NSArray<NSString *> *)tags;
- (void)exitFromContent;
- (void)changeContent:(NSArray<NSString *> *)tags;

@end

