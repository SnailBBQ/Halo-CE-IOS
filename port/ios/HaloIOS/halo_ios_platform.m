#import "halo_ios_platform.h"
#import "halo_guest_runner.h"
#import "HaloSettingsStore.h"

#import <UIKit/UIKit.h>

/* ---------- invites: halo://join/<44 hex digits> (see port/linux/README.md, "Internet play") */

static NSString *const kInvitePrefix = @"halo://join/";
static NSLock *InviteLock(void)
{
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSLock alloc] init]; });
    return lock;
}
static NSString *g_pending_invite;   /* opened through a link or "Join from clipboard"; consumed once */
static NSString *g_last_invite;      /* the invite this copy of the game is hosting */

static BOOL HaloLooksLikeInvite(NSString *text)
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed.lowercaseString hasPrefix:kInvitePrefix]) return trimmed.length > kInvitePrefix.length;
    /* the bare 44 hexadecimal digits are accepted too */
    if (trimmed.length != 44) return NO;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [trimmed rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound;
}

void HaloSetPendingInvite(NSString *invite)
{
    NSString *trimmed = [invite stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [InviteLock() lock];
    g_pending_invite = [trimmed copy];
    [InviteLock() unlock];
    halo_ios_post_focus_event(); /* the game looks for an invite when its window gains focus */
}

NSString *HaloLastHostedInvite(void)
{
    [InviteLock() lock];
    NSString *invite = [g_last_invite copy];
    [InviteLock() unlock];
    return invite;
}

/* Joins the invite in `text` (typed or pasted into the settings screen by the player). */
BOOL HaloJoinInviteText(NSString *text)
{
    if (!text.length || !HaloLooksLikeInvite(text)) {
        halo_ios_toast("That is not a Halo invite link (it starts with halo://join/)");
        return NO;
    }
    HaloSetPendingInvite(text);
    halo_ios_toast("Joining the invite…");
    return YES;
}

/* "Join from clipboard": a button press, so reading the pasteboard is expected. */
BOOL HaloJoinInviteFromClipboard(void)
{
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (!text.length || !HaloLooksLikeInvite(text)) {
        halo_ios_toast("No invite link on the clipboard");
        return NO;
    }
    HaloSetPendingInvite(text);
    halo_ios_toast("Joining the invite…");
    return YES;
}

/* ---------- clipboard for the game */

void halo_ios_clipboard_set(const char *text)
{
    if (!text) return;
    NSString *string = [NSString stringWithUTF8String:text];
    if (!string) return;
    if (HaloLooksLikeInvite(string)) {
        [InviteLock() lock];
        g_last_invite = [string copy];
        [InviteLock() unlock];
    }
    dispatch_async(dispatch_get_main_queue(), ^{ UIPasteboard.generalPasteboard.string = string; });
}

void halo_ios_clipboard_get(char *buffer, size_t size)
{
    if (!buffer || size == 0) return;
    buffer[0] = 0;
    NSString *text = nil;

    [InviteLock() lock];
    text = g_pending_invite;
    g_pending_invite = nil;
    [InviteLock() unlock];
    if (!text) {
        HsSettings settings = [[HaloSettingsStore shared] snapshot];
        if (!settings.join_from_clipboard) return; /* reading the pasteboard shows iOS's paste prompt */
        __block NSString *pasted = nil;
        void (^read)(void) = ^{
            if (UIPasteboard.generalPasteboard.hasStrings) pasted = UIPasteboard.generalPasteboard.string;
        };
        if (NSThread.isMainThread) read(); else dispatch_sync(dispatch_get_main_queue(), read);
        if (pasted && HaloLooksLikeInvite(pasted)) text = pasted;
    }
    if (text) strlcpy(buffer, text.UTF8String, size);
}

/* ---------- toasts */

void halo_ios_toast(const char *text)
{
    if (!text) return;
    NSString *message = [NSString stringWithUTF8String:text];
    if (!message.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
                    if (candidate.isKeyWindow) window = candidate;
            }
        }
        if (!window) window = UIApplication.sharedApplication.windows.firstObject;
        if (!window) return;
        UILabel *label = [[UILabel alloc] init];
        label.text = [NSString stringWithFormat:@"  %@  ", message];
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        label.font = [UIFont boldSystemFontOfSize:15];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        label.layer.cornerRadius = 14;
        label.clipsToBounds = YES;
        CGSize fit = [label sizeThatFits:CGSizeMake(window.bounds.size.width - 120, 80)];
        label.frame = CGRectMake((window.bounds.size.width - fit.width - 24) / 2, window.safeAreaInsets.top + 52,
                                 fit.width + 24, fit.height + 16);
        label.alpha = 0;
        [window addSubview:label];
        [UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; } completion:^(BOOL done) {
            (void)done;
            [UIView animateWithDuration:0.4 delay:2.4 options:0 animations:^{ label.alpha = 0; }
                             completion:^(BOOL finished) { (void)finished; [label removeFromSuperview]; }];
        }];
    });
}
