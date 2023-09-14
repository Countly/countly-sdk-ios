// CountlyExperimentInfo.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyExperimentInformation : NSObject

@property (nonatomic, readonly) NSString* experimentID;
@property (nonatomic, readonly) NSString* experimentName;
@property (nonatomic, readonly) NSString* experimentDescription;
@property (nonatomic, readonly) NSString* currentVariant;
@property (nonatomic, readonly) NSDictionary* variants;


- (instancetype)initWithID:(NSString*)experimentID experimentName:(NSString*)experimentName  experimentDescription:(NSString*)experimentDescription  currentVariant:(NSString*)currentVariant  variants:(NSDictionary*)variants;

@end



