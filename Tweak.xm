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
#import <dlfcn.h>
#import <stdio.h>

#define DIP_DOMAIN @"com.dynamicislandpro.tweak"
#define DIP_APPS_CACHE @"/var/mobile/Library/Caches/DynamicIslandPro-apps.plist"

static UIWindow *gWindow = nil;
static UIView   *gPill   = nil;
static UIImageView *gIcon = nil;
static UILabel  *gTitle  = nil;
static UILabel  *gBody   = nil;
static UILabel  *gNow    = nil;
static UILabel  *gApp    = nil;
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

static NSString *gLastBundle = nil;
static void DIPHideNow(void);

static void DIPOpenApp(NSString *bundleID) {
    if (!bundleID.length) return;
    @try {
        Class WS = objc_getClass("LSApplicationWorkspace");
        if (!WS) {
            void *h = dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
                             RTLD_LAZY);
            (void)h;
            WS = objc_getClass("LSApplicationWorkspace");
        }
        if (!WS) { DIPLog(@"open app: no LSApplicationWorkspace"); return; }
        id ws = ((id (*)(id, SEL))objc_msgSend)((id)WS, @selector(defaultWorkspace));
        SEL selOpen = NSSelectorFromString(@"openApplicationWithBundleID:");
        if ([ws respondsToSelector:selOpen]) {
            ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, selOpen, bundleID);
            DIPLog(@"open app: %@", bundleID);
        } else {
            SEL selOpenURL = NSSelectorFromString(@"openSensitiveURL:withOptions:");
            id url = [NSURL URLWithString:[@"prefs:root=" stringByAppendingString:bundleID]];
            if ([ws respondsToSelector:selOpenURL]) {
                ((BOOL (*)(id, SEL, id, id))objc_msgSend)(ws, selOpenURL, url, nil);
                DIPLog(@"open url: %@", url);
            }
        }
    } @catch (NSException *e) {
        DIPLog(@"open app exception: %@", e.reason);
    }
}

@interface DIPTapHandler : NSObject
@end

@implementation DIPTapHandler
- (void)handleTap:(UITapGestureRecognizer *)g {
    DIPLog(@"pill tapped: %@", gLastBundle ?: @"-");
    DIPOpenApp(gLastBundle);
    DIPHideNow();
}
@end

static DIPTapHandler *gTapHandler = nil;

@interface DIPWindow : UIWindow
@end

@implementation DIPWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!gVisible || !gPill) return nil;
    CGRect f = [gPill convertRect:gPill.bounds toView:nil];
    if (CGRectContainsPoint(f, point)) return [super hitTest:point withEvent:event];
    return nil;
}
@end

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

static CGFloat DIPCWidth(void)  { return (CGFloat)DIPPrefNum(@"collapsedW", 150.0); }
static CGFloat DIPCHeight(void) { return (CGFloat)DIPPrefNum(@"collapsedH", 38.0); }
static CGFloat DIPRadius(void)  { return (CGFloat)DIPPrefNum(@"cornerRadius", 19.0); }
static CGFloat DIPExpandH(void) { return (CGFloat)DIPPrefNum(@"expandedH", 100.0); }
static NSInteger DIPLayoutStyle(void) { return (NSInteger)DIPPrefNum(@"layoutStyle", 0.0); }

static CGRect DIPCollapsedRect(CGFloat w) {
    if (DIPLayoutStyle() == 2) {
        return CGRectMake((w - 92.0) / 2.0, 13.0, 92.0, 32.0);
    }
    CGFloat cw = DIPCWidth(), ch = DIPCHeight();
    return CGRectMake((w - cw) / 2.0, 10.0, cw, ch);
}

static CGRect DIPExpandedRect(CGFloat w) {
    NSInteger ls = DIPLayoutStyle();
    if (ls == 2) return DIPCollapsedRect(w);
    if (ls == 1) return CGRectMake(20.0, 8.0, w - 40.0, 44.0);
    return CGRectMake(10.0, 1.0, w - 20.0, DIPExpandH());
}

