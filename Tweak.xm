// DynamicIslandPro —— 灵动岛通知胶囊（iOS 16 / iPhone 14 Pro）
// v16：日志改为追加写；自动扫描类名含 Banner 的类、找 presentNotification* 方法挂钩；
//      窗口场景多级兜底（connectedScenes → 现有 window → SBWindowSceneManager）。

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

#pragma mark - 日志（追加写，不覆盖）

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

#pragma mark - 窗口场景（多级兜底）

static UIWindowScene *DIPWindowScene(void) {
    UIApplication *app = [UIApplication sharedApplication];

    NSInteger sceneCount = 0;
    for (UIScene *s in app.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        sceneCount++;
        UIWindowScene *ws = (UIWindowScene *)s;
        if (ws.activationState == UISceneActivationStateForegroundActive) {
            DIPLog(@"scene found(active) total=%d", (int)sceneCount);
            return ws;
        }
    }
    for (UIScene *s in app.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            DIPLog(@"scene found(inactive)");
            return (UIWindowScene *)s;
        }
    }

    NSArray *wins = app.windows;
    DIPLog(@"no scene in connectedScenes(count=%d), windows=%d", (int)sceneCount, (int)wins.count);
    for (UIWindow *w in wins) {
        if (w.windowScene) {
            DIPLog(@"scene taken from existing window");
            return w.windowScene;
        }
    }

    Class mgr = objc_getClass("SBWindowSceneManager");
    if (mgr) {
        @try {
            id shared = [(id)mgr performSelector:@selector(sharedInstance)];
            id active = [shared performSelector:@selector(activeDisplayWindowScene)];
            if ([active isKindOfClass:[UIWindowScene class]]) {
                DIPLog(@"scene taken from SBWindowSceneManager");
                return (UIWindowScene *)active;
            }
        } @catch (NSException *e) {
            DIPLog(@"SBWindowSceneManager threw: %@", e.reason);
        }
    }
    DIPLog(@"no window scene at all");
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
    if (!gWindow) {
        DIPLog(@"show aborted: no window");
        return;
    }

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

#pragma mark - 自动扫钩子

static IMP  gOrigPresent   = NULL;
static BOOL gHookInstalled = NO;

static void DIPPresentReplacement(id self, SEL _cmd, id first, id second) {
    @try {
        NSString *title = DIPSafeString(first, @[@"title", @"notificationTitle", @"header"]);
        NSString *body  = DIPSafeString(first, @[@"message", @"body", @"subtitle"]);
        if (!title.length) title = DIPSafeString(first, @[@"sectionIdentifier", @"bundleIdentifier"]);
        DIPShow(title, body, YES);
    } @catch (NSException *e) {
        DIPLog(@"show exception: %@", e.reason);
    }
    if (gOrigPresent) ((void (*)(id, SEL, id, id))gOrigPresent)(self, _cmd, first, second);
}

// 遍历所有类名含 "Banner" 的类，找名字含 "presentNotification" 且只有 3 个参数的方法挂钩
static BOOL DIPScanAndHook(void) {
    if (gHookInstalled) return YES;

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return NO;
    Class *classes = (Class *)malloc(sizeof(Class) * count);
    count = objc_getClassList(classes, count);

    int bannerClasses = 0;
    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        const char *name = class_getName(cls);
        if (!name || !strstr(name, "Banner")) continue;
        bannerClasses++;

        unsigned int mcount = 0;
        Method *methods = class_copyMethodList(cls, &mcount);
        for (unsigned int j = 0; j < mcount; j++) {
            const char *selName = sel_getName(method_getName(methods[j]));
            if (!selName || !strstr(selName, "presentNotification")) continue;

            int argc = (int)method_getNumberOfArguments(methods[j]);
            DIPLog(@"candidate %s -%s argc=%d", name, selName, argc);

            if (argc == 3) {
                gOrigPresent = method_getImplementation(methods[j]);
                method_setImplementation(methods[j], (IMP)DIPPresentReplacement);
                gHookInstalled = YES;
                DIPLog(@"HOOKED %s -%s", name, selName);
                if (methods) free(methods);
                free(classes);
                return YES;
            }
        }
        if (methods) free(methods);
    }

    DIPLog(@"scan done: bannerClasses=%d totalClasses=%d, no hook", bannerClasses, count);
    free(classes);
    return NO;
}

#pragma mark - 装载

%ctor {
    DIPLog(@"=== dylib loaded v16 pid=%d ===", getpid());

    // 自检：6 秒后弹测试胶囊，验证注入 + 窗口 + 动画都通
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DIPShow(@"灵动岛通知胶囊", @"已注入 SpringBoard ✅", YES);
    });

    // 类可能晚于 dylib 出现，前 18 秒内反复尝试扫钩子
    for (int i = 0; i < 6; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((3.0 + i * 3.0) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            DIPScanAndHook();
        });
    }
}
