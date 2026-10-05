#import <UIKit/UIKit.h>
#import <mach/mach.h>
#include <ifaddrs.h>
#include <net/if.h>

extern CFMutableDictionaryRef IOServiceMatching(const char *name);
extern mach_port_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching);
extern kern_return_t IORegistryEntryCreateCFProperties(mach_port_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, uint32_t options);
extern kern_return_t IOObjectRelease(mach_port_t object);

@interface UIWindow (GBFind)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)a onlyVisibleWindows:(BOOL)b;
@end
@interface SBHomeScreenViewController : UIViewController
@end
@interface STUIStatusBarWifiSignalView : UIView
@end
@interface STUIStatusBarBatteryView : UIView
@end
@interface STUIStatusBarDualCellularSignalView : UIView
@end

#define PW 80.0
#define PH 28.0
#define PAD 2.0
#define LW 2.5
#define DOT_D 3.4
#define DOT_STEP 8.0
#define ROW_GAP 6.5
#define EXTRA_H 6.0
#define GAP_HALF 19.0

static UIWindow *win;
static CAShapeLayer *trackLayer, *fillLayer, *wf1, *wf2, *wf3;
static UIImageView *wifiView, *boltView;
static UILabel *pctLabel;
static NSMutableArray<CALayer *> *dots;
static __weak UIView *gWifi;
static __weak UIView *gBatt;
static __weak UIView *gCell;
static __weak UIView *gSim1;
static __weak UIView *gSim2;
static __weak UILabel *gTime;
static BOOL gExt = NO;
static BOOL gHaveBatt = NO;

static CGFloat rad(CGFloat deg) { return deg * M_PI / 180.0; }

static void readNet(BOOL *wifi, BOOL *cell) {
    *wifi = NO; *cell = NO;
    struct ifaddrs *ifa, *p;
    if (getifaddrs(&ifa) != 0) return;
    for (p = ifa; p; p = p->ifa_next) {
        if (!p->ifa_addr) continue;
        int fam = p->ifa_addr->sa_family;
        if (fam != AF_INET && fam != AF_INET6) continue;
        if (!(p->ifa_flags & IFF_UP) || !(p->ifa_flags & IFF_RUNNING)) continue;
        if (!strcmp(p->ifa_name, "en0") && fam == AF_INET) *wifi = YES;
        else if (!strncmp(p->ifa_name, "pdp_ip", 6)) *cell = YES;
    }
    freeifaddrs(ifa);
}

static int readPercent(void) {
    int pct = -1;
    gHaveBatt = NO;
    mach_port_t svc = IOServiceGetMatchingService(0, IOServiceMatching("IOPMPowerSource"));
    if (!svc) return -1;
    CFMutableDictionaryRef props = NULL;
    if (IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
        NSDictionary *d = (__bridge_transfer NSDictionary *)props;
        NSNumber *c = d[@"CurrentCapacity"];
        if (c) pct = c.intValue;
        gExt = [d[@"ExternalConnected"] boolValue];
        gHaveBatt = YES;
    }
    IOObjectRelease(svc);
    return pct;
}

static UIView *findView(UIView *v, NSString *cn, int depth) {
    if (depth > 8) return nil;
    if ([NSStringFromClass(v.class) isEqualToString:cn]) return v;
    for (UIView *s in v.subviews) {
        UIView *r = findView(s, cn, depth + 1);
        if (r) return r;
    }
    return nil;
}

static UILabel *findTime(UIView *v, int depth) {
    if (depth > 9) return nil;
    if ([v isKindOfClass:UILabel.class] && [NSStringFromClass(v.class) isEqualToString:@"STUIStatusBarStringView"]) {
        NSString *t = ((UILabel *)v).text;
        if ([t containsString:@":"]) return (UILabel *)v;
    }
    for (UIView *s in v.subviews) {
        UILabel *r = findTime(s, depth + 1);
        if (r) return r;
    }
    return nil;
}

