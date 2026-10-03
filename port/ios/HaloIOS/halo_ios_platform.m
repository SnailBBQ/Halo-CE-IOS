#import "halo_ios_platform.h"
#import "halo_guest_runner.h"
#import "HaloSettingsStore.h"
#include "halo_invite_file_policy.h"

#import <UIKit/UIKit.h>

/* ---------- invites: halo://join/<64 hex digits> (build 73 public-key hash + token) */

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
    if ([trimmed.lowercaseString hasPrefix:kInvitePrefix]) trimmed = [trimmed substringFromIndex:kInvitePrefix.length];
    /* Keep the UI/export aligned with p2p_internal.h: 16-byte hash + 16-byte token. */
    if (trimmed.length != 64) return NO;
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
    halo_ios_toast("Joining the inviteâ€¦");
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
    halo_ios_toast("Joining the inviteâ€¦");
    return YES;
}

/* A picked folder works with sideloaded builds: no application-specific iCloud
 * entitlement is required. File-provider access and bookmarks follow UIKit's
 * document-picker contract. All coordinated I/O runs off the game/UI threads. */
static NSString *const kInviteFolderBookmark = @"HaloInviteFolderBookmark";
static NSString *const kInviteFolderLabel = @"HaloInviteFolderLabel";
static NSString *const kInviteOwnedCode = @"HaloInviteOwnedCode";
static dispatch_queue_t InviteFileQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("halo.invite-file", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static NSError *InviteFileError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"HaloInviteFile" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSURL *LocalInviteFolder(void)
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Halo" isDirectory:YES];
}
/* Call only on InviteFileQueue. Caller balances security scope after I/O. */
static NSURL *ResolveInviteFolder(BOOL *scoped, NSError **error)
{
    *scoped = NO;
    NSData *bookmark = [[NSUserDefaults standardUserDefaults] dataForKey:kInviteFolderBookmark];
    if (!bookmark) return LocalInviteFolder();
    BOOL stale = NO;
    NSURL *folder = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:error];
    if (!folder || ![folder startAccessingSecurityScopedResource]) {
        if (error && !*error) *error = InviteFileError(1, @"Choose the invite folder again to restore access.");
        return nil; /* Never silently export to a different location. */
    }
    *scoped = YES;
    if (stale) {
        NSData *renewed = [folder bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:error];
        if (!renewed) { [folder stopAccessingSecurityScopedResource]; *scoped = NO; return nil; }
        [[NSUserDefaults standardUserDefaults] setObject:renewed forKey:kInviteFolderBookmark];
    }
    return folder;
}
static NSString *ReadSmallInvite(NSURL *url, NSError **error)
{
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:error];
    if (!attributes) return nil;
    if ([attributes[NSFileSize] unsignedLongLongValue] > 1024) {
        if (error) *error = InviteFileError(2, @"The invite file must contain one link, at most 1024 bytes.");
        return nil;
    }
    return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
}
/* A clear is conditional: a code pasted from a PC belongs to the user and must
 * survive host-stop/launch cleanup. Creation leaves an existing incoming file
 * intact. Only publishing a live hosted invite intentionally replaces it. */
