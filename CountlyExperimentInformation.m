// CountlyExperimentInfo.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyExperimentInformation.h"

@interface CountlyExperimentInformation ()
@property (nonatomic) NSString* experimentID;
@property (nonatomic) NSString* experimentName;
@property (nonatomic) NSString* experimentDescription;
@property (nonatomic) NSString* currentVariant;
@property (nonatomic) NSDictionary* variants;
@end


@implementation CountlyExperimentInformation

- (instancetype)init
{
    if (self = [super init])
    {
    }
    
    return self;
}

- (instancetype)initWithID:(NSString*)experimentID experimentName:(NSString*)experimentName  experimentDescription:(NSString*)experimentDescription  currentVariant:(NSString*)currentVariant  variants:(NSDictionary*)variants
{
    if (self = [super init])
    {
        self.experimentID = experimentID;
        self.experimentName = experimentName;
        self.experimentDescription = experimentDescription;
        self.currentVariant = currentVariant;
        self.variants = variants;
    }
    
    return self;
}


@end