static void DIPApplyStyle(void) {
    gPill.backgroundColor = [DIPBackgroundColor()
        colorWithAlphaComponent:(CGFloat)DIPPrefNum(@"bgAlpha", 1.0)];
    gTitle.textColor = DIPLightPreset() ? [UIColor blackColor] : [UIColor whiteColor];
    gBody.textColor  = DIPLightPreset() ? [UIColor colorWithWhite:0.18 alpha:1.0]
                                        : [UIColor colorWithWhite:0.84 alpha:1.0];
    gNow.textColor = DIPLightPreset() ? [UIColor colorWithWhite:0.45 alpha:1.0]
                                      : [UIColor colorWithWhite:0.55 alpha:1.0];
    gApp.textColor = DIPLightPreset() ? [UIColor blackColor]
                                      : [UIColor colorWithWhite:0.95 alpha:1.0];
}

static void DIPBuildIfNeeded(void) {
    if (gWindow) return;
    UIWindowScene *scene = DIPWindowScene();
    if (!scene) return;

    gWindow = [[DIPWindow alloc] initWithWindowScene:scene];
    gWindow.frame = scene.coordinateSpace.bounds;
    gWindow.windowLevel = UIWindowLevelAlert + 1.0;
    gWindow.backgroundColor = [UIColor clearColor];
    gWindow.userInteractionEnabled = YES;
    gWindow.hidden = NO;

    gPill = [[UIView alloc] initWithFrame:DIPCollapsedRect(gWindow.bounds.size.width)];
    gPill.layer.cornerRadius = DIPRadius();
    gPill.layer.masksToBounds = YES;
    gPill.alpha = 0.0;
    gPill.userInteractionEnabled = YES;
    [gWindow addSubview:gPill];

    gTapHandler = [[DIPTapHandler alloc] init];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:gTapHandler
                                                                          action:@selector(handleTap:)];
    [gPill addGestureRecognizer:tap];

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

    gNow = [[UILabel alloc] initWithFrame:CGRectZero];
    gNow.font = [UIFont systemFontOfSize:11.5];
    gNow.alpha = 0.0;
    [gPill addSubview:gNow];

    gApp = [[UILabel alloc] initWithFrame:CGRectZero];
    gApp.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    gApp.textAlignment = NSTextAlignmentRight;
    gApp.alpha = 0.0;
    [gPill addSubview:gApp];

    DIPApplyStyle();
    DIPLog(@"window built frame=%@ level=%d", NSStringFromCGRect(gWindow.frame), (int)gWindow.windowLevel);
}

