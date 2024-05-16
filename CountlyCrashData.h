// CrashData.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyCrashData : NSObject

@property (nonatomic, copy, nonnull) NSString *stackTrace;
@property (nonatomic, copy, nonnull) NSDictionary<NSString *, id> *crashSegmentation;
@property (nonatomic, copy, nonnull) NSArray<NSString *> *breadcrumbs;
@property (nonatomic, assign) BOOL fatal;
@property (nonatomic, copy, nonnull) NSDictionary<NSString *, id> *crashMetrics;
@property (nonatomic, strong, nonnull) NSMutableArray<NSString *> *checksums;
@property (nonatomic, strong, nonnull) NSMutableArray<NSNumber *> *changedFields;

- (instancetype)initWithStackTrace:(NSString *)stackTrace crashSegmentation:(NSDictionary<NSString *, id> *)crashSegmentation breadcrumbs:(NSArray<NSString *> *)breadcrumbs crashMetrics:(NSDictionary<NSString *, id> *_Nullable)crashMetrics fatal:(BOOL)fatal;

- (NSString *)getBreadcrumbsAsString;
- (NSDictionary<NSString *, id> *)getCrashMetricsJSON;
- (void)calculateChangedFields;
- (int)getChangedFieldsAsInt;

@end

