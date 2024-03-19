// Resettable.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
#import <Foundation/Foundation.h>

@protocol Resettable <NSObject>

@optional
- (void)resetInstance;
- (void)resetInstance:(BOOL) clearStorage;

@end