static void DIPLayoutContents(CGRect bounds) {
    CGFloat w = bounds.size.width, h = bounds.size.height;
    NSInteger ls = DIPLayoutStyle();
    BOOL hasIcon = (gIcon.image != nil);

    if (ls == 2) {            // 迷你：只显示图标
        CGFloat s = MIN(26.0, h - 8.0);
        gIcon.frame = CGRectMake((w - s) / 2.0, (h - s) / 2.0, s, s);
        gIcon.layer.cornerRadius = s / 3.0;
        gNow.hidden = YES; gApp.hidden = YES;
        gTitle.hidden = YES; gBody.hidden = YES;
        return;
    }

    gNow.hidden = NO; gApp.hidden = NO;
    gTitle.hidden = NO;

    BOOL big = (h > 60.0);
    if (big) {                // 标准（展开态）
        CGFloat is = 44.0;
        gIcon.frame = CGRectMake(16.0, (h - is) / 2.0, is, is);
        gIcon.layer.cornerRadius = 10.0;
        CGFloat x = hasIcon ? (16.0 + is + 12.0) : 18.0;
        CGFloat tw = w - x - 16.0;
        gNow.frame = CGRectMake(x, 16.0, 80.0, 15.0);
        gApp.frame = CGRectMake(w - 16.0 - 150.0, 15.0, 150.0, 16.0);
        gTitle.frame = CGRectMake(x, 33.0, tw, 21.0);
        gBody.frame  = CGRectMake(x, 58.0, tw, 18.0);
        gTitle.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        gBody.font  = [UIFont systemFontOfSize:13.0];
        gNow.font   = [UIFont systemFontOfSize:11.5];
        gApp.font   = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        return;
    }

    if (h > 42.0) {           // 紧凑：图标 + 单行标题
        CGFloat is = 28.0;
        gIcon.frame = CGRectMake(11.0, (h - is) / 2.0, is, is);
        gIcon.layer.cornerRadius = 8.0;
        CGFloat x = hasIcon ? (11.0 + is + 8.0) : 12.0;
        gTitle.frame = CGRectMake(x, (h - 18.0) / 2.0, w - x - 12.0, 18.0);
        gTitle.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
        gNow.hidden = YES; gApp.hidden = YES; gBody.hidden = YES;
        return;
    }

    CGFloat is = 26.0;        // 标准（收起态）
    gIcon.frame = CGRectMake(11.0, (h - is) / 2.0, is, is);
    gIcon.layer.cornerRadius = 7.0;
    CGFloat x = hasIcon ? (11.0 + is + 9.0) : 12.0;
    gTitle.frame = CGRectMake(x, (h - 15.0) / 2.0, w - x - 12.0, 15.0);
    gTitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    gNow.hidden = YES; gApp.hidden = YES; gBody.hidden = YES;
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
    gLastBundle = bundleID;

    gTitle.text = title.length ? title : @"通知";
    gBody.text  = body.length ? body : @"";
    gBody.hidden = (body.length == 0);
    gNow.text = @"现在";
    gApp.text = bundleID.length ? DIPAppDisplayName(bundleID) : @"通知";

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
        gPill.layer.cornerRadius = DIPRadius() + (DIPLayoutStyle() == 0 ? 17.0 : 0.0);
        gIcon.alpha = 1.0;
        gTitle.alpha = 1.0;
        gBody.alpha = (gBody.hidden ? 0.0 : 1.0);
        gNow.alpha = (gNow.hidden ? 0.0 : 1.0);
        gApp.alpha = (gApp.hidden ? 0.0 : 1.0);
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
            gNow.alpha = 0.0;
            gApp.alpha = 0.0;
        } completion:^(BOOL finished) { gPill.alpha = 0.0; }];
    });
}

#pragma mark - 取值与过滤

static void DIPHideNow(void) {
    gToken++;
    gVisible = NO;
    [UIView animateWithDuration:0.25 animations:^{
        gPill.alpha = 0.0;
        gIcon.alpha = 0.0;
        gTitle.alpha = 0.0;
        gBody.alpha = 0.0;
        gNow.alpha = 0.0;
        gApp.alpha = 0.0;
    }];
}

static void DIPEnsureDefaults(void) {
    CFStringRef dom = (CFStringRef)DIP_DOMAIN;
    if (!CFPreferencesCopyAppValue(CFSTR("filterMode"), dom)) {
        CFPreferencesSetAppValue(CFSTR("filterMode"), (__bridge CFTypeRef)@(1), dom);
    }
    NSArray *ids = @[@"com.tencent.xin", @"com.tencent.mqq"];
    for (NSString *bid in ids) {
        NSString *key = [@"app_" stringByAppendingString:bid];
        if (!CFPreferencesCopyAppValue((__bridge CFStringRef)key, dom)) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFTypeRef)@(YES), dom);
        }
    }
    CFPreferencesAppSynchronize(dom);
}

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

#pragma mark - 设置页入口注入（不依赖 PreferenceLoader）

static id DIPMakeSpecifier(NSString *name, NSInteger cell) {
    Class PS = objc_getClass("PSSpecifier");
    if (!PS) return nil;
    SEL sel = NSSelectorFromString(@"preferenceSpecifierNamed:target:set:get:detail:cell:edit:");
    if (![PS respondsToSelector:sel]) return nil;
    id (*fn)(id, SEL, id, id, id, id, id, NSInteger, id) =
        (id (*)(id, SEL, id, id, id, id, id, NSInteger, id))objc_msgSend;
    return fn((id)PS, sel, name, nil, nil, nil, nil, cell, nil);
}

