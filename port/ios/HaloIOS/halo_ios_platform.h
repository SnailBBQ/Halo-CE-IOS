#ifndef HALO_IOS_PLATFORM_H
#define HALO_IOS_PLATFORM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Called from guest threads (through the SDL clipboard and toast imports). */
void halo_ios_clipboard_set(const char *text);
/* NULL clears this app's hosted code; a different incoming PC invite is preserved. */
void halo_ios_set_hosted_invite(const char *text);
/* An invite opened through a halo:// link wins; otherwise the pasteboard, if
 * "Join invites on the clipboard" is on. Writes an empty string if none. */
void halo_ios_clipboard_get(char *buffer, size_t size);
void halo_ios_toast(const char *text);
/* The text chat's line, typed on the phone's own keyboard (called from the guest thread through host_settings_value's index -8).
 * mode 1 and up: a line is being typed, in `text` (64 bytes, ended), and the keyboard comes up if it is not. The line is the
 * keyboard's: `text` is replaced by what the field holds. The answer is 0 while typing, 1 when the player pressed Send (the line is
 * in `text`), 2 when the keyboard was closed without sending. mode 100: the guest ended the line; the keyboard goes. */
int halo_ios_chat_input(int mode, char text[64]);

#ifdef __cplusplus
}
#endif

#ifdef __OBJC__
#import <Foundation/Foundation.h>
/* An invite opened through a halo:// link or "Join from clipboard"; the game picks it up
 * as if it were on the clipboard. */
void HaloSetPendingInvite(NSString *invite);
/* Games hosted or joined, newest first (at most 8): dictionaries with "invite", "role" (Hosted or Joined) and "date". */
void HaloRecordRecentGame(NSString *invite, NSString *role);
NSArray<NSDictionary *> *HaloRecentGames(void);
void HaloClearRecentGames(void);
/* The invite this copy of the game is hosting, or nil. */
NSString *HaloLastHostedInvite(void);
/* Joins an invite typed or pasted by the player; NO (and a message) if it is not an invite. */
BOOL HaloJoinInviteText(NSString *text);
/* Reads the pasteboard (a deliberate button press) and joins an invite found there. */
BOOL HaloJoinInviteFromClipboard(void);
/* Document-picker grant; callbacks run on the main queue. I/O is serialized off
 * the game/UI threads and uses file coordination with the selected provider. */
NSString *HaloInviteFileLocation(void);
void HaloSelectInviteFolder(NSURL *folder, void (^completion)(NSError *error));
void HaloReadInviteFile(void (^completion)(NSString *text, NSError *error));
#endif

#endif
