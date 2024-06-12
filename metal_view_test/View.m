//
//  View.m
//  metal_view_test
//
//  Created by Manuel Cabrerizo on 10/06/2024.
//

#import "View.h"

@implementation View
{
    CADisplayLink *_displayLink;
}

+ (Class) layerClass
{
    return [CAMetalLayer class];
}

- (instancetype) initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if(self) {
        [self initCommon];
    }
    return self;
}

- (instancetype) initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if(self) {
        [self initCommon];
    }
    return self;
}

- (void)initCommon {
    _metalLayer = (CAMetalLayer *) self.layer;
    self.layer.delegate = self;
}

- (void)resizeDrawable:(CGFloat)scaleFactor {
    CGSize newSize = self.bounds.size;
    newSize.width *= scaleFactor;
    newSize.height *= scaleFactor;
    if(newSize.width <= 0 || newSize.height <= 0) {
        return;
    }
    
    if(newSize.width == _metalLayer.drawableSize.width &&
       newSize.height == _metalLayer.drawableSize.height) {
        return;
    }
    _metalLayer.drawableSize = newSize;
    [_delegate drawableResize:newSize];
}

-(void)dealloc {
    [self stopRenderLoop];
}

- (void)render {
    [_delegate renderToMetalLayer:_metalLayer];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    
    if(self.window == nil) {
        // if moving off of a window destroy the display link
        [_displayLink invalidate];
        _displayLink = nil;
        return;
    }
    [self setupCADisplayLinkForScreen:self.window.screen];
    
    // CADDisplayLink callbaks are associated with an NSRunLoop. The currentRunLoop is the
    // main run loop
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [self resizeDrawable:self.window.screen.nativeScale];
}

-(void) setPaused:(BOOL)paused
{
    self.paused = paused;
    _displayLink.paused = paused;
}

- (void)setupCADisplayLinkForScreen:(UIScreen*)screen {
    [self stopRenderLoop];
    _displayLink = [screen displayLinkWithTarget:self selector:@selector(render)];
    _displayLink.paused = self.paused;
    _displayLink.preferredFramesPerSecond = 60;
}

- (void)didEnterBackground:(NSNotification*)notification {
    self.paused = YES;
}

- (void)willEnterForeground:(NSNotification*)notification {
    self.paused = NO;
}

- (void)stopRenderLoop {
    [_displayLink invalidate];
}

// Override all methods which indicate the view's size has changed

- (void)setContentScaleFactor:(CGFloat)contentScaleFactor {
    [super setContentScaleFactor:contentScaleFactor];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    [self resizeDrawable:self.window.screen.nativeScale];
}

@end
