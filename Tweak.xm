// DynamicIslandPro —— 灵动岛通知胶囊（iOS 16 / iPhone 14 Pro）
// v18：1) 胶囊显示 App 图标与应用名
//      2) 接管后隐藏系统原生横幅（不再重复显示）
//      3) 读设置页的开关 / 样式 / 时长 / 动画 / 按 App 过滤
//      4) 修日志路径判定

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <unistd.h>
#import <stdio.h>

#define DIP_DOMAIN @"com.dynamicislandpro.tweak"
#define DIP_APPS_CACHE @"/var/mobile/Library/Caches/DynamicIslandPro-apps.plist"

static UIWindow *gWindow = nil;
static UIView   *gPill   = nil;
static UIImageView *gIcon = nil;
static UILabel  *gTitle  = nil;
static UILabel  *gBody   = nil;
static BOOL      gVisible = NO;
static NSInteger gToken   = 0;

#pragma mark - 日志

static NSString *gLogPath = nil;

static void DIPLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[DIP] %@", msg);

    if (!gLogPath) {
        if (access("/var/mobile/Library/Caches", W_OK) == 0)
            gLogPath = @"/var/mobile/Library/Caches/DynamicIslandPro-status.txt";
        else
            gLogPath = @"/private/var/tmp/DynamicIslandPro-status.txt";
    }
    FILE *f = fopen(gLogPath.UTF8String, "a");
    if (!f) return;
    fprintf(f, "%s | pid=%d\n", msg.UTF8String, getpid());
    fclose(f);
}

#pragma mark - 偏好

static id DIPPref(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                          (__bridge CFStringRef)DIP_DOMAIN);
}

static double DIPPrefNum(NSString *key, double def) {
    id v = DIPPref(key);
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
}

static BOOL DIPPrefBool(NSString *key, BOOL def) {
    id v = DIPPref(key);
    return v ? [v boolValue] : def;
}

#pragma mark - App 信息

static NSString *DIPInfoValue(NSDictionary *info, NSString *key) {
    id v = info[key];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static NSString *DIPFindBundlePath(NSString *bundleID) {
    static NSMutableDictionary *cache = nil;
    static NSArray *roots = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (!roots) roots = @[@"/var/containers/Bundle/Application",
                          @"/var/mobile/Containers/Bundle/Application",
                          @"/Applications",
                          @"/var/jb/Applications"];
    if (cache[bundleID]) return cache[bundleID];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *found = nil;
    for (NSString *root in roots) {
        for (NSString *d in [fm contentsOfDirectoryAtPath:root error:nil]) {
            NSString *p = [root stringByAppendingPathComponent:d];
            for (NSString *e in [fm contentsOfDirectoryAtPath:p error:nil]) {
                if (![e hasSuffix:@".app"]) continue;
                NSString *appPath = [p stringByAppendingPathComponent:e];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                                      [appPath stringByAppendingPathComponent:@"Info.plist"]];
                NSString *bid = DIPInfoValue(info, @"CFBundleIdentifier");
                if (bid) cache[bid] = appPath;
                if ([bid isEqualToString:bundleID]) { found = appPath; break; }
            }
            if (found) break;
        }
        if (found) break;
    }
    return found;
}

static NSString *DIPAppDisplayName(NSString *bundleID) {
    NSString *p = DIPFindBundlePath(bundleID);
    if (!p) return nil;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                          [p stringByAppendingPathComponent:@"Info.plist"]];
    return DIPInfoValue(info, @"CFBundleDisplayName") ?: DIPInfoValue(info, @"CFBundleName");
}

