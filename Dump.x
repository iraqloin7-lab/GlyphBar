#import <UIKit/UIKit.h>

@interface UIWindow (GBDump)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)a onlyVisibleWindows:(BOOL)b;
@end

static void walk(UIView *v, int depth, NSMutableString *out, int *count) {
    if (*count > 300 || depth > 9) return;
    (*count)++;
    NSString *cn = NSStringFromClass(v.class);
    NSString *pad = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *extra = @"";
    if ([cn containsString:@"Signal"] || [cn containsString:@"Wifi"] || [cn containsString:@"WiFi"]) {
        SEL sel = NSSelectorFromString(@"numberOfActiveBars");
        if ([v respondsToSelector:sel]) {
            extra = [NSString stringWithFormat:@" bars=%@", [v valueForKey:@"numberOfActiveBars"]];
        }
    }
    [out appendFormat:@"%@%@ %@%@%@\n", pad, cn, NSStringFromCGRect(v.frame), v.hidden ? @" H" : @"", extra];
    for (UIView *s in v.subviews) walk(s, depth + 1, out, count);
}

static void dump(void) {
    NSMutableString *out = [NSMutableString string];
    NSArray *ws = [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:YES];
    for (UIWindow *w in ws) {
        NSString *cn = NSStringFromClass(w.class);
        [out appendFormat:@"== %@ lvl=%.0f %@\n", cn, w.windowLevel, NSStringFromCGRect(w.frame)];
    }
    for (UIWindow *w in ws) {
        NSString *cn = NSStringFromClass(w.class);
        if (w.frame.size.height <= 100 || [cn containsString:@"StatusBar"]) {
            [out appendFormat:@"\n#### %@\n", cn];
            int count = 0;
            walk(w, 1, out, &count);
        }
    }
    NSString *res = out.length > 12000 ? [out substringToIndex:12000] : out;
    UIPasteboard.generalPasteboard.string = res;
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{ dump(); });
}
