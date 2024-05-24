// CrashData.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyCrashData : NSObject

@property (nonatomic, copy, nonnull) NSString *stackTrace;
@property (nonatomic, copy, nonnull) NSString *name;
@property (nonatomic, copy, nonnull) NSString *crashDescription;
@property (nonatomic, assign) BOOL fatal;
@property (nonatomic, copy, nonnull) NSMutableArray<NSString *> *breadcrumbs;
@property (nonatomic, copy, nonnull) NSMutableDictionary<NSString *, id> *crashSegmentation;
@property (nonatomic, copy, nonnull) NSMutableDictionary<NSString *, id> *crashMetrics;

@property (nonatomic, strong, nonnull) NSMutableArray<NSString *> *checksums;
@property (nonatomic, strong, nonnull) NSMutableArray<NSNumber *> *changedFields;

- (instancetype _Nonnull )initWithStackTrace:(NSString *_Nonnull)stackTrace name:(NSString *_Nonnull)name description:(NSString *_Nonnull)description crashSegmentation:(NSDictionary<NSString *, id> *_Nonnull)crashSegmentation breadcrumbs:(NSArray<NSString *> *_Nonnull)breadcrumbs crashMetrics:(NSDictionary<NSString *, id> *_Nullable)crashMetrics fatal:(BOOL)fatal;

- (NSString *_Nonnull)getBreadcrumbsAsString;
- (NSDictionary<NSString *, id> *_Nonnull)getCrashMetricsJSON;
- (void)calculateChangedFields;
- (NSNumber *_Nonnull)getChangedFieldsAsInt;

@end

