// CountlyOverlayWindow.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS)
#import "CountlyOverlayWindow.h"

@implementation CountlyOverlayWindow

- (instancetype)init {
    if (self = [super initWithFrame:UIScreen.mainScreen.bounds]) {
        self.windowLevel = UIWindowLevelAlert + 10;
        self.backgroundColor = UIColor.clearColor;
        self.hidden = YES;
    }
    return self;
}

@end
#endif
