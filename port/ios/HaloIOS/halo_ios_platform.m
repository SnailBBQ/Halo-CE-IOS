#import "halo_ios_platform.h"
#import "halo_guest_runner.h"
#import "HaloSettingsStore.h"
#include "halo_invite_file_policy.h"

#import <UIKit/UIKit.h>
#include <pthread.h>

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

/* The last few games hosted or joined, newest first, so a player can find one again. Invites stop working when the host ends the game. */
static NSString *const kRecentGamesKey = @"HaloRecentGames";

void HaloRecordRecentGame(NSString *invite, NSString *role)
{
    NSString *trimmed = [invite stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length || !HaloLooksLikeInvite(trimmed)) return;
    @synchronized (NSUserDefaults.standardUserDefaults) {
        NSMutableArray *list = [([NSUserDefaults.standardUserDefaults arrayForKey:kRecentGamesKey] ?: @[]) mutableCopy];
        for (NSDictionary *entry in [list copy])
            if ([entry isKindOfClass:NSDictionary.class] && [entry[@"invite"] isEqual:trimmed]) [list removeObject:entry];
        [list insertObject:@{ @"invite": trimmed, @"role": role ?: @"Joined", @"date": @([NSDate date].timeIntervalSince1970) } atIndex:0];
        while (list.count > 8) [list removeLastObject];
        [NSUserDefaults.standardUserDefaults setObject:list forKey:kRecentGamesKey];
    }
}

NSArray<NSDictionary *> *HaloRecentGames(void)
{
    NSMutableArray<NSDictionary *> *valid = [NSMutableArray array];
    for (id entry in ([NSUserDefaults.standardUserDefaults arrayForKey:kRecentGamesKey] ?: @[]))
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"invite"] isKindOfClass:NSString.class]) [valid addObject:entry];
    return valid;
}

void HaloClearRecentGames(void) { [NSUserDefaults.standardUserDefaults removeObjectForKey:kRecentGamesKey]; }

void HaloSetPendingInvite(NSString *invite)
{
    halo_ios_campaign_state(0);
    NSString *trimmed = [invite stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    HaloRecordRecentGame(trimmed, @"Joined");
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
    if (invite) HaloRecordRecentGame(invite, @"Hosted");
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

/* ---------- the text chat's keyboard
 *
 * A line of the game's text chat is typed on the system keyboard, with or without a controller. The guest asks for it while a line is
 * begun (halo_ios_chat_input, from the game's thread); the keyboard belongs to an almost invisible text field in the game's window. What
 * is typed shows in the game's chat line as it does on PC, and the game gets none of the controller or the touch controls' stick and
 * look while the line is open. Send sends the line, closing the keyboard lets it go. */

#define HALO_CHAT_TEXT_SIZE 64

static pthread_mutex_t g_chat_lock = PTHREAD_MUTEX_INITIALIZER;
static char g_chat_text[HALO_CHAT_TEXT_SIZE];
static int g_chat_wanted;      /* the guest has a line open */
static int g_chat_answer;      /* 0 typing, 1 send, 2 let go */
static int g_chat_showing;     /* the field is first responder (main queue) */

@interface HaloChatField : UITextField <UITextFieldDelegate>
@end

static HaloChatField *g_chat_field;

static void HaloChatFinish(int answer)
{
    pthread_mutex_lock(&g_chat_lock);
    if (g_chat_wanted && !g_chat_answer) g_chat_answer = answer;
    pthread_mutex_unlock(&g_chat_lock);
}

@implementation HaloChatField
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.delegate = self;
        self.alpha = 0.02;
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        self.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.spellCheckingType = UITextSpellCheckingTypeNo;
        self.smartQuotesType = UITextSmartQuotesTypeNo;
        self.smartDashesType = UITextSmartDashesTypeNo;
        self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
        self.keyboardType = UIKeyboardTypeASCIICapable;
        self.returnKeyType = UIReturnKeySend;
        self.enablesReturnKeyAutomatically = NO;
        [self addTarget:self action:@selector(edited) forControlEvents:UIControlEventEditingChanged];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardDidHideNotification object:nil];
    }
    return self;
}
- (void)edited
{
    pthread_mutex_lock(&g_chat_lock);
    snprintf(g_chat_text, sizeof g_chat_text, "%s", self.text.UTF8String ?: "");
    pthread_mutex_unlock(&g_chat_lock);
}
- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    NSString *result = [field.text stringByReplacingCharactersInRange:range withString:string];
    return result.length < HALO_CHAT_TEXT_SIZE;   /* the game's line holds 63 characters */
}
- (BOOL)textFieldShouldReturn:(UITextField *)field
{
    [self edited];
    HaloChatFinish(1);
    return NO;
}
- (void)keyboardHidden:(NSNotification *)note
{
    (void)note;
    /* (a keyboard going that a line before it had, while this line's field holds the focus again, is not this line's) */
    if (g_chat_showing && !self.isFirstResponder) {
        g_chat_showing = 0;
        HaloChatFinish(2);   /* closed by hand (or by iOS): the line is let go */
    }
}
@end

static void HaloChatShow(NSString *start)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.delegate.window;
        if (!window) { HaloChatFinish(2); return; }
        if (!g_chat_field) g_chat_field = [[HaloChatField alloc] initWithFrame:CGRectMake(0, 0, 2, 2)];
        if (g_chat_field.superview != window.rootViewController.view) [window.rootViewController.view addSubview:g_chat_field];
        g_chat_field.text = start;
        g_chat_showing = 1;
        if (![g_chat_field becomeFirstResponder]) { g_chat_showing = 0; HaloChatFinish(2); }
    });
}