static UIImage *DIPAppIcon(NSString *bundleID) {
    NSString *p = DIPFindBundlePath(bundleID);
    if (!p) return nil;

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                          [p stringByAppendingPathComponent:@"Info.plist"]];
    NSArray *names = nil;
    id icons = info[@"CFBundleIcons"];
    if ([icons isKindOfClass:[NSDictionary class]]) {
        id primary = icons[@"CFBundlePrimaryIcon"];
        if ([primary isKindOfClass:[NSDictionary class]])
            names = primary[@"CFBundleIconFiles"];
    }
    if (![names isKindOfClass:[NSArray class]]) {
        id legacy = info[@"CFBundleIconFiles"];
        if ([legacy isKindOfClass:[NSArray class]]) names = legacy;
    }
    if (![names isKindOfClass:[NSArray class]] || names.count == 0) {
        id single = info[@"CFBundleIconFile"];
        if ([single isKindOfClass:[NSString class]]) names = @[single];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    UIImage *best = nil;
    CGFloat bestArea = 0;

    for (NSString *base in names) {
        NSString *stem = [base stringByDeletingPathExtension];
        for (NSString *suffix in @[@"@3x.png", @"@2x.png", @".png"]) {
            NSString *path = [p stringByAppendingPathComponent:[stem stringByAppendingString:suffix]];
            if (![fm fileExistsAtPath:path]) continue;
            UIImage *img = [UIImage imageWithContentsOfFile:path];
            if (!img) continue;
            CGFloat area = img.size.width * img.size.height;
            if (area > bestArea) { best = img; bestArea = area; }
        }
    }
    if (!best) {
        for (NSString *f in [fm contentsOfDirectoryAtPath:p error:nil]) {
            if (![f.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
            UIImage *img = [UIImage imageWithContentsOfFile:[p stringByAppendingPathComponent:f]];
            if (!img) continue;
            CGFloat area = img.size.width * img.size.height;
            if (area > bestArea) { best = img; bestArea = area; }
        }
    }
    return best;
}

static void DIPWriteAppList(void) {
    NSMutableArray *list = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *roots = @[@"/var/containers/Bundle/Application",
                       @"/var/mobile/Containers/Bundle/Application",
                       @"/Applications",
                       @"/var/jb/Applications"];
    for (NSString *root in roots) {
        for (NSString *d in [fm contentsOfDirectoryAtPath:root error:nil]) {
            NSString *dirPath = [root stringByAppendingPathComponent:d];
            for (NSString *e in [fm contentsOfDirectoryAtPath:dirPath error:nil]) {
                if (![e hasSuffix:@".app"]) continue;
                NSString *appPath = [dirPath stringByAppendingPathComponent:e];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                                      [appPath stringByAppendingPathComponent:@"Info.plist"]];
                NSString *bid = DIPInfoValue(info, @"CFBundleIdentifier");
                if (!bid || [bid hasPrefix:@"com.apple."]) continue;
                NSString *name = DIPInfoValue(info, @"CFBundleDisplayName")
                              ?: DIPInfoValue(info, @"CFBundleName") ?: bid;
                [list addObject:@{@"id": bid, @"name": name}];
            }
        }
    }
    [list writeToFile:DIP_APPS_CACHE atomically:YES];
    DIPLog(@"app list written: %lu", (unsigned long)list.count);
}

#pragma mark - 窗口

static UIWindowScene *DIPWindowScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *s in app.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
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

#pragma mark - 样式

static UIColor *DIPBackgroundColor(void) {
    switch ((NSInteger)DIPPrefNum(@"stylePreset", 0)) {
        case 1: return [UIColor colorWithWhite:0.11 alpha:1.0];
        case 2: return [UIColor colorWithWhite:0.97 alpha:1.0];
        case 3: return [UIColor colorWithRed:0.05 green:0.12 blue:0.26 alpha:1.0];
        default: return [UIColor blackColor];
    }
}

static BOOL DIPLightPreset(void) { return (NSInteger)DIPPrefNum(@"stylePreset", 0) == 2; }

static CGFloat DIPCWidth(void)  { return (CGFloat)DIPPrefNum(@"collapsedW", 126.0); }
static CGFloat DIPCHeight(void) { return (CGFloat)DIPPrefNum(@"collapsedH", 37.0); }
static CGFloat DIPRadius(void)  { return (CGFloat)DIPPrefNum(@"cornerRadius", 18.5); }
static CGFloat DIPExpandH(void) { return (CGFloat)DIPPrefNum(@"expandedH", 88.0); }

static CGRect DIPCollapsedRect(CGFloat w) {
    CGFloat cw = DIPCWidth(), ch = DIPCHeight();
    return CGRectMake((w - cw) / 2.0, 11.0, cw, ch);
}

static CGRect DIPExpandedRect(CGFloat w) {
    CGFloat ew = MIN(w - 28.0, 372.0);
    return CGRectMake((w - ew) / 2.0, 11.0, ew, DIPExpandH());
}

static void DIPApplyStyle(void) {
    gPill.backgroundColor = [DIPBackgroundColor()
        colorWithAlphaComponent:(CGFloat)DIPPrefNum(@"bgAlpha", 1.0)];
    gTitle.textColor = DIPLightPreset() ? [UIColor blackColor] : [UIColor whiteColor];
    gBody.textColor  = DIPLightPreset() ? [UIColor colorWithWhite:0.18 alpha:1.0]
                                        : [UIColor colorWithWhite:0.84 alpha:1.0];
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
    gPill.layer.cornerRadius = DIPRadius();
    gPill.layer.masksToBounds = YES;
    gPill.alpha = 0.0;
    [gWindow addSubview:gPill];

    gIcon = [[UIImageView alloc] initWithFrame:CGRectMake(11, 5, 26, 26)];
    gIcon.contentMode = UIViewContentModeScaleAspectFill;
    gIcon.layer.cornerRadius = 6.5;
    gIcon.layer.masksToBounds = YES;
    gIcon.alpha = 0.0;
    [gPill addSubview:gIcon];

    gTitle = [[UILabel alloc] initWithFrame:CGRectMake(46, 8, 100, 15)];
    gTitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    gTitle.alpha = 0.0;
    [gPill addSubview:gTitle];

    gBody = [[UILabel alloc] initWithFrame:CGRectMake(46, 24, 100, 14)];
    gBody.font = [UIFont systemFontOfSize:11.0];
    gBody.alpha = 0.0;
    [gPill addSubview:gBody];

    DIPApplyStyle();
    DIPLog(@"window built frame=%@ level=%d", NSStringFromCGRect(gWindow.frame), (int)gWindow.windowLevel);
}

static void DIPLayoutContents(CGRect bounds) {
    BOOL hasIcon = (gIcon.image != nil);
    CGFloat x = 11.0;
    if (hasIcon) {
        gIcon.frame = CGRectMake(11, (bounds.size.height - 26.0) / 2.0, 26, 26);
        x = 11 + 26 + 9;
    }
    CGFloat textW = bounds.size.width - x - 13.0;
    CGFloat titleH = 15.0, bodyH = 14.0, gap = 2.0;
    CGFloat total = titleH + gap + bodyH;
    CGFloat y0 = (bounds.size.height - total) / 2.0;
    gTitle.frame = CGRectMake(x, y0, textW, titleH);
    gBody.frame  = CGRectMake(x, y0 + titleH + gap, textW, bodyH);
}

static void DIPShow(NSString *title, NSString *body, NSString *bundleID, BOOL autoHide) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ DIPShow(title, body, bundleID, autoHide); });
        return;
    }
    DIPBuildIfNeeded();
    if (!gWindow) { DIPLog(@"show aborted: no window"); return; }

    DIPApplyStyle();
    gToken++;
    NSInteger token = gToken;
    gVisible = YES;

    UIImage *icon = bundleID.length ? DIPAppIcon(bundleID) : nil;
    gIcon.image = icon;
    gIcon.hidden = (icon == nil);

    gTitle.text = title.length ? title : @"通知";
    gBody.text  = body.length ? body : @"";
    gBody.hidden = (body.length == 0);

    CGFloat w = gWindow.bounds.size.width;
    CGRect collapsed = DIPCollapsedRect(w);
    CGRect expanded  = DIPExpandedRect(w);

    gPill.frame = collapsed;
    gPill.layer.cornerRadius = DIPRadius();
    gPill.alpha = 1.0;
    DIPLayoutContents(collapsed);
    DIPLog(@"showing: %@ <%@>", gTitle.text, bundleID ?: @"-");

    NSInteger anim = (NSInteger)DIPPrefNum(@"animStyle", 0);
    void (^expand)(void) = ^{
        gPill.frame = expanded;
        DIPLayoutContents(expanded);
        gPill.layer.cornerRadius = DIPRadius() + 9.0;
        gIcon.alpha = 1.0;
        gTitle.alpha = 1.0;
        gBody.alpha = 1.0;
    };

    if (anim == 1) {
        [UIView animateWithDuration:0.25 animations:expand];
    } else if (anim == 2) {
        expand();
    } else {
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.82
              initialSpringVelocity:0.5
                              options:UIViewAnimationOptionAllowUserInteraction
                           animations:expand completion:nil];
    }

    if (!autoHide) return;
    double duration = DIPPrefNum(@"duration", 3.4);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (token != gToken || !gVisible) return;
        gVisible = NO;
        CGRect collapsed2 = DIPCollapsedRect(gWindow.bounds.size.width);
        [UIView animateWithDuration:0.32 animations:^{
            gPill.frame = collapsed2;
            gPill.layer.cornerRadius = DIPRadius();
            gIcon.alpha = 0.0;
            gTitle.alpha = 0.0;
            gBody.alpha = 0.0;
        } completion:^(BOOL finished) { gPill.alpha = 0.0; }];
    });
}

