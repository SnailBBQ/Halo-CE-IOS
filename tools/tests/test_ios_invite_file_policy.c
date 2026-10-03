#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "halo_invite_file_policy.h"
int main(void)
{
    const char *own="halo://join/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const char *pc="halo://join/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    char edited[1100];
    snprintf(edited,sizeof(edited)," \t%s\r\n",own);
    assert(halo_invite_clear_allowed(edited,own));
    memset(edited,'A',sizeof(edited));
    edited[sizeof(edited)-1]=0;
    assert(!halo_invite_clear_allowed(edited,own));
    /* Host stop and a later launch may clear only their last published code. */
    assert(!halo_invite_clear_allowed(pc,own));
    assert(!halo_invite_clear_allowed(pc,NULL));
    assert(!halo_invite_clear_allowed(own,NULL));
    assert(!halo_invite_clear_allowed(own,""));
    assert(!halo_invite_clear_allowed("",own));
    assert(!halo_invite_clear_allowed(NULL,own));
    snprintf(edited,sizeof(edited),"HALO://JOIN/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n");
    assert(halo_invite_clear_allowed(edited,own));
    /* New hosting replaces ownership; it may not clear the old host's code. */
    assert(!halo_invite_clear_allowed(own,pc));
    assert(halo_invite_clear_allowed(pc,pc));
    snprintf(edited,sizeof(edited),"%s-extra",own);
    assert(!halo_invite_clear_allowed(edited,own));
    puts("invite file ownership/PC preservation tests passed");
    return 0;
}
