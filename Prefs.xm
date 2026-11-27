// DynamicIslandPro 设置页（PreferenceBundle）
// 用自带 UIViewController + UITableView 实现，避免依赖 Preferences 私有头文件。

#import <UIKit/UIKit.h>
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

#pragma mark - 设置页

@interface DIPRootController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *apps;
@end

@implementation DIPRootController

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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"总开关";
        case 1: return @"样式";
        case 2: return @"显示时长与动画";
        case 3: return @"通知来源";
        default: return @"选择 App（配合上面的模式生效）";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"宽度/高度/圆角以“点”为单位；不透明度 1.0 为不透明。改动在下一条通知生效。";
    if (section == 3) return @"模式为“全部 App”时下面选择不起作用；选“仅选中的 App”则只显示勾选的，选“排除选中的 App”则屏蔽勾选的。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return 6;
        case 2: return 2;
        case 3: return 1;
        default: return self.apps.count ?: 1;
    }
}

- (UITableViewCell *)cellWithReuse:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.accessoryView = nil;
    return cell;
}

- (UISwitch *)makeSwitch:(BOOL)on action:(NSString *)action {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    sw.tag = action.hash;
    [sw addTarget:self action:NSSelectorFromString(action) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self cellWithReuse:tableView];
    NSInteger s = indexPath.section, r = indexPath.row;

    if (s == 0) {
        if (r == 0) {
            cell.textLabel.text = @"启用灵动岛通知";
            cell.accessoryView = [self makeSwitch:DIPBool(@"enabled", YES) action:@"toggleEnabled:"];
        } else {
            cell.textLabel.text = @"显示一条测试胶囊";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        return cell;
    }

    if (s == 1) {
        if (r == 0) {
            cell.textLabel.text = @"配色";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"纯黑", @"石墨", @"亮白", @"深蓝"]];
            seg.selectedSegmentIndex = (NSInteger)DIPNum(@"stylePreset", 0);
            [seg addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
            return cell;
        }
        NSArray *defs = @[@[@"宽度", @"collapsedW", @100, @180, @126],
                          @[@"高度", @"collapsedH", @28, @50, @37],
                          @[@"圆角", @"cornerRadius", @6, @27, @18.5],
                          @[@"展开高度", @"expandedH", @56, @140, @88],
                          @[@"不透明度", @"bgAlpha", @0.5, @1.0, @1.0]];
        NSArray *d = defs[r - 1];
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %.1f",
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

    if (s == 2) {
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

    if (s == 3) {
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

    NSDictionary *app = self.apps[r];
    cell.textLabel.text = app[@"name"] ?: app[@"id"];
    NSString *key = [@"app_" stringByAppendingString:app[@"id"]];
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = DIPBool(key, NO);
    sw.tag = r;
    [sw addTarget:self action:@selector(appToggled:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

#pragma mark 交互

- (void)toggleEnabled:(UISwitch *)sw { DIPSet(@"enabled", @(sw.on)); }

- (void)styleChanged:(UISegmentedControl *)seg { DIPSet(@"stylePreset", @(seg.selectedSegmentIndex)); }

- (void)animChanged:(UISegmentedControl *)seg { DIPSet(@"animStyle", @(seg.selectedSegmentIndex)); }

- (void)filterChanged:(UISegmentedControl *)seg {
    DIPSet(@"filterMode", @(seg.selectedSegmentIndex));
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:4] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)sliderChanged:(UISlider *)sl {
    NSArray *keys = @[@"collapsedW", @"collapsedH", @"cornerRadius", @"expandedH", @"bgAlpha"];
    NSString *key = keys[sl.tag - 1];
    DIPSet(key, @(sl.value));
    NSInteger r = sl.tag;
    UITableViewCell *cell = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:1]];
    NSString *label = @[@"宽度", @"高度", @"圆角", @"展开高度", @"不透明度"][r - 1];
    cell.textLabel.text = [NSString stringWithFormat:@"%@  %.1f", label, sl.value];
}

- (void)durationChanged:(UISlider *)sl {
    DIPSet(@"duration", @(sl.value));
    UITableViewCell *cell = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
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