static void locate(void) {
    if (!(gWifi && gBatt && gCell)) {
        for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:YES]) {
            if (![NSStringFromClass(w.class) isEqualToString:@"SBStatusBarWindow"]) continue;
            if (!gWifi) gWifi = findView(w, @"STUIStatusBarWifiSignalView", 0);
            if (!gBatt) gBatt = findView(w, @"STUIStatusBarBatteryView", 0);
            if (!gCell) gCell = findView(w, @"STUIStatusBarDualCellularSignalView", 0);
        }
    }
    UIView *c = gCell;
    if (c) {
        if (!gSim1 || !gSim1.window) gSim1 = findView(c, @"STUIStatusBarCellularSmallSignalView", 0);
        if (!gSim2 || !gSim2.window) gSim2 = findView(c, @"STUIStatusBarCellularFlatSignalView", 0);
    }
    if (!gTime || !gTime.window) {
        for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:YES]) {
            if (![NSStringFromClass(w.class) isEqualToString:@"SBStatusBarWindow"]) continue;
            UILabel *t = findTime(w, 0);
            if (t) { gTime = t; break; }
        }
    }
}

static BOOL contentIsDark(UILabel *l) {
    int w = (int)ceil(l.bounds.size.width);
    int h = (int)ceil(l.bounds.size.height);
    if (w < 2 || h < 2 || w > 200 || h > 100) return NO;
    uint8_t *buf = calloc((size_t)w * h * 4, 1);
    if (!buf) return NO;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, w * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(buf); return NO; }
    CGContextTranslateCTM(ctx, 0, h);
    CGContextScaleCTM(ctx, 1, -1);
    [l.layer renderInContext:ctx];
    double sum = 0, alphaSum = 0;
    for (int i = 0; i < w * h; i++) {
        double a = buf[i * 4 + 3];
        if (a < 40) continue;
        double r = buf[i * 4] / a;
        double g = buf[i * 4 + 1] / a;
        double b = buf[i * 4 + 2] / a;
        double lum = 0.299 * r + 0.587 * g + 0.114 * b;
        sum += lum * a;
        alphaSum += a;
    }
    CGContextRelease(ctx);
    free(buf);
    if (alphaSum < 1) return NO;
    return (sum / alphaSum) < 0.5;
}

static void halo(CALayer *l, BOOL dk) {
    l.shadowColor = (dk ? UIColor.whiteColor : UIColor.blackColor).CGColor;
    l.shadowOpacity = dk ? 0.3 : 0.5;
    l.shadowRadius = 1.5;
    l.shadowOffset = CGSizeZero;
}

static int barsOf(UIView *v, int maxBars) {
    if (!v || ![v respondsToSelector:NSSelectorFromString(@"numberOfActiveBars")]) return -1;
    int n = (int)[[v valueForKey:@"numberOfActiveBars"] integerValue];
    return n < 0 ? 0 : (n > maxBars ? maxBars : n);
}

static void addFrame(UIView *v, CGRect *u) {
    if (!v || !v.window || !v.superview) return;
    CGRect r = [v.superview convertRect:v.frame toView:nil];
    *u = CGRectIsNull(*u) ? r : CGRectUnion(*u, r);
}