static BOOL DIPArrayHasName(NSArray *arr, NSString *name) {
    for (id s in arr) {
        @try {
            id n = [s valueForKey:@"name"];
            if ([n isKindOfClass:[NSString class]] && [(NSString *)n isEqualToString:name]) return YES;
        } @catch (NSException *e) {}
    }
    return NO;
}

static int gSpecCalls = 0;
static NSMutableSet *gHookedNames = nil;

static id DIPInjectIfNeeded(id self, id arr, NSString *hookedClass) {
    @try {
        if (gSpecCalls < 30) {
            gSpecCalls++;
            DIPLog(@"spec call %@ via %@ count=%lu",
                   NSStringFromClass([self class]), hookedClass, (unsigned long)[arr count]);
        }
        if (![arr isKindOfClass:[NSArray class]]) return arr;
        if (DIPArrayHasName(arr, @"灵动岛通知胶囊")) return arr;

        id link = DIPMakeSpecifier(@"灵动岛通知胶囊", 13);
        if (!link) { DIPLog(@"inject: cannot build specifier"); return arr; }
        [link setProperty:@"DynamicIslandProPrefs" forKey:@"bundle"];

        id group = DIPMakeSpecifier(@"", 0);
        NSMutableArray *m = [arr isKindOfClass:[NSMutableArray class]] ? (NSMutableArray *)arr : [arr mutableCopy];
        if (!m) m = [NSMutableArray array];
        if (group) [m addObject:group];
        [m addObject:link];
        DIPLog(@"INJECTED entry into %@ (via %@) rows=%lu",
               NSStringFromClass([self class]), hookedClass, (unsigned long)[m count]);
        return m;
    } @catch (NSException *e) {
        DIPLog(@"inject exception: %@", [e reason]);
    }
    return arr;
}

static BOOL DIPClassImplements(Class c, SEL sel) {
    unsigned int n = 0;
    Method *list = class_copyMethodList(c, &n);
    BOOL found = NO;
    for (unsigned int i = 0; i < n; i++) {
        if (method_getName(list[i]) == sel) { found = YES; break; }
    }
    free(list);
    return found;
}

static void DIPHookSpecifiers(Class c) {
    if (!c) return;
    NSString *cn = NSStringFromClass(c);
    if (!gHookedNames) gHookedNames = [NSMutableSet set];
    if ([gHookedNames containsObject:cn]) return;

    SEL sel = NSSelectorFromString(@"specifiers");
    if (!DIPClassImplements(c, sel)) {
        DIPLog(@"%@ 继承 specifiers，跳过", cn);
        return;
    }
    Method m = class_getInstanceMethod(c, sel);
    if (!m) { DIPLog(@"%@ 无 specifiers", cn); return; }

    IMP orig = method_getImplementation(m);
    IMP rep = imp_implementationWithBlock(^(id self) {
        id arr = ((id (*)(id, SEL))orig)(self, sel);
        return DIPInjectIfNeeded(self, arr, cn);
    });
    method_setImplementation(m, rep);
    [gHookedNames addObject:cn];
    DIPLog(@"hooked %@ specifiers", cn);
}

static void DIPInstallSettingsHooks(void) {
    NSArray *exact = @[@"PrefsListController", @"PSUIPrefsListController", @"PSListController"];
    for (NSString *cn in exact) {
        Class c = objc_getClass(cn.UTF8String);
        if (!c) { DIPLog(@"waiting for class %@", cn); continue; }
        DIPHookSpecifiers(c);
    }
    // 顺带尝试所有名字里带 ListController 的类（只在 Root 语境里注入）
    int total = objc_getClassList(NULL, 0);
    if (total <= 0) return;
    Class *list = (Class *)malloc(sizeof(Class) * (size_t)total);
    if (!list) return;
    total = objc_getClassList(list, total);
    for (int i = 0; i < total; i++) {
        NSString *cn = NSStringFromClass(list[i]);
        if ([cn hasSuffix:@"RootListController"] || [cn isEqualToString:@"PrefsListController"]) {
            DIPHookSpecifiers(list[i]);
        }
    }
    free(list);
}

