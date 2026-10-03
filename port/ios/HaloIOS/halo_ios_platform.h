#ifndef HALO_IOS_PLATFORM_H
#define HALO_IOS_PLATFORM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Called from guest threads (through the SDL clipboard and toast imports). */
void halo_ios_clipboard_set(const char *text);
/* NULL clears the active invite and replaces the sharing file with an empty file. */
void halo_ios_set_hosted_invite(const char *text);
/* An invite opened through a halo:// link wins; otherwise the pasteboard, if
 * "Join invites on the clipboard" is on. Writes an empty string if none. */
void halo_ios_clipboard_get(char *buffer, size_t size);
void halo_ios_toast(const char *text);

#ifdef __cplusplus
}
#endif

#ifdef __OBJC__
#import <Foundation/Foundation.h>
/* An invite opened through a halo:// link or "Join from clipboard"; the game picks it up
 * as if it were on the clipboard. */
void HaloSetPendingInvite(NSString *invite);
/* The invite this copy of the game is hosting, or nil. */
NSString *HaloLastHostedInvite(void);
/* Joins an invite typed or pasted by the player; NO (and a message) if it is not an invite. */
BOOL HaloJoinInviteText(NSString *text);
/* Reads the pasteboard (a deliberate button press) and joins an invite found there. */
BOOL HaloJoinInviteFromClipboard(void);
#endif

#endif
