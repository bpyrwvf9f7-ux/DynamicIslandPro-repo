// DynamicIslandPro —— 灵动岛通知胶囊（iOS 16 / iPhone 14 Pro）
// 目标进程：SpringBoard（24x24 岛屿位置浮层，收到通知横幅请求时弹出胶囊）
// 依赖：ElleKit（通过 filter plist 注入），不链接 CydiaSubstrate。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <unistd.h>

static const CGFloat kIslandTop       = 11.0;
static const CGFloat kCollapsedW      = 126.0;
static const CGFloat kCollapsedH      = 37.0;
static const CGFloat kCollapsedRadius = 18.5;

static UIWindow *gWindow = nil;
static UIView   *gPill   = nil;
static UILabel  *gTitle  = nil;
static UILabel  *gBody   = nil;
static BOOL      gVisible = NO;
static NSInteger gToken   = 0;

#pragma mark - 状态落盘

static void DIPLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[DIP] %@", msg);

    NSString *line = [NSString stringWithFormat:@"%@ | pid=%d | %@\n", msg, getpid(), [NSDate date]];
    static NSString *chosenPath = nil;
    if (chosenPath) {
        [line writeToFile:chosenPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }
    NSArray<NSString *> *candidates = @[
        @"/var/mobile/Library/Caches/DynamicIslandPro-status.txt",
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"DynamicIslandPro-status.txt"]
    ];
    for (NSString *p in candidates) {
        if ([line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
            chosenPath = p;
            return;
        }
    }
}

#pragma mark - 取窗口场景

static UIWindowScene *DIPWindowScene(void) {
    UIApplication *app = [UIApplication sharedApplication];

    for (UIScene *s in app.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)s;
        if (ws.activationState == UISceneActivationStateForegroundActive) return ws;
    }
    for (UIScene *s in app.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }

    // 兜底：从已有的 window 反查 scene
    for (UIWindow *w in app.windows) {
        if (w.windowScene) return w.windowScene;
    }
    return nil;
}

#pragma mark - 视图

static CGRect DIPCollapsedRect(CGFloat w) {
    return CGRectMake((w - kCollapsedW) / 2.0, kIslandTop, kCollapsedW, kCollapsedH);
}

static CGRect DIPExpandedRect(CGFloat w) {
    CGFloat ew = MIN(w - 36.0, 372.0);
    return CGRectMake((w - ew) / 2.0, kIslandTop, ew, 92.0);
}

static void DIPBuildIfNeeded(void) {
    if (gWindow) return;

    UIWindowScene *scene = DIPWindowScene();
    if (!scene) {
        DIPLog(@"no window scene yet");
        return;
    }

    gWindow = [[UIWindow alloc] initWithWindowScene:scene];
    gWindow.frame = scene.coordinateSpace.bounds;
    gWindow.windowLevel = UIWindowLevelAlert + 1.0;
    gWindow.backgroundColor = [UIColor clearColor];
    gWindow.userInteractionEnabled = NO;
    gWindow.hidden = NO;

    gPill = [[UIView alloc] initWithFrame:DIPCollapsedRect(gWindow.bounds.size.width)];
    gPill.backgroundColor = [UIColor blackColor];
    gPill.layer.cornerRadius = kCollapsedRadius;
    gPill.layer.masksToBounds = YES;
    gPill.alpha = 0.0;
    [gWindow addSubview:gPill];

    gTitle = [[UILabel alloc] initWithFrame:CGRectMake(10.0, 8.0, 106.0, 13.0)];
    gTitle.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    gTitle.textColor = [UIColor whiteColor];
    gTitle.alpha = 0.0;
    [gPill addSubview:gTitle];

    gBody = [[UILabel alloc] initWithFrame:CGRectMake(10.0, 22.0, 106.0, 12.0)];
    gBody.font = [UIFont systemFontOfSize:10.5];
    gBody.textColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    gBody.alpha = 0.0;
    [gPill addSubview:gBody];

    DIPLog(@"window built, level=%d", (int)gWindow.windowLevel);
}

