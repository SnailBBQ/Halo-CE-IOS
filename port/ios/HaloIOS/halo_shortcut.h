#ifndef HALO_SHORTCUT_H
#define HALO_SHORTCUT_H
#include "halo_settings_core.h"

typedef struct {
    HsShortcut binding;
    unsigned progress;
    double start,last;
} HaloShortcutState;

/* A bounded, non-consuming sequence recognizer. Reject malformed imported
 * bindings instead of turning them into unexpectedly short shortcuts. */
static inline int halo_shortcut_press(HaloShortcutState *state,const HsShortcut *binding,int button,double now)
{
    int keys[16],count=0;
    const char *p=binding->sequence;
    if(strcmp(state->binding.sequence,binding->sequence) ||
       state->binding.gap!=binding->gap || state->binding.total!=binding->total ||
       state->binding.action!=binding->action) {
        state->binding=*binding;
        state->progress=0;
    }
    while(*p && count<16) {
        char *end;
        long key=strtol(p,&end,10);
        if(end==p || key<0 || key>16 || key==5 || (*end && *end!=',') || (*end==',' && !end[1])) {
            state->progress=0;return 0;
        }
        keys[count++]=(int)key;p=*end?end+1:end;
    }
    if(*p || !count || button<0 || button>16 || !isfinite(now)) {state->progress=0;return 0;}
    if(state->progress>=(unsigned)count || now<state->last ||
       now-state->last>binding->gap || now-state->start>binding->total)state->progress=0;
    if(keys[state->progress]!=button)state->progress=0;
    if(keys[state->progress]!=button)return 0;
    if(!state->progress)state->start=now;
    state->last=now;
    if(++state->progress!=(unsigned)count)return 0;
    state->progress=0;
    return 1;
}
#endif
