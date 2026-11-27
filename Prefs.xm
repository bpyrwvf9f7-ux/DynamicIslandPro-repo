// DynamicIslandPro 设置页（PreferenceBundle）
// 自带 UIViewController + UITableView，外观对齐「灵动通知」风格：样式预览卡片 + 大开关。

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <notify.h>
#import <CoreFoundation/CoreFoundation.h>

#define DIP_DOMAIN @"com.dynamicislandpro.tweak"
#define DIP_APPS_CACHE @"/var/mobile/Library/Caches/DynamicIslandPro-apps.plist"

#pragma mark - 偏好读写

static id DIPGet(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                          (__bridge CFStringRef)DIP_DOMAIN);
}

static void DIPSet(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFTypeRef)value,
                             (__bridge CFStringRef)DIP_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)DIP_DOMAIN);
}

static double DIPNum(NSString *key, double def) {
    id v = DIPGet(key);
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
}

static BOOL DIPBool(NSString *key, BOOL def) {
    id v = DIPGet(key);
    return v ? [v boolValue] : def;
}

#pragma mark - 样式预览图

static UIImage *DIPPreviewImage(NSInteger style) {
    CGSize size = CGSizeMake(104, 68);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        UIBezierPath *card = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                                          cornerRadius:10];
        [[UIColor colorWithWhite:0.98 alpha:1.0] setFill];
        [card fill];
        [[UIColor colorWithWhite:0.86 alpha:1.0] setStroke];
        card.lineWidth = 1.0;
        [card stroke];

        // 桌面壁纸底色
        UIBezierPath *wall = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(4, 4, size.width - 8, size.height - 8)
                                                          cornerRadius:8];
        [[UIColor colorWithRed:0.66 green:0.86 blue:0.55 alpha:1.0] setFill];
        [wall fill];

        CGFloat pad = 12.0;
        CGFloat pw = size.width - pad * 2;
        CGFloat ph = 15.0;
        CGRect pill;
        NSInteger ls = style;
        if (ls == 0) {
            pill = CGRectMake(pad, 9, pw, ph + 3);
        } else if (ls == 1) {
            CGFloat w2 = pw * 0.62;
            pill = CGRectMake(pad + (pw - w2) / 2.0, 9, w2, ph);
        } else {
            CGFloat w2 = pw * 0.34;
            pill = CGRectMake(pad + (pw - w2) / 2.0, 9, w2, ph);
        }
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:pill
                                                     cornerRadius:ph / 2.0 + 1.0];
        [[UIColor blackColor] setFill];
        [p fill];

        // 内容示意
        CGFloat ix = pill.origin.x + 5;
        CGRect iconRect = CGRectMake(ix, pill.origin.y + 4, 9, 9);
        [[UIColor colorWithRed:0.29 green:0.78 blue:0.35 alpha:1.0] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:iconRect cornerRadius:2.5] fill];
        if (ls == 0) {
            [[UIColor whiteColor] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(ix + 13, pill.origin.y + 4, pill.size.width - 24, 2.5)
                                       cornerRadius:1.2] fill];
            [[UIColor colorWithWhite:0.75 alpha:1.0] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(ix + 13, pill.origin.y + 9, pill.size.width - 34, 2.0)
                                       cornerRadius:1.0] fill];
        } else if (ls == 1) {
            [[UIColor whiteColor] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(ix + 12, pill.origin.y + 5.5, pill.size.width - 22, 2.5)
                                       cornerRadius:1.2] fill];
        }
        CGContextSetFillColorWithColor(c, [UIColor clearColor].CGColor);
    }];
}

#pragma mark - 样式选择单元

@interface DIPStyleCell : UITableViewCell
@property (nonatomic, strong) NSMutableArray *tiles;
- (void)setSelectedStyle:(NSInteger)style;
@end

