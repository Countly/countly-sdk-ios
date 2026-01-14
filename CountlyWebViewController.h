//
//  CountlyWebViewController.h
//  Countly
//
//  Created by Arif Burak Demiray on 14.01.2026.
//  Copyright © 2026 Countly. All rights reserved.
//


//
//  CountlyWebViewController.h
//  CountlyTestApp-iOS
//
//  Created by Arif Burak Demiray on 19.11.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
#if (TARGET_OS_IOS)
#import <UIKit/UIKit.h>
#endif

#import "CountlyCommon.h"

NS_ASSUME_NONNULL_BEGIN
#if (TARGET_OS_IOS)
@interface CountlyWebViewController : UIViewController
@property (nonatomic, strong) UIView *contentView;
@end
#endif
NS_ASSUME_NONNULL_END
