#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <ifaddrs.h>
#include <net/if.h>

@interface SBHomeScreenViewController : UIViewController
@end

#define GB_SIZE 38.0
#define GB_R 16.0
#define GB_X_FROM_RIGHT 10.0
#define GB_Y 36.0

static UIWindow *win;
static CAShapeLayer *trackLayer, *fillLayer;
static UIImageView *wifiView, *boltView;
static NSMutableArray<CALayer *> *dots;
static NSDate *startDate;

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

static BOOL headphones(void) {
    AVAudioSessionRouteDescription *r = [AVAudioSession sharedInstance].currentRoute;
    for (AVAudioSessionPortDescription *o in r.outputs) {
        NSString *t = o.portType;
        if ([t isEqualToString:AVAudioSessionPortHeadphones] ||
            [t isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
            [t isEqualToString:AVAudioSessionPortBluetoothHFP] ||
            [t isEqualToString:AVAudioSessionPortBluetoothLE]) return YES;
    }
    return NO;
}

static void update(void) {
    UIDevice *d = UIDevice.currentDevice;
    float lvl = d.batteryLevel;
    if (lvl < 0) lvl = 1;
    BOOL chg = d.batteryState == UIDeviceBatteryStateCharging || d.batteryState == UIDeviceBatteryStateFull;

    UIColor *green = [UIColor colorWithRed:0.20 green:0.84 blue:0.42 alpha:1];
    UIColor *red = [UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1];
    UIColor *blue = [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1];
    UIColor *orange = [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1];
    UIColor *purple = [UIColor colorWithRed:0.75 green:0.35 blue:0.95 alpha:1];
    UIColor *dim = [UIColor colorWithWhite:1 alpha:0.25];
    UIColor *ring = chg ? green : (lvl <= 0.2 ? red : [UIColor colorWithWhite:0.9 alpha:1]);

    fillLayer.strokeColor = ring.CGColor;
    fillLayer.strokeEnd = lvl;
    trackLayer.strokeColor = (chg ? [green colorWithAlphaComponent:0.22] : [UIColor colorWithWhite:1 alpha:0.22]).CGColor;
    boltView.hidden = !chg;

    BOOL wifi, cell;
    readNet(&wifi, &cell);
    NSString *name = wifi ? @"wifi" : (cell ? @"antenna.radiowaves.left.and.right" : @"wifi.slash");
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
    wifiView.image = [UIImage systemImageNamed:name withConfiguration:cfg];

    BOOL demo = [[NSDate date] timeIntervalSinceDate:startDate] < 6;
    BOOL on[4] = { NO, NO, NO, headphones() };
    NSArray<UIColor *> *cols = @[blue, orange, green, purple];
    for (int i = 0; i < 4; i++) {
        dots[i].backgroundColor = ((on[i] || demo) ? cols[i] : dim).CGColor;
    }
}

static CAShapeLayer *makeArc(UIBezierPath *arc) {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.path = arc.CGPath;
    l.fillColor = UIColor.clearColor.CGColor;
    l.lineWidth = 3;
    l.lineCap = kCALineCapRound;
    return l;
}

static void setupWindow(UIWindowScene *scene) {
    if (win) return;
    CGFloat w = scene.screen.bounds.size.width;
    win = [[UIWindow alloc] initWithWindowScene:scene];
    win.frame = CGRectMake(w - GB_SIZE - GB_X_FROM_RIGHT, GB_Y, GB_SIZE, GB_SIZE);
    win.windowLevel = 10000;
    win.userInteractionEnabled = NO;
    win.backgroundColor = UIColor.clearColor;

    UIView *root = [[UIView alloc] initWithFrame:win.bounds];
    [win addSubview:root];

    CGPoint c = CGPointMake(GB_SIZE / 2, GB_SIZE / 2);
    UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:c radius:GB_R
        startAngle:rad(120) endAngle:rad(420) clockwise:YES];
    trackLayer = makeArc(arc);
    fillLayer = makeArc(arc);
    fillLayer.strokeEnd = 1;
    [root.layer addSublayer:trackLayer];
    [root.layer addSublayer:fillLayer];

    wifiView = [[UIImageView alloc] initWithFrame:CGRectMake(c.x - 9, 15, 18, 12)];
    wifiView.contentMode = UIViewContentModeScaleAspectFit;
    wifiView.tintColor = UIColor.whiteColor;
    [root addSubview:wifiView];

    boltView = [[UIImageView alloc] initWithFrame:CGRectMake(c.x - 4, 6, 8, 8)];
    boltView.contentMode = UIViewContentModeScaleAspectFit;
    boltView.tintColor = [UIColor colorWithRed:0.20 green:0.84 blue:0.42 alpha:1];
    boltView.image = [UIImage systemImageNamed:@"bolt.fill"];
    [root addSubview:boltView];

    dots = [NSMutableArray array];
    CGFloat angs[4] = {118, 99, 81, 62};
    for (int i = 0; i < 4; i++) {
        CALayer *dl = [CALayer layer];
        dl.bounds = CGRectMake(0, 0, 4, 4);
        dl.cornerRadius = 2;
        dl.position = CGPointMake(c.x + 12.5 * cos(rad(angs[i])), c.y + 12.5 * sin(rad(angs[i])));
        [root.layer addSublayer:dl];
        [dots addObject:dl];
    }

    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    startDate = [NSDate date];
    win.hidden = NO;
    update();
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){ update(); }];
}

%hook SBHomeScreenViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIWindowScene *s = self.view.window.windowScene;
    if (s) setupWindow(s);
}
%end
