#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <substrate.h>
#import "MediaManager.h"

// ============================================================================
// MARK: - 全局状态
// ============================================================================

static BOOL g_vcamEnabled = NO;
static UIWindow *g_overlayWindow = nil;
static UIButton *g_floatButton = nil;

// ============================================================================
// MARK: - 悬浮按钮 UI
// ============================================================================

@interface VCamFloatButton : UIButton
@property (nonatomic, assign) CGPoint initialCenter;
@end

@implementation VCamFloatButton
@end

static void setupFloatButton() {
    if (g_floatButton) return;
    
    CGFloat btnSize = 50;
    CGRect screen = [UIScreen mainScreen].bounds;
    
    g_floatButton = [VCamFloatButton buttonWithType:UIButtonTypeSystem];
    g_floatButton.frame = CGRectMake(screen.size.width - btnSize - 15, 100, btnSize, btnSize);
    g_floatButton.layer.cornerRadius = btnSize / 2.0;
    g_floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    g_floatButton.layer.shadowOffset = CGSizeMake(0, 2);
    g_floatButton.layer.shadowOpacity = 0.3;
    g_floatButton.layer.shadowRadius = 4;
    g_floatButton.backgroundColor = g_vcamEnabled 
        ? [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9]
        : [UIColor colorWithRed:0.4 blue:0.4 alpha:0.9];
    
    // Icon: camera emoji
    [g_floatButton setTitle:@"📷" forState:UIControlStateNormal];
    g_floatButton.titleLabel.font = [UIFont systemFontOfSize:24];
    
    // Drag gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
    [g_floatButton addGestureRecognizer:pan];
    
    // Tap gesture
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:@selector(handleTap:)];
    [g_floatButton addGestureRecognizer:tap];
    
    // Overlay window (above everything)
    g_overlayWindow = [[UIWindow alloc] initWithFrame:screen];
    g_overlayWindow.windowLevel = UIWindowLevelAlert + 100;
    g_overlayWindow.hidden = NO;
    g_overlayWindow.backgroundColor = [UIColor clearColor];
    
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    [rootVC.view addSubview:g_floatButton];
    g_overlayWindow.rootViewController = rootVC;
}

// Drag handler
static void (^panHandler)(UIPanGestureRecognizer *) = ^(UIPanGestureRecognizer *gesture) {
    UIView *btn = gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    btn.center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:btn.superview];
    
    if (gesture.state == UIGestureRecognizerStateEnded) {
        // Snap to edge
        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat x = btn.center.x < screen.size.width / 2 ? 35 : screen.size.width - 35;
        [UIView animateWithDuration:0.2 animations:^{
            btn.center = CGPointMake(x, btn.center.y);
        }];
    }
};

// Tap handler - present media picker
static void (^tapHandler)(UITapGestureRecognizer *) = ^(UITapGestureRecognizer *gesture) {
    UIViewController *topVC = nil;
    
    // Find topmost view controller
    UIWindow *keyWindow = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in scene.windows) {
                if (w.isKeyWindow) {
                    keyWindow = w;
                    break;
                }
            }
        }
    }
    
    topVC = keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    if (!topVC) return;
    
    // Show action sheet
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"VCam" 
        message:g_vcamEnabled ? @"虚拟相机已启用" : @"虚拟相机已关闭"
        preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"选择视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
        config.filter = [PHPickerFilter videosFilter];
        config.selectionLimit = 1;
        
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        // Delegate set in tweak
        [topVC presentViewController:picker animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:g_vcamEnabled ? @"关闭虚拟相机" : @"开启虚拟相机" 
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        g_vcamEnabled = !g_vcamEnabled;
        g_floatButton.backgroundColor = g_vcamEnabled 
            ? [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9]
            : [UIColor colorWithRed:0.4 blue:0.4 alpha:0.9];
        
        if (g_vcamEnabled) {
            [[MediaManager sharedManager] start];
        } else {
            [[MediaManager sharedManager] stop];
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // iPad popover support
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = gesture.view;
        alert.popoverPresentationController.sourceRect = gesture.view.bounds;
    }
    
    [topVC presentViewController:alert animated:YES completion:nil];
};