@implementation DIPStyleCell {
    NSArray *_labels;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];

    _labels = @[@"标准", @"紧凑", @"迷你"];
    self.tiles = [NSMutableArray array];
    CGFloat cellW = [UIScreen mainScreen].bounds.size.width - 40.0;
    CGFloat tileW = MIN(110.0, (cellW - 16.0) / 3.0);
    CGFloat gap = (cellW - tileW * 3.0) / 4.0;

    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(gap + i * (tileW + gap), 10, tileW, 112);
        b.tag = 100 + i;

        UIImageView *img = [[UIImageView alloc] initWithFrame:CGRectMake((tileW - 104) / 2.0, 0, 104, 68)];
        img.image = DIPPreviewImage(i);
        img.layer.cornerRadius = 10;
        img.layer.masksToBounds = YES;
        img.userInteractionEnabled = NO;
        [b addSubview:img];

        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, 72, tileW, 18)];
        lab.text = _labels[i];
        lab.font = [UIFont systemFontOfSize:13.5];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;
        [b addSubview:lab];

        UIImageView *radio = [[UIImageView alloc] initWithFrame:CGRectMake((tileW - 22) / 2.0, 94, 22, 22)];
        radio.tag = 200 + i;
        radio.userInteractionEnabled = NO;
        [b addSubview:radio];

        [b addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
        [self.tiles addObject:b];
    }
    [self setSelectedStyle:(NSInteger)DIPNum(@"layoutStyle", 0)];
    return self;
}

- (void)setSelectedStyle:(NSInteger)style {
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = self.tiles[i];
        UIImageView *radio = (UIImageView *)[b viewWithTag:200 + i];
        BOOL on = (i == style);
        radio.image = nil;
        radio.layer.cornerRadius = 11;
        radio.layer.borderWidth = 1.2;
        radio.layer.borderColor = (on ? [UIColor systemBlueColor] : [UIColor systemGray3Color]).CGColor;
        radio.backgroundColor = on ? [UIColor systemBlueColor] : [UIColor clearColor];
        if (on) {
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(22, 22)];
            radio.image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                UIBezierPath *tick = [UIBezierPath bezierPath];
                [tick moveToPoint:CGPointMake(5, 11)];
                [tick addLineToPoint:CGPointMake(9.5, 15.5)];
                [tick addLineToPoint:CGPointMake(17, 6.5)];
                tick.lineWidth = 2.0;
                [[UIColor whiteColor] setStroke];
                [tick stroke];
            }];
        }
    }
}

- (void)tileTapped:(UIButton *)sender {
    NSInteger idx = sender.tag - 100;
    [self setSelectedStyle:idx];
    id responder = [self nextResponder];
    SEL action = @selector(styleTileSelected:);
    while (responder) {
        if ([responder respondsToSelector:action]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(responder, action, idx);
            break;
        }
        responder = [responder nextResponder];
    }
}

@end

#pragma mark - 设置页

@interface DIPRootController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *apps;
@end

@implementation DIPRootController

// 兼容 Settings 可能调用的私有协议方法，避免 unrecognized selector 崩溃
- (void)setSpecifier:(id)specifier {}
- (id)specifier { return nil; }
- (void)setParentController:(id)parent {}
- (id)parentController { return nil; }
- (void)setRootController:(id)root {}
- (id)rootController { return nil; }
- (void)setPreferenceValue:(id)value specifier:(id)specifier {}
- (id)readPreferenceValue:(id)specifier { return nil; }
- (void)reloadSpecifiers {}
- (id)loadSpecifiersFromPlistName:(id)name target:(id)target { return @[]; }

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (sig) return sig;
    return [NSObject instanceMethodSignatureForSelector:@selector(description)];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    // 未知的私有方法一律忽略
    NSLog(@"[DIP] ignored selector %@", NSStringFromSelector([invocation selector]));
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"灵动岛通知胶囊";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];

    NSArray *cached = [NSArray arrayWithContentsOfFile:DIP_APPS_CACHE];
    self.apps = cached ?: @[];
}

