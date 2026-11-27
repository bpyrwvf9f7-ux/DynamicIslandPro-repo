// DynamicIslandPro —— 灵动岛通知胶囊（iOS 16 / iPhone 14 Pro）
// v17：按实测签名挂钩 SBNotificationBannerDestination
//      -_presentNotificationViewController:modal:forRequest:completion:
//      并从 NCNotificationRequest.content 里取标题/正文。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <unistd.h>
#import <stdio.h>

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

#pragma mark - 日志（追加写）

static NSString *gLogPath = nil;

static void DIPLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[DIP] %@", msg);

    if (!gLogPath) {
        NSString *a = @"/var/mobile/Library/Caches/DynamicIslandPro-status.txt";
        if (access(a.UTF8String, W_OK) == 0) {
            gLogPath = a;
        } else {
            gLogPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DynamicIslandPro-status.txt"];
        }
    }
    FILE *f = fopen(gLogPath.UTF8String, "a");
    if (!f) return;
    fprintf(f, "%s | pid=%d\n", msg.UTF8String, getpid());
    fclose(f);
}

#pragma mark - 窗口场景

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
    for (UIWindow *w in app.windows) {
        if (w.windowScene) return w.windowScene;
    }
    Class mgr = objc_getClass("SBWindowSceneManager");
    if (mgr) {
        @try {
            id shared = [(id)mgr performSelector:@selector(sharedInstance)];
            id active = [shared performSelector:@selector(activeDisplayWindowScene)];
            if ([active isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)active;
        } @catch (NSException *e) {}
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
    if (!scene) return;

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

    DIPLog(@"window built frame=%@ level=%d", NSStringFromCGRect(gWindow.frame), (int)gWindow.windowLevel);
}

static void DIPShow(NSString *title, NSString *body, BOOL autoHide) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ DIPShow(title, body, autoHide); });
        return;
    }

    DIPBuildIfNeeded();
    if (!gWindow) { DIPLog(@"show aborted: no window"); return; }

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
    DIPLog(@"showing: %@", gTitle.text);

    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        gPill.frame = expanded;
        gPill.layer.cornerRadius = 28.0;
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
        } completion:^(BOOL finished) { gPill.alpha = 0.0; }];
    });
}

#pragma mark - 从 NCNotificationRequest 取字段

static NSString *DIPStr(id obj, NSString *key) {
    @try {
        id v = [obj valueForKey:key];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return (NSString *)v;
    } @catch (NSException *e) {}
    return nil;
}

static void DIPExtractAndShow(id request) {
    NSString *title = nil, *body = nil, *bundle = nil;

    if (request) {
        id content = nil, header = nil;
        @try { content = [request valueForKey:@"content"]; } @catch (NSException *e) {}
        if (content) {
            title = DIPStr(content, @"title");
            body  = DIPStr(content, @"message");
            if (!body.length) body = DIPStr(content, @"subtitle");
        }
        @try { header = [request valueForKey:@"header"]; } @catch (NSException *e) {}
        if (!title.length && header) title = DIPStr(header, @"title");

        bundle = DIPStr(request, @"sectionIdentifier");
        if (!bundle.length) bundle = DIPStr(request, @"bundleIdentifier");
        if (!title.length) title = DIPStr(request, @"title");
        if (!body.length) body = DIPStr(request, @"message");
    }

    if (title.length || body.length) {
        DIPShow(title, body, YES);
    } else {
        DIPShow(bundle.length ? bundle : @"新通知", @"", YES);
    }
}

#pragma mark - 钩子

static IMP  gOrigPresent   = NULL;
static BOOL gHookInstalled = NO;

// - (void)_presentNotificationViewController:(id)vc modal:(BOOL)modal
//        forRequest:(id)request completion:(id)completion
static void DIPPresentReplacement(id self, SEL _cmd, id vc, BOOL modal, id request, id completion) {
    @try {
        DIPLog(@"HOOK fired, request class=%s",
               request ? class_getName(object_getClass(request)) : "nil");
        DIPExtractAndShow(request);
    } @catch (NSException *e) {
        DIPLog(@"hook body exception: %@", e.reason);
    }
    if (gOrigPresent) {
        ((void (*)(id, SEL, id, BOOL, id, id))gOrigPresent)(self, _cmd, vc, modal, request, completion);
    }
}

static BOOL DIPInstallHook(void) {
    if (gHookInstalled) return YES;

    Class cls = objc_getClass("SBNotificationBannerDestination");
    if (!cls) { DIPLog(@"SBNotificationBannerDestination missing"); return NO; }

    SEL sel = NSSelectorFromString(@"_presentNotificationViewController:modal:forRequest:completion:");
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { DIPLog(@"target selector missing"); return NO; }

    DIPLog(@"installing hook, argc=%d", (int)method_getNumberOfArguments(m));
    gOrigPresent = method_getImplementation(m);
    method_setImplementation(m, (IMP)DIPPresentReplacement);
    gHookInstalled = YES;
    DIPLog(@"HOOKED -_presentNotificationViewController:modal:forRequest:completion:");
    return YES;
}

#pragma mark - 装载

%ctor {
    DIPLog(@"=== dylib loaded v17 pid=%d ===", getpid());

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DIPShow(@"灵动岛通知胶囊", @"已注入 SpringBoard ✅", YES);
    });

    for (int i = 0; i < 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((2.0 + i * 2.0) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            DIPInstallHook();
        });
    }
}
