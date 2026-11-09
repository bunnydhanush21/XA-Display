#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XAVirtualDisplay : NSObject
@property (nonatomic, readonly) uint32_t displayID;
@property (nonatomic, readonly) BOOL running;
- (BOOL)applyPixelWidth:(uint32_t)pixelsWide height:(uint32_t)pixelsHigh scale:(double)scale name:(NSString *)name;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