#pragma mark 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 6; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"灵动通知设置";
        case 1: return @"灵动岛通知窗口样式选择";
        case 2: return @"手势与点击";
        case 3: return @"外观";
        case 4: return @"显示时长与动画";
        case 5: return @"通知来源";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1)
        return @"三种样式：\n1. 图标 + 时间 + App 名称 + 标题 + 双行内容（展开显示）\n2. 图标 + 标题（单行，紧凑常驻）\n3. 仅图标（迷你）";
    if (section == 3)
        return @"尺寸单位是点；改动在下一条通知生效。";
    if (section == 5)
        return @"模式为“全部 App”时下面选择不起作用；选“仅选中的 App”则只显示勾选的，选“排除选中的 App”则屏蔽勾选的。";
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) return 136.0;
    return 44.0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return 1;
        case 2: return 2;
        case 3: return 6;
        case 4: return 2;
        case 5: return 1 + MAX((NSInteger)self.apps.count, 1);
        default: return 0;
    }
}

- (UITableViewCell *)cellWithReuse:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.accessoryView = nil;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    return cell;
}

- (UISwitch *)makeSwitch:(BOOL)on action:(NSString *)action {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    [sw addTarget:self action:NSSelectorFromString(action) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger s = indexPath.section, r = indexPath.row;

    if (s == 1) {
        DIPStyleCell *sc = [tableView dequeueReusableCellWithIdentifier:@"style"];
        if (!sc) sc = [[DIPStyleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"style"];
        [sc setSelectedStyle:(NSInteger)DIPNum(@"layoutStyle", 0)];
        return sc;
    }

    UITableViewCell *cell = [self cellWithReuse:tableView];

    if (s == 0) {
        if (r == 0) {
            cell.textLabel.text = @"开启灵动通知";
            cell.accessoryView = [self makeSwitch:DIPBool(@"enabled", YES) action:@"toggleEnabled:"];
        } else {
            cell.textLabel.text = @"发送测试胶囊";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        return cell;
    }

    if (s == 2) {
        if (r == 0) {
            cell.textLabel.text = @"点击事件操作";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"默认事件", @"打开 App", @"无操作"]];
            seg.selectedSegmentIndex = (NSInteger)DIPNum(@"tapAction", 0);
            [seg addTarget:self action:@selector(tapActionChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
        } else {
            cell.textLabel.text = @"下拉手势操作";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"默认", @"快捷回复", @"无操作"]];
            seg.selectedSegmentIndex = (NSInteger)DIPNum(@"pullAction", 0);
            [seg addTarget:self action:@selector(pullActionChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
        }
        return cell;
    }

    if (s == 3) {
        if (r == 0) {
            cell.textLabel.text = @"配色";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"纯黑", @"石墨", @"亮白", @"深蓝"]];
            seg.selectedSegmentIndex = (NSInteger)DIPNum(@"stylePreset", 0);
            [seg addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
            return cell;
        }
        NSArray *defs = @[@[@"宽度（收起）", @"collapsedW", @80, @240, @150],
                          @[@"高度（收起）", @"collapsedH", @28, @54, @38],
                          @[@"圆角", @"cornerRadius", @8, @30, @19],
                          @[@"展开高度", @"expandedH", @70, @140, @100],
                          @[@"不透明度", @"bgAlpha", @0.5, @1.0, @1.0]];
        NSArray *d = defs[r - 1];
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %.0f",
                               d[0], DIPNum(d[1], [d[4] doubleValue])];
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
        sl.minimumValue = [d[2] floatValue];
        sl.maximumValue = [d[3] floatValue];
        sl.value = DIPNum(d[1], [d[4] doubleValue]);
        sl.tag = r;
        [sl addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sl;
        return cell;
    }

    if (s == 4) {
        if (r == 0) {
            cell.textLabel.text = [NSString stringWithFormat:@"显示时长  %.1f 秒", DIPNum(@"duration", 3.4)];
            UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
            sl.minimumValue = 1.0; sl.maximumValue = 8.0; sl.value = DIPNum(@"duration", 3.4);
            [sl addTarget:self action:@selector(durationChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sl;
        } else {
            cell.textLabel.text = @"动画";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"弹簧", @"淡入", @"无"]];
            seg.selectedSegmentIndex = (NSInteger)DIPNum(@"animStyle", 0);
            [seg addTarget:self action:@selector(animChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
        }
        return cell;
    }

    if (s == 5) {
        if (r == 0) {
            cell.textLabel.text = @"过滤模式";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"全部", @"仅选中", @"排除选中"]];
            seg.selectedSegmentIndex = (NSInteger)DIPNum(@"filterMode", 0);
            [seg addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
            return cell;
        }
        if (self.apps.count == 0) {
            cell.textLabel.text = @"（还没有应用列表，请先重启一次 SpringBoard）";
            cell.textLabel.font = [UIFont systemFontOfSize:13];
            cell.textLabel.numberOfLines = 0;
            return cell;
        }
        NSDictionary *app = self.apps[r - 1];
        cell.textLabel.text = app[@"name"] ?: app[@"id"];
        NSString *key = [@"app_" stringByAppendingString:app[@"id"]];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = DIPBool(key, NO);
        sw.tag = r - 1;
        [sw addTarget:self action:@selector(appToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    return cell;
}

#pragma mark 交互

- (void)toggleEnabled:(UISwitch *)sw { DIPSet(@"enabled", @(sw.on)); }

- (void)styleTileSelected:(NSInteger)idx {
    DIPSet(@"layoutStyle", @(idx));
    [self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:1]]
                       withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tapActionChanged:(UISegmentedControl *)seg { DIPSet(@"tapAction", @(seg.selectedSegmentIndex)); }

- (void)pullActionChanged:(UISegmentedControl *)seg { DIPSet(@"pullAction", @(seg.selectedSegmentIndex)); }

- (void)styleChanged:(UISegmentedControl *)seg { DIPSet(@"stylePreset", @(seg.selectedSegmentIndex)); }

- (void)animChanged:(UISegmentedControl *)seg { DIPSet(@"animStyle", @(seg.selectedSegmentIndex)); }

- (void)filterChanged:(UISegmentedControl *)seg {
    DIPSet(@"filterMode", @(seg.selectedSegmentIndex));
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:5] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)sliderChanged:(UISlider *)sl {
    NSArray *keys = @[@"collapsedW", @"collapsedH", @"cornerRadius", @"expandedH", @"bgAlpha"];
    NSString *key = keys[sl.tag - 1];
    DIPSet(key, @(sl.value));
    NSString *label = @[@"宽度（收起）", @"高度（收起）", @"圆角", @"展开高度", @"不透明度"][sl.tag - 1];
    UITableViewCell *cell = [self.table cellForRowAtIndexPath:
                             [NSIndexPath indexPathForRow:sl.tag inSection:3]];
    cell.textLabel.text = [NSString stringWithFormat:@"%@  %.0f", label, sl.value];
}

- (void)durationChanged:(UISlider *)sl {
    DIPSet(@"duration", @(sl.value));
    UITableViewCell *cell = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]];
    cell.textLabel.text = [NSString stringWithFormat:@"显示时长  %.1f 秒", sl.value];
}

- (void)appToggled:(UISwitch *)sw {
    if (sw.tag >= (NSInteger)self.apps.count) return;
    NSString *key = [@"app_" stringByAppendingString:self.apps[sw.tag][@"id"]];
    DIPSet(key, @(sw.on));
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 1) {
        notify_post("com.dynamicislandpro.test");
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已发送测试"
                                                                  message:@"退出设置后看屏幕顶部，胶囊会在灵动岛位置展开。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

@end
