#import "XAVirtualDisplay.h"
#import <CoreGraphics/CoreGraphics.h>

// Private CoreGraphics virtual-display SPI. Declared locally so this target
// does not vendor any third-party virtual-display project. Symbols are
// resolved at runtime (-undefined dynamic_lookup).

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t serialNum;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic) BOOL hiDPI;
@property (nonatomic, copy) NSArray *modes;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (nonatomic, readonly) uint32_t displayID;
@end

@implementation XAVirtualDisplay {
    CGVirtualDisplay *_display;
    uint32_t _width;
    uint32_t _height;
    double _scale;
}

- (uint32_t)displayID {
    return _display ? _display.displayID : 0;
}

- (BOOL)running {
    return _display != nil && self.displayID != 0;
}

- (BOOL)applyPixelWidth:(uint32_t)pixelsWide height:(uint32_t)pixelsHigh scale:(double)scale name:(NSString *)name {
    if (pixelsWide < 640 || pixelsHigh < 480 || pixelsWide > 4096 || pixelsHigh > 4096) {
        return NO;
    }
    if (_display && _width == pixelsWide && _height == pixelsHigh && fabs(_scale - scale) < 0.01) {
        return YES;
    }
    [self stop];
    if (NSClassFromString(@"CGVirtualDisplayDescriptor") == nil) {
        return NO;
    }
    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    if (descriptor == nil) {
        return NO;
    }
    double ppi = scale >= 1.5 ? 264.0 : 110.0;
    descriptor.name = name.length ? name : @"XA Display";
    descriptor.maxPixelsWide = pixelsWide;
    descriptor.maxPixelsHigh = pixelsHigh;
    descriptor.vendorID = 0x5841;
    descriptor.productID = 0x0001;
    descriptor.serialNum = 0x58410001;
    descriptor.sizeInMillimeters = CGSizeMake(pixelsWide / ppi * 25.4, pixelsHigh / ppi * 25.4);

    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
    if (display == nil) {
        return NO;
    }
    BOOL hiDPI = scale >= 1.5;
    uint32_t logicalW = hiDPI ? pixelsWide / (uint32_t)llround(scale) : pixelsWide;
    uint32_t logicalH = hiDPI ? pixelsHigh / (uint32_t)llround(scale) : pixelsHigh;
    if (logicalW < 1 || logicalH < 1) {
        logicalW = pixelsWide;
        logicalH = pixelsHigh;
        hiDPI = NO;
    }
    NSMutableArray *modes = [NSMutableArray array];
    CGVirtualDisplayMode *full = [[CGVirtualDisplayMode alloc] initWithWidth:pixelsWide height:pixelsHigh refreshRate:60];
    if (full) {
        [modes addObject:full];
    }
    if (hiDPI) {
        CGVirtualDisplayMode *logical = [[CGVirtualDisplayMode alloc] initWithWidth:logicalW height:logicalH refreshRate:60];
        if (logical) {
            [modes addObject:logical];
        }
    }
    CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
    settings.hiDPI = hiDPI;
    settings.modes = modes;
    if (![display applySettings:settings]) {
        return NO;
    }
    _display = display;
    _width = pixelsWide;
    _height = pixelsHigh;
    _scale = scale;
    return display.displayID != 0;
}

- (void)stop {
    _display = nil;
    _width = 0;
    _height = 0;
    _scale = 0;
}

@end