static void update(void) {
    locate();
    UIDevice *d = UIDevice.currentDevice;
    int pct = readPercent();
    if (pct < 0 || pct > 100) {
        float l = d.batteryLevel;
        pct = l < 0 ? 100 : (int)lroundf(l * 100);
    }
    BOOL chg = gHaveBatt ? gExt : (d.batteryState == UIDeviceBatteryStateCharging || d.batteryState == UIDeviceBatteryStateFull);
    BOOL dk = gTime ? contentIsDark(gTime) : NO;

    UIColor *green = [UIColor colorWithRed:0.20 green:0.84 blue:0.42 alpha:1];
    UIColor *red = [UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1];
    UIColor *fg = dk ? [UIColor colorWithWhite:0.06 alpha:1] : UIColor.whiteColor;
    UIColor *dim = [fg colorWithAlphaComponent:0.25];
    UIColor *ring = chg ? green : (pct <= 20 ? red : fg);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    fillLayer.strokeColor = ring.CGColor;
    fillLayer.strokeEnd = pct / 100.0;
    trackLayer.strokeColor = (chg ? [green colorWithAlphaComponent:0.22] : [fg colorWithAlphaComponent:0.22]).CGColor;
    int s1 = barsOf(gSim1, 4);
    int s2 = barsOf(gSim2, 4);
    for (int i = 0; i < 4; i++) {
        dots[i].backgroundColor = ((s1 > i) ? fg : dim).CGColor;
        dots[i + 4].backgroundColor = ((s2 > i) ? fg : dim).CGColor;
    }
    wf1.fillColor = fg.CGColor;
    wf2.strokeColor = fg.CGColor;
    wf3.strokeColor = fg.CGColor;
    halo(fillLayer, dk);
    halo(wf1, dk);
    halo(wf2, dk);
    halo(wf3, dk);
    for (CALayer *dl in dots) halo(dl, dk);
    halo(pctLabel.layer, dk);
    halo(wifiView.layer, dk);
    [CATransaction commit];

    boltView.hidden = !chg;
    pctLabel.text = [NSString stringWithFormat:@"%d", pct];
    pctLabel.textColor = chg ? green : (pct <= 20 ? red : fg);
    wifiView.tintColor = fg;

    BOOL wifi, cell;
    readNet(&wifi, &cell);
    int wb = barsOf(gWifi, 3);
    int bars = wifi ? (wb < 0 ? 3 : wb) : 0;
    wf1.hidden = !wifi;
    wf2.hidden = !wifi;
    wf3.hidden = !wifi;
    wf1.opacity = bars >= 1 ? 1 : 0.3;
    wf2.opacity = bars >= 2 ? 1 : 0.3;
    wf3.opacity = bars >= 3 ? 1 : 0.3;
    wifiView.hidden = wifi;
    if (!wifi) {
        NSString *name = cell ? @"antenna.radiowaves.left.and.right" : @"wifi.slash";
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
        wifiView.image = [UIImage systemImageNamed:name withConfiguration:cfg];
    }

    CGRect u = CGRectNull;
    addFrame(gWifi, &u);
    addFrame(gBatt, &u);
    addFrame(gCell, &u);
    if (!CGRectIsNull(u)) {
        CGFloat W = PW + 2 * PAD, H = PH + 2 * PAD + EXTRA_H;
        win.frame = CGRectMake(CGRectGetMidX(u) - W / 2, CGRectGetMidY(u) - (PAD + PH / 2), W, H);
    }
}

static UIBezierPath *pillPath(void) {
    CGRect r = CGRectMake(PAD + LW / 2, PAD + LW / 2, PW - LW, PH - LW);
    CGFloat R = r.size.height / 2;
    CGFloat cx = CGRectGetMidX(r), my = CGRectGetMidY(r);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(cx - GAP_HALF, CGRectGetMaxY(r))];
    [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + R, CGRectGetMaxY(r))];
    [p addArcWithCenter:CGPointMake(CGRectGetMinX(r) + R, my) radius:R
        startAngle:M_PI_2 endAngle:3 * M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(CGRectGetMaxX(r) - R, CGRectGetMinY(r))];
    [p addArcWithCenter:CGPointMake(CGRectGetMaxX(r) - R, my) radius:R
        startAngle:3 * M_PI_2 endAngle:5 * M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(cx + GAP_HALF, CGRectGetMaxY(r))];
    return p;
}

static CAShapeLayer *makeArc(UIBezierPath *path) {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.path = path.CGPath;
    l.fillColor = UIColor.clearColor.CGColor;
    l.lineWidth = LW;
    l.lineCap = kCALineCapRound;
    return l;
}

static CAShapeLayer *wifiArc(CGPoint base, CGFloat r) {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.path = [UIBezierPath bezierPathWithArcCenter:base radius:r
        startAngle:rad(-135) endAngle:rad(-45) clockwise:YES].CGPath;
    l.fillColor = UIColor.clearColor.CGColor;
    l.strokeColor = UIColor.whiteColor.CGColor;
    l.lineWidth = 2;
    l.lineCap = kCALineCapRound;
    return l;
}

