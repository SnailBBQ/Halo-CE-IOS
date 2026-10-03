#ifndef HALO_INVITE_FILE_POLICY_H
#define HALO_INVITE_FILE_POLICY_H
#include <stddef.h>
/* Compare only bounded ASCII invite text. Unknown/empty ownership never grants
 * permission to clear a user-edited file. Whitespace/case changes to our own
 * link do not prolong a stale hosted code. No invite values are retained. */
static inline int halo_invite_clear_allowed(const char *existing, const char *owned)
{
    if (!existing || !owned || !*owned) return 0;
    size_t a=0,b=0;
    while (a<1024 && existing[a]) ++a;
    while (b<77 && owned[b]) ++b;
    if (a==1024 || b==77 || b==0) return 0;
    size_t first=0;
    while (first<a && (existing[first]==' ' || existing[first]=='\t' || existing[first]=='\r' || existing[first]=='\n')) ++first;
    while (a>first && (existing[a-1]==' ' || existing[a-1]=='\t' || existing[a-1]=='\r' || existing[a-1]=='\n')) --a;
    if (a-first!=b) return 0;
    for (size_t i=0;i<b;++i) {
        unsigned char x=(unsigned char)existing[first+i], y=(unsigned char)owned[i];
        if (x>='A' && x<='Z') x=(unsigned char)(x+'a'-'A');
        if (y>='A' && y<='Z') y=(unsigned char)(y+'a'-'A');
        if (x!=y) return 0;
    }
    return 1;
}
#endif
