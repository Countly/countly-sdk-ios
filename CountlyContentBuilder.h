// CountlyContentBuilder.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CountlyContentBuilder: NSObject

+ (instancetype)sharedInstance;

- (void)openForContent;
- (void)openForContent:(NSArray<NSString *> *)tags;
- (void)exitFromContent;
- (void)changeContent:(NSArray<NSString *> *)tags;

@end