static void DIPShow(NSString *title, NSString *body, BOOL autoHide) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ DIPShow(title, body, autoHide); });
        return;
    }

    DIPBuildIfNeeded();
    if (!gWindow) return;

    gToken++;
    NSInteger token = gToken;
    gVisible = YES;

    gTitle.text = title.length ? title : @"通知";
    gBody.text  = body.length ? body : @"";
    gWindow.hidden = NO;

    CGFloat w = gWindow.bounds.size.width;
    CGRect collapsed = DIPCollapsedRect(w);
    CGRect expanded  = DIPExpandedRect(w);

    gPill.frame = collapsed;
    gPill.layer.cornerRadius = kCollapsedRadius;
    gPill.alpha = 1.0;

    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        gPill.frame = expanded;
        gPill.layer.cornerRadius = 28.0;
        gPill.alpha = 1.0;
        gTitle.alpha = 1.0;
        gBody.alpha = 1.0;
    } completion:nil];

    if (!autoHide) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (token != gToken || !gVisible) return;
        gVisible = NO;
        CGRect collapsed2 = DIPCollapsedRect(gWindow.bounds.size.width);
        [UIView animateWithDuration:0.32 animations:^{
            gPill.frame = collapsed2;
            gPill.layer.cornerRadius = kCollapsedRadius;
            gTitle.alpha = 0.0;
            gBody.alpha = 0.0;
        } completion:^(BOOL finished) {
            gPill.alpha = 0.0;
        }];
    });
}

#pragma mark - KVC 兜底取字段

static NSString *DIPSafeString(id obj, NSArray<NSString *> *keys) {
    for (NSString *k in keys) {
        @try {
            id v = [obj valueForKey:k];
            if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return (NSString *)v;
        } @catch (NSException *e) {}
    }
    return nil;
}

#pragma mark - 手写 hook（不依赖 substrate）

static IMP  gOrigPresent   = NULL;
static BOOL gHookInstalled = NO;
static SEL  gPresentSel    = NULL;

static void DIPPresentReplacement(id self, SEL _cmd, id request) {
    @try {
        NSString *title = DIPSafeString(request, @[@"title", @"notificationTitle", @"header"]);
        NSString *body  = DIPSafeString(request, @[@"message", @"body", @"subtitle"]);
        if (!title.length) title = DIPSafeString(request, @[@"sectionIdentifier", @"bundleIdentifier"]);
        DIPShow(title, body, YES);
    } @catch (NSException *e) {
        DIPLog(@"show exception: %@", e.reason);
    }
    if (gOrigPresent) ((void (*)(id, SEL, id))gOrigPresent)(self, _cmd, request);
}

static BOOL DIPTryInstallHook(void) {
    if (gHookInstalled) return YES;

    NSArray<NSString *> *classes = @[@"SBNotificationBannerDestination",
                                    @"SBBannerManager",
                                    @"SBNotificationBannerViewController"];
    gPresentSel = @selector(presentNotificationRequest:);

    for (NSString *name in classes) {
        Class cls = objc_getClass(name.UTF8String);
        if (!cls) continue;
        Method m = class_getInstanceMethod(cls, gPresentSel);
        if (!m) continue;

        gOrigPresent = method_getImplementation(m);
        method_setImplementation(m, (IMP)DIPPresentReplacement);
        gHookInstalled = YES;
        DIPLog(@"hook installed on %@", name);
        return YES;
    }
    return NO;
}

#pragma mark - 装载

%ctor {
    DIPLog(@"dylib loaded");

    // 自检：6 秒后弹一个测试胶囊，证明注入与窗口都通了
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DIPShow(@"灵动岛通知胶囊", @"已注入 SpringBoard ✅", YES);
    });

    // 通知类可能晚于 dylib 加载，轮询 30 秒尝试装钩子
    for (int i = 0; i < 15; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((2.0 + i * 2.0) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!DIPTryInstallHook()) DIPLog(@"hook class not found yet");
        });
    }
}