static BOOL WriteInviteToFolder(NSURL *folder, NSString *invite, NSError **error)
{
    NSFileManager *files = [NSFileManager defaultManager];
    if (![files createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSURL *url = [folder URLByAppendingPathComponent:@"game_invite.txt"];
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSError *operationError = nil;
    __block BOOL saved = NO;
    [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForReplacing error:error byAccessor:^(NSURL *coordinatedURL) {
        NSString *owned = [[NSUserDefaults standardUserDefaults] stringForKey:kInviteOwnedCode];
        if (!invite && [files fileExistsAtPath:coordinatedURL.path]) {
            NSString *existing = ReadSmallInvite(coordinatedURL, &operationError);
            if (!existing) return;
            NSString *trimmed = [existing stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!halo_invite_clear_allowed(trimmed.UTF8String, owned.UTF8String)) {
                /* Includes empty files and incoming PC invites. No rewrite. */
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kInviteOwnedCode];
                saved = YES;
                return;
            }
        }
        NSString *contents = invite ? [invite stringByAppendingString:@"\n"] : @"";
        saved = [contents writeToURL:coordinatedURL atomically:YES encoding:NSUTF8StringEncoding error:&operationError];
        if (saved) {
            if (invite) [[NSUserDefaults standardUserDefaults] setObject:invite forKey:kInviteOwnedCode];
            else [[NSUserDefaults standardUserDefaults] removeObjectForKey:kInviteOwnedCode];
        }
    }];
    if (operationError && error) *error = operationError;
    if (!saved && error && !*error) *error = InviteFileError(4, @"Could not update the invite file.");
    return saved;
}
static BOOL WriteCurrentInvite(NSString *invite, NSError **error)
{
    BOOL scoped = NO;
    NSURL *folder = ResolveInviteFolder(&scoped, error);
    if (!folder) return NO;
    BOOL saved = WriteInviteToFolder(folder, invite, error);
    if (scoped) [folder stopAccessingSecurityScopedResource];
    return saved;
}
NSString *HaloInviteFileLocation(void)
{
    NSString *label = [[NSUserDefaults standardUserDefaults] stringForKey:kInviteFolderLabel];
    return label.length ? [NSString stringWithFormat:@"Selected folder: %@ / game_invite.txt", label]
        : @"Choose an iCloud Drive folder below. Until then, the file stays in Documents/Halo/game_invite.txt.";
}
void HaloSelectInviteFolder(NSURL *folder, void (^completion)(NSError *))
{
    /* Retain the picker's grant until a persisted bookmark is created. */
    BOOL granted = [folder startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSNumber *isDirectory = nil;
    NSString *folderLabel = nil;
    if (granted) [folder getResourceValue:&folderLabel forKey:NSURLLocalizedNameKey error:nil];
    [folder getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error];
    NSData *bookmark = granted && isDirectory.boolValue ? [folder bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:&error] : nil;
    if (granted) [folder stopAccessingSecurityScopedResource];
    if (!bookmark) {
        completion(error ?: InviteFileError(3, @"Choose a writable folder in iCloud Drive."));
        return;
    }
    [InviteLock() lock];
    dispatch_async(InviteFileQueue(), ^{
        @autoreleasepool {
            NSError *operationError = nil;
            /* Attempt previous-destination cleanup before moving the writer.
             * A revoked grant is reported without blocking a replacement. */
            if (!WriteCurrentInvite(nil, &operationError)) {
                /* A revoked old bookmark must not prevent choosing a new grant.
                   Its inaccessible file cannot be cleaned up by this process. */
                NSLog(@"Halo old invite folder cleanup: %@", operationError.localizedDescription);
                halo_ios_toast("Previous invite folder could not be cleared. Remove its old file in Files if needed.");
                operationError = nil;
            }
            NSData *previous = [[NSUserDefaults standardUserDefaults] dataForKey:kInviteFolderBookmark];
            NSString *previousLabel = [[NSUserDefaults standardUserDefaults] stringForKey:kInviteFolderLabel];
            [[NSUserDefaults standardUserDefaults] setObject:bookmark forKey:kInviteFolderBookmark];
            [[NSUserDefaults standardUserDefaults] setObject:(folderLabel.length ? folderLabel : folder.lastPathComponent) forKey:kInviteFolderLabel];
            /* Current memory state wins if hosting changed while the picker
             * was open. Later lifecycle writes run in this same serial queue. */
            NSString *current = HaloLastHostedInvite();
            BOOL ready = WriteCurrentInvite(current, &operationError);
            if (!ready) {
                if (previous) [[NSUserDefaults standardUserDefaults] setObject:previous forKey:kInviteFolderBookmark];
                else [[NSUserDefaults standardUserDefaults] removeObjectForKey:kInviteFolderBookmark];
                if (previousLabel) [[NSUserDefaults standardUserDefaults] setObject:previousLabel forKey:kInviteFolderLabel];
                else [[NSUserDefaults standardUserDefaults] removeObjectForKey:kInviteFolderLabel];
                /* Restore a currently hosted code at the previous destination. */
                WriteCurrentInvite(HaloLastHostedInvite(), nil);
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(ready ? nil : operationError); });
        }
    });
    [InviteLock() unlock];
}
void HaloReadInviteFile(void (^completion)(NSString *, NSError *))
{
    dispatch_async(InviteFileQueue(), ^{
        @autoreleasepool {
            NSError *error = nil;
            BOOL scoped = NO;
            NSURL *folder = ResolveInviteFolder(&scoped, &error);
            __block NSString *text = nil;
            __block NSError *readError = nil;
            if (folder) {
                NSURL *url = [folder URLByAppendingPathComponent:@"game_invite.txt"];
                NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                [coordinator coordinateReadingItemAtURL:url options:0 error:&error byAccessor:^(NSURL *coordinatedURL) {
                    text = ReadSmallInvite(coordinatedURL, &readError);
                }];
                if (scoped) [folder stopAccessingSecurityScopedResource];
            }
            NSError *resultError = error ?: readError;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(text, resultError); });
        }
    });
}
/* Lock orders lifecycle enqueueing with current-memory publication. I/O never
 * holds InviteLock, so file-provider delays cannot stall simulation or UIKit. */
void halo_ios_set_hosted_invite(const char *text)
{
    NSString *invite = text ? [NSString stringWithUTF8String:text] : nil;
    if (invite && !HaloLooksLikeInvite(invite)) invite = nil;
    [InviteLock() lock];
    g_last_invite = [invite copy];
    dispatch_async(InviteFileQueue(), ^{
        @autoreleasepool {
            NSError *error = nil;
            NSString *current = HaloLastHostedInvite();
            if (current != invite && ![current isEqualToString:invite]) return;
            if (!WriteCurrentInvite(invite, &error)) {
                /* Log no invite contents. Preserve the file on failed I/O. */
                NSLog(@"Halo invite file: %@", error.localizedDescription);
                halo_ios_toast("Could not update invite file. Check iCloud sync or choose the folder again.");
            }
        }
    });
    [InviteLock() unlock];
}

/* ---------- clipboard for the game */

void halo_ios_clipboard_set(const char *text)
{
    if (!text) return;
    NSString *string = [NSString stringWithUTF8String:text];
    if (!string) return;
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
