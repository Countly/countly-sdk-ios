// CrashData.m

#import "CountlyCrashData.h"
#import "CountlyCommon.h"

@implementation CountlyCrashData

- (instancetype)initWithStackTrace:(NSString *)stackTrace name:(NSString *)name description:(NSString *)description crashSegmentation:(NSDictionary<NSString *, id> *)crashSegmentation breadcrumbs:(NSArray<NSString *> *)breadcrumbs crashMetrics:(NSDictionary<NSString *, id> *)crashMetrics fatal:(BOOL)fatal {
    self = [super init];
    if (self) {
        _stackTrace = [stackTrace copy] ?: @"";
        _name = [name copy] ?: @"";
        _crashDescription = [description copy] ?: @"";
        _crashSegmentation = [crashSegmentation copy] ?: @{};
        _breadcrumbs = [breadcrumbs copy] ?: @[];
        _crashMetrics = [crashMetrics copy] ?: @{};
        _fatal = fatal;
        
        _checksums = [NSMutableArray arrayWithCapacity:5];
        _changedFields = [NSMutableArray arrayWithCapacity:5];
        [self calculateChecksums:_checksums];
    }
    return self;
}

- (NSString *)getBreadcrumbsAsString {
    NSMutableString *breadcrumbsString = [NSMutableString string];
    for (NSString *breadcrumb in self.breadcrumbs) {
        [breadcrumbsString appendFormat:@"%@\n", breadcrumb];
    }
    return [breadcrumbsString copy];
}

- (NSDictionary<NSString *, id> *)getCrashMetricsJSON {
    NSMutableDictionary<NSString *, id> *crashMetrics = [NSMutableDictionary dictionary];
    for (NSString *key in self.crashMetrics) {
        crashMetrics[key] = self.crashMetrics[key];
    }
    return [crashMetrics copy];
}

- (void)calculateChangedFields {
    NSMutableArray<NSString *> *checksumsNew = [NSMutableArray arrayWithCapacity:5];
    [self calculateChecksums:checksumsNew];
    
    NSMutableArray<NSNumber *> *changedFields = [NSMutableArray arrayWithCapacity:5];
    for (int i = 0; i < checksumsNew.count; i++) {
        changedFields[i] = @(![self.checksums[i] isEqualToString:checksumsNew[i]]);
    }
    self.changedFields = [changedFields copy];
}

- (NSNumber *)getChangedFieldsAsInt {
    int result = 0;
    for (int i = (int)self.changedFields.count - 1; i >= 0; i--) {
        if (self.changedFields[i].boolValue) {
            result |= (1 << ((int)self.changedFields.count - 1 - i));
        }
    }
    return @(result);
}

- (void)calculateChecksums:(NSMutableArray<NSString *> *)checksumArrayToSet {
    [checksumArrayToSet removeAllObjects];
    [checksumArrayToSet addObject:[self.stackTrace cly_SHA256]];
    [checksumArrayToSet addObject:[[self.crashSegmentation description] cly_SHA256]];
    [checksumArrayToSet addObject:[[self.breadcrumbs description] cly_SHA256]];
    [checksumArrayToSet addObject:[[self.crashMetrics description] cly_SHA256]];
    [checksumArrayToSet addObject:[(self.fatal ? @"true" : @"false") cly_SHA256]];
}

@end