// ============================================================================
// MARK: - PHPicker Delegate
// ============================================================================

@interface VCamPickerDelegate : NSObject <PHPickerViewControllerDelegate>
@end

@implementation VCamPickerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    if (results.count == 0) return;
    
    PHPickerResult *result = results.firstObject;
    NSItemProvider *provider = result.itemProvider;
    
    if ([provider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeMovie]) {
        [provider loadFileRepresentationForTypeIdentifier:(NSString *)kUTTypeMovie 
            completionHandler:^(NSURL *url, NSError *error) {
            if (url && !error) {
                // Copy to temp to avoid permission issues
                NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() 
                    stringByAppendingPathComponent:@"vcam_input.mp4"]];
                [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
                [[NSFileManager defaultManager] copyItemAtURL:url toURL:tempURL error:nil];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[MediaManager sharedManager] loadMediaFromURL:tempURL];
                    g_vcamEnabled = YES;
                    [[MediaManager sharedManager] start];
                    g_floatButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9];
                });
            }
        }];
    }
}

@end

static VCamPickerDelegate *g_pickerDelegate = nil;

// ============================================================================
// MARK: - Hook AVCaptureSession
// ============================================================================

%group VCamHooks

// Hook session start - intercept the pipeline
%hook AVCaptureSession

- (void)startRunning {
    if (g_vcamEnabled) {
        // Still call original so the session object is "started"
        // but we'll intercept the output callbacks
    }
    %orig;
}

- (void)stopRunning {
    %orig;
}

%end

// ============================================================================
// MARK: - Hook Video Data Output Delegate
// ============================================================================

// We swizzle the delegate setter to intercept frame delivery
%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate 
                          queue:(dispatch_queue_t)queue {
    if (g_vcamEnabled && delegate) {
        // Store original delegate info, we'll inject our own frames
        // The original delegate will receive our generated frames
    }
    %orig;
}

%end

// Hook the delegate callback to replace frames
%hook NSObject

// This catches AVCaptureVideoDataOutputSampleBufferDelegate implementations
- (void)captureOutput:(AVCaptureOutput *)output 
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
           fromConnection:(AVCaptureConnection *)connection {
    
    if (g_vcamEnabled && [[MediaManager sharedManager] isRunning]) {
        CMSampleBufferRef fakeFrame = [[MediaManager sharedManager] nextVideoFrame];
        if (fakeFrame) {
            %orig(output, fakeFrame, connection);
            CFRelease(fakeFrame);
            return;
        }
    }
    %orig;
}

%end

// ============================================================================
// MARK: - Hook Photo Output
// ============================================================================

%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings 
                        delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (g_vcamEnabled) {
        // For photos, we still let the original flow happen
        // The video preview layer hook will show our fake frames
    }
    %orig;
}

%end

// ============================================================================
// MARK: - Hook Preview Layer (visual feedback)
// ============================================================================

%hook AVCaptureVideoPreviewLayer

- (void)setSession:(AVCaptureSession *)session {
    %orig;
    // Preview layer will show whatever the session outputs
    // Our frame hook handles the substitution
}

%end

%end // VCamHooks group

// ============================================================================
// MARK: - Constructor (auto-run on inject)
// ============================================================================

%ctor {
    @autoreleasepool {
        // Wait for app to be ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), 
            dispatch_get_main_queue(), ^{
            @autoreleasepool {
                setupFloatButton();
                
                // Attach gesture handlers via runtime
                Class btnClass = [g_floatButton class];
                class_addMethod(btnClass, @selector(handlePan:), 
                    (IMP)panHandler, "v@:@");
                class_addMethod(btnClass, @selector(handleTap:), 
                    (IMP)tapHandler, "v@:@");
                
                // Init picker delegate (retain globally)
                g_pickerDelegate = [[VCamPickerDelegate alloc] init];
            }
        });
        
        // Only hook if not SpringBoard
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.apple.springboard"]) {
            %init(VCamHooks);
        }
    }
}