#pragma mark - 取值与过滤

static NSString *DIPStr(id obj, NSString *key) {
    @try {
        id v = [obj valueForKey:key];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return (NSString *)v;
    } @catch (NSException *e) {}
    return nil;
}

static BOOL DIPPassFilter(NSString *bundleID) {
    NSInteger mode = (NSInteger)DIPPrefNum(@"filterMode", 0);
    if (mode == 0) return YES;
    if (!bundleID.length) return NO;
    id v = DIPPref([@"app_" stringByAppendingString:bundleID]);
    BOOL selected = v ? [v boolValue] : NO;
    return (mode == 1) ? selected : !selected;
}

static void DIPExtractAndShow(id request) {
    if (!DIPPrefBool(@"enabled", YES)) { DIPLog(@"skip: disabled"); return; }

    NSString *title = nil, *body = nil, *bundle = nil;
    if (request) {
        id content = nil;
        @try { content = [request valueForKey:@"content"]; } @catch (NSException *e) {}
        if (content) {
            title = DIPStr(content, @"title");
            body  = DIPStr(content, @"message");
            if (!body.length) body = DIPStr(content, @"subtitle");
        }
        bundle = DIPStr(request, @"sectionIdentifier");
        if (!bundle.length) bundle = DIPStr(request, @"bundleIdentifier");
        if (!title.length) title = DIPStr(request, @"title");
        if (!body.length) body = DIPStr(request, @"message");
    }

    if (bundle.length && !DIPPassFilter(bundle)) { DIPLog(@"skip: filtered %@", bundle); return; }
    if (!title.length && bundle.length) title = DIPAppDisplayName(bundle);
    if (!title.length) title = @"通知";

    DIPShow(title, body, bundle, YES);
}