static void setupWindow(UIWindowScene *scene) {
    if (win) return;
    CGFloat W = PW + 2 * PAD, H = PH + 2 * PAD + EXTRA_H;
    win = [[UIWindow alloc] initWithWindowScene:scene];
    win.frame = CGRectMake(8, 6, W, H);
    win.windowLevel = 10000;
    win.userInteractionEnabled = NO;
    win.backgroundColor = UIColor.clearColor;

    UIView *root = [[UIView alloc] initWithFrame:win.bounds];
    [win addSubview:root];

    UIBezierPath *pill = pillPath();
    trackLayer = makeArc(pill);
    fillLayer = makeArc(pill);
    fillLayer.strokeEnd = 1;
    [root.layer addSublayer:trackLayer];
    [root.layer addSublayer:fillLayer];

    CGPoint base = CGPointMake(PAD + PW - 20, PAD + 18);
    wf1 = [CAShapeLayer layer];
    wf1.path = [UIBezierPath bezierPathWithArcCenter:base radius:1.8
        startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
    wf1.fillColor = UIColor.whiteColor.CGColor;
    wf1.strokeColor = UIColor.clearColor.CGColor;
    wf2 = wifiArc(base, 5.5);
    wf3 = wifiArc(base, 9.0);
    [root.layer addSublayer:wf1];
    [root.layer addSublayer:wf2];
    [root.layer addSublayer:wf3];

    wifiView = [[UIImageView alloc] initWithFrame:CGRectMake(base.x - 9, PAD + 8, 18, 12)];
    wifiView.contentMode = UIViewContentModeScaleAspectFit;
    wifiView.tintColor = UIColor.whiteColor;
    [root addSubview:wifiView];

    pctLabel = [[UILabel alloc] initWithFrame:CGRectMake(PAD + 17, PAD + 5, 28, 18)];
    pctLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightBold];
    pctLabel.textAlignment = NSTextAlignmentCenter;
    pctLabel.textColor = UIColor.whiteColor;
    [root addSubview:pctLabel];

    boltView = [[UIImageView alloc] initWithFrame:CGRectMake(PAD + 8.5, PAD + 9.5, 7, 9)];
    boltView.contentMode = UIViewContentModeScaleAspectFit;
    boltView.tintColor = [UIColor colorWithRed:0.20 green:0.84 blue:0.42 alpha:1];
    boltView.image = [UIImage systemImageNamed:@"bolt.fill"];
    [root addSubview:boltView];

    dots = [NSMutableArray array];
    for (int i = 0; i < 8; i++) {
        int col = i % 4, row = i / 4;
        CALayer *dl = [CALayer layer];
        dl.bounds = CGRectMake(0, 0, DOT_D, DOT_D);
        dl.cornerRadius = DOT_D / 2;
        dl.position = CGPointMake(PAD + PW / 2 + (col - 1.5) * DOT_STEP, PAD + PH - LW / 2 + row * ROW_GAP);
        [root.layer addSublayer:dl];
        [dots addObject:dl];
    }

    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryStateDidChangeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ update(); }];
    win.hidden = NO;
    update();
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){ update(); }];
}

%hook SBHomeScreenViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIWindowScene *s = self.view.window.windowScene;
    if (s) setupWindow(s);
}
%end

%hook STUIStatusBarWifiSignalView
- (void)didMoveToWindow { %orig; self.alpha = 0; }
- (void)setAlpha:(CGFloat)a { %orig(0); }
%end

%hook STUIStatusBarBatteryView
- (void)didMoveToWindow { %orig; self.alpha = 0; }
- (void)setAlpha:(CGFloat)a { %orig(0); }
%end

%hook STUIStatusBarDualCellularSignalView
- (void)didMoveToWindow { %orig; self.alpha = 0; }
- (void)setAlpha:(CGFloat)a { %orig(0); }
%end