static BOOL gKickReloaded = NO;

static void DIPKickReload(void) {
    if (gKickReloaded) return;
    @try {
        UIWindow *key = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
        if (!key) return;
        NSMutableArray *q = [NSMutableArray array];
        if ([key rootViewController]) [q addObject:[key rootViewController]];
        while (q.count) {
            id vc = [q objectAtIndex:0];
            [q removeObjectAtIndex:0];
            NSString *cn = NSStringFromClass([vc class]);
            if ([cn isEqualToString:@"PSUIPrefsListController"] || [cn isEqualToString:@"PrefsListController"]) {
                SEL rs = NSSelectorFromString(@"reloadSpecifiers");
                if ([vc respondsToSelector:rs]) {
                    ((void (*)(id, SEL))objc_msgSend)(vc, rs);
                    gKickReloaded = YES;
                    DIPLog(@"reload sent to %@", cn);
                }
                return;
            }
            id kids = nil;
            @try { kids = [vc valueForKey:@"viewControllers"]; } @catch (NSException *e) {}
            if (!kids) { @try { kids = [vc valueForKey:@"childViewControllers"]; } @catch (NSException *e) {} }
            for (id k in kids) [q addObject:k];
        }
    } @catch (NSException *e) {
        DIPLog(@"kick exception: %@", [e reason]);
    }
}

static void DIPProbeRoot(void) {
    @try {
        UIWindow *key = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
        if (!key) { DIPLog(@"probe: no key window"); return; }
        id root = [key rootViewController];
        DIPLog(@"probe: rootVC=%@", NSStringFromClass([root class]));
        NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
        int depth = 0;
        while (stack.count && depth < 24) {
            id vc = [stack objectAtIndex:0];
            [stack removeObjectAtIndex:0];
            depth++;
            NSString *cn = NSStringFromClass([vc class]);
            if ([cn hasPrefix:@"PS"] || [cn hasSuffix:@"ListController"]) {
                DIPLog(@"probe vc: %@", cn);
            }
            id kids = nil;
            @try { kids = [vc valueForKey:@"viewControllers"]; } @catch (NSException *e) {}
            if (!kids) { @try { kids = [vc valueForKey:@"childViewControllers"]; } @catch (NSException *e) {} }
            for (id k in kids) [stack addObject:k];
        }
    } @catch (NSException *e) {
        DIPLog(@"probe exception: %@", [e reason]);
    }
}

static void DIPDumpClasses(void) {
    int total = objc_getClassList(NULL, 0);
    if (total <= 0) return;
    Class *list = (Class *)malloc(sizeof(Class) * (size_t)total);
    if (!list) return;
    total = objc_getClassList(list, total);
    NSMutableString *buf = [NSMutableString string];
    int n = 0;
    for (int i = 0; i < total && n < 80; i++) {
        NSString *cn = NSStringFromClass(list[i]);
        if ([cn hasPrefix:@"PS"] ||
            [cn rangeOfString:@"RootList"].location != NSNotFound) {
            [buf appendFormat:@"%@ ", cn];
            n++;
        }
    }
    free(list);
    DIPLog(@"candidate classes: %@", buf);
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
    NSString *proc = [[NSProcessInfo processInfo] processName];
    DIPLog(@"=== dylib loaded v23 (%@) pid=%d ===", proc, getpid());

    if (![proc isEqualToString:@"SpringBoard"]) {
        DIPInstallSettingsHooks();
        for (int i = 1; i <= 6; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                DIPInstallSettingsHooks();
                if (i == 3) DIPDumpClasses();
                if (i == 4) DIPProbeRoot();
                if (i >= 2) DIPKickReload();
            });
        }
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ DIPWriteAppList(); });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ DIPEnsureDefaults(); });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (DIPPrefBool(@"enabled", YES))
            DIPShow(@"灵动岛通知胶囊", @"v23 已注入 SpringBoard ✅", @"com.tencent.xin", YES);
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