#pragma mark - 隐藏系统原生横幅

static void DIPHideNativeBanner(id destination, id bannerVC, id request) {
    UIViewController *vc = (UIViewController *)bannerVC;
    @try {
        vc.view.hidden = YES;
        vc.view.alpha = 0.0;
        CGRect f = vc.view.frame;
        f.origin.y = -(f.size.height + 10.0);
        vc.view.frame = f;
    } @catch (NSException *e) {
        DIPLog(@"hide banner exception: %@", e.reason);
    }

    SEL dismiss = NSSelectorFromString(@"dismissNotificationRequest:");
    if ([destination respondsToSelector:dismiss]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                void (*fn)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
                fn(destination, dismiss, request);
            } @catch (NSException *e) {}
        });
    }
}

#pragma mark - 钩子

static IMP  gOrigPresent = NULL;
static BOOL gHookInstalled = NO;

static void DIPPresentReplacement(id self, SEL _cmd, id vc, BOOL modal, id request, id completion) {
    BOOL handled = NO;
    @try {
        DIPLog(@"HOOK fired, request class=%s",
               request ? class_getName(object_getClass(request)) : "nil");
        DIPExtractAndShow(request);
        handled = DIPPrefBool(@"enabled", YES);
    } @catch (NSException *e) {
        DIPLog(@"hook body exception: %@", e.reason);
    }

    if (gOrigPresent)
        ((void (*)(id, SEL, id, BOOL, id, id))gOrigPresent)(self, _cmd, vc, modal, request, completion);

    if (handled && DIPPrefBool(@"hideNative", YES))
        DIPHideNativeBanner(self, vc, request);
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
    DIPLog(@"=== dylib loaded v18 pid=%d ===", getpid());

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ DIPWriteAppList(); });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (DIPPrefBool(@"enabled", YES))
            DIPShow(@"灵动岛通知胶囊", @"v18 已注入 SpringBoard ✅", @"com.tencent.xin", YES);
    });

    for (int i = 0; i < 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((2.0 + i * 2.0) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ DIPInstallHook(); });
    }

    static int token = 0;
    notify_register_dispatch("com.dynamicislandpro.test", &token, dispatch_get_main_queue(),
                             ^(int t) {
        DIPShow(@"灵动岛通知胶囊", @"测试按钮生效 ✅", @"com.tencent.xin", YES);
    });
}