static void HaloChatHide(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        g_chat_showing = 0;   /* (so the keyboard going is not a line let go) */
        [g_chat_field resignFirstResponder];
        [g_chat_field removeFromSuperview];
    });
}

int halo_ios_chat_input(int mode, char text[64])
{
    int answer = 0;

    if (mode == 100) {
        pthread_mutex_lock(&g_chat_lock);
        int was = g_chat_wanted;
        g_chat_wanted = 0;
        g_chat_answer = 0;
        pthread_mutex_unlock(&g_chat_lock);
        if (was) HaloChatHide();
        return 0;
    }
    pthread_mutex_lock(&g_chat_lock);
    if (!g_chat_wanted) {
        g_chat_wanted = 1;
        g_chat_answer = 0;
        snprintf(g_chat_text, sizeof g_chat_text, "%s", text);
        NSString *start = [NSString stringWithUTF8String:g_chat_text] ?: @"";
        pthread_mutex_unlock(&g_chat_lock);
        HaloChatShow(start);
        return 0;
    }
    memcpy(text, g_chat_text, HALO_CHAT_TEXT_SIZE);
    text[HALO_CHAT_TEXT_SIZE - 1] = 0;
    answer = g_chat_answer;
    pthread_mutex_unlock(&g_chat_lock);
    return answer;
}

/* ---- the menus' text fields: Server Setup's game name and password, the join password, Direct Link's invite link. The game's
 * field asks (halo_ios_text_prompt, from its thread) and the phone shows a prompt with a text field, and its keyboard, over the game:
 * what is typed shows in it as it is typed (a password as dots), and OK or Cancel answers. */

#define HALO_PROMPT_TEXT_SIZE 160

static pthread_mutex_t g_prompt_lock = PTHREAD_MUTEX_INITIALIZER;
static char g_prompt_text[HALO_PROMPT_TEXT_SIZE];
static int g_prompt_wanted;     /* the game has a prompt open */
static int g_prompt_answer;     /* 0 open, 1 OK, 2 cancelled */
static int g_prompt_serial;     /* each prompt's own, so a late answer of one the game let go of is not the next one's */
static __weak UIAlertController *g_prompt_alert;   /* (main queue) */

static void HaloPromptFinish(int serial, int answer, NSString *text)
{
    pthread_mutex_lock(&g_prompt_lock);
    if (g_prompt_wanted && serial == g_prompt_serial && !g_prompt_answer) {
        snprintf(g_prompt_text, sizeof g_prompt_text, "%s", text.UTF8String ?: "");
        g_prompt_answer = answer;
    }
    pthread_mutex_unlock(&g_prompt_lock);
}

static UIViewController *HaloPromptPresenter(void)
{
    UIViewController *top = UIApplication.sharedApplication.delegate.window.rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

static void HaloPromptShow(int kind, NSString *start, int serial)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = HaloPromptPresenter();
        if (!presenter) { HaloPromptFinish(serial, 2, @""); return; }
        BOOL password = kind == 3, link = kind == 4;
        NSString *title = link ? @"Join with an invite link" : password ? @"Password" : @"Game name";
        NSString *message = link ? @"Type or paste the host's invite link (halo://join/...)." :
            password ? @"Type the password." : nil;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = start;
            field.placeholder = link ? @"halo://join/..." : password ? @"Password" : @"Game name";
            field.secureTextEntry = password;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.spellCheckingType = UITextSpellCheckingTypeNo;
            field.smartQuotesType = UITextSmartQuotesTypeNo;
            field.smartDashesType = UITextSmartDashesTypeNo;
            field.keyboardType = link ? UIKeyboardTypeURL : UIKeyboardTypeASCIICapable;
            field.returnKeyType = UIReturnKeyDone;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            (void)action;
            HaloPromptFinish(serial, 2, @"");
        }]];
        __weak UIAlertController *weak = alert;
        [alert addAction:[UIAlertAction actionWithTitle:link ? @"Join" : @"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            HaloPromptFinish(serial, 1, weak.textFields.firstObject.text ?: @"");
        }]];
        g_prompt_alert = alert;
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static void HaloPromptHide(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = g_prompt_alert;
        g_prompt_alert = nil;
        if (alert.presentingViewController) [alert dismissViewControllerAnimated:NO completion:nil];
    });
}

int halo_ios_text_prompt(int kind, char text[HALO_PROMPT_TEXT_SIZE])
{
    int answer = 0;

    if (kind == 100) {
        pthread_mutex_lock(&g_prompt_lock);
        int was = g_prompt_wanted;
        g_prompt_wanted = 0;
        g_prompt_answer = 0;
        pthread_mutex_unlock(&g_prompt_lock);
        if (was) HaloPromptHide();
        return 0;
    }
    pthread_mutex_lock(&g_prompt_lock);
    if (!g_prompt_wanted) {
        g_prompt_wanted = 1;
        g_prompt_answer = 0;
        int serial = ++g_prompt_serial;
        text[HALO_PROMPT_TEXT_SIZE - 1] = 0;
        NSString *start = [NSString stringWithUTF8String:text] ?: @"";
        pthread_mutex_unlock(&g_prompt_lock);
        HaloPromptShow(kind, start, serial);
        return 0;
    }
    memcpy(text, g_prompt_text, HALO_PROMPT_TEXT_SIZE);
    text[HALO_PROMPT_TEXT_SIZE - 1] = 0;
    answer = g_prompt_answer;
    pthread_mutex_unlock(&g_prompt_lock);
    return answer;
}

