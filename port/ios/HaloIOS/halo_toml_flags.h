#ifndef HALO_TOML_FLAGS_H
#define HALO_TOML_FLAGS_H
/* Reads and edits one `key = true|false` line of OpenCE's config.toml without disturbing the rest of the file (comments,
 * order, the player's edits). Plain C so the Settings screen's map-sharing switch can be tested on any machine.
 * A key counts when it is in [section], or written dotted at the top (section.key = ...). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static inline int halo_toml_is_space(char c) { return c==' ' || c=='\t' || c=='\r'; }
static inline int halo_toml_is_key_char(char c) {
    return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.';
}

/* One line (start..end, without '\n'). Fills *section when it is a [header]; returns 1 for a header, 2 for the wanted
 * key (value_start/value_end/value set), 0 otherwise. */
static inline int halo_toml_line(const char *start, const char *end, const char *current, const char *section, const char *key,
                                 const char **value_start, int *value) {
    const char *p=start;
    while(p<end && halo_toml_is_space(*p))p++;
    if(p>=end || *p=='#')return 0;
    if(*p=='['){return p+1<end && p[1]=='['?0:1;}
    const char *name=p;
    while(p<end && halo_toml_is_key_char(*p))p++;
    size_t length=(size_t)(p-name);
    while(p<end && halo_toml_is_space(*p))p++;
    if(!length || p>=end || *p!='=')return 0;
    size_t key_length=strlen(key),section_length=strlen(section);
    int match=0;
    if(!strcmp(current,section) && length==key_length && !strncmp(name,key,key_length))match=1;
    if(!current[0] && length==section_length+1+key_length && !strncmp(name,section,section_length) && name[section_length]=='.' &&
       !strncmp(name+section_length+1,key,key_length))match=1;
    if(!match)return 0;
    p++;
    while(p<end && halo_toml_is_space(*p))p++;
    int is_true=(end-p>=4 && !strncmp(p,"true",4) && (end-p==4 || !halo_toml_is_key_char(p[4])));
    int is_false=(end-p>=5 && !strncmp(p,"false",5) && (end-p==5 || !halo_toml_is_key_char(p[5])));
    if(!is_true && !is_false)return 0;
    *value_start=p;*value=is_true;
    return 2;
}

static inline int halo_toml_header_name(const char *start, const char *end, char *out, size_t size) {
    const char *p=start;
    while(p<end && halo_toml_is_space(*p))p++;
    if(p>=end || *p!='[')return 0;
    p++;
    while(p<end && halo_toml_is_space(*p))p++;
    size_t n=0;
    while(p<end && *p!=']' && !halo_toml_is_space(*p)){if(n+1<size)out[n++]=*p;p++;}
    out[n]=0;
    return 1;
}

/* 1 = true, 0 = false, -1 = not in the file. When the key repeats, the last one wins (as TOML readers that join do). */
static inline int halo_toml_get_bool(const char *text, const char *section, const char *key) {
    char current[64]="";
    int result=-1;
    const char *line=text;
    while(*line){
        const char *end=strchr(line,'\n');if(!end)end=line+strlen(line);
        const char *value_start=NULL;int value=0;
        int kind=halo_toml_line(line,end,current,section,key,&value_start,&value);
        if(kind==1)halo_toml_header_name(line,end,current,sizeof current);
        else if(kind==2)result=value;
        line=*end?end+1:end;
    }
    return result;
}

/* Returns a new malloc'ed text (caller frees) with every matching line set to value. When none matched and add_missing is
 * set, the key is added under [section] (the section is created at the end if needed). *changed says whether anything
 * differs from the input. */
static inline char *halo_toml_set_bool(const char *text, const char *section, const char *key, int value, int add_missing, int *changed) {
    size_t size=strlen(text);
    char *out=malloc(size+strlen(section)+strlen(key)+64);
    if(!out)return NULL;
    size_t used=0;
    char current[64]="";
    int matched=0,section_found=0,modified=0;
    size_t insert_at=(size_t)-1;
    const char *line=text;
    while(*line){
        const char *end=strchr(line,'\n');if(!end)end=line+strlen(line);
        const char *value_start=NULL;int old=0;
        int kind=halo_toml_line(line,end,current,section,key,&value_start,&old);
        size_t length=(size_t)(end-line)+(*end?1:0);
        if(kind==2){
            matched=1;
            size_t head=(size_t)(value_start-line),old_length=old?4:5;
            memcpy(out+used,line,head);used+=head;
            const char *word=value?"true":"false";
            size_t word_length=strlen(word);
            memcpy(out+used,word,word_length);used+=word_length;
            size_t tail=length-head-old_length;
            memcpy(out+used,value_start+old_length,tail);used+=tail;
            if(old!=value)modified=1;
        } else {
            memcpy(out+used,line,length);used+=length;
            if(kind==1){
                halo_toml_header_name(line,end,current,sizeof current);
                if(!strcmp(current,section)){section_found=1;insert_at=used;}
            }
        }
        line=*end?end+1:end;
    }
    out[used]=0;
    if(!matched && add_missing){
        char add[160];
        int add_length;
        char *grown;
        if(section_found){
            add_length=snprintf(add,sizeof add,"%s = %s\n",key,value?"true":"false");
            if(insert_at>0 && out[insert_at-1]!='\n'){memmove(out+insert_at+1,out+insert_at,used-insert_at+1);out[insert_at++]='\n';used++;}
            grown=realloc(out,used+(size_t)add_length+2);if(!grown){free(out);return NULL;}out=grown;
            memmove(out+insert_at+add_length,out+insert_at,used-insert_at+1);
            memcpy(out+insert_at,add,(size_t)add_length);used+=(size_t)add_length;
        } else {
            add_length=snprintf(add,sizeof add,"%s[%s]\n%s = %s\n",used&&out[used-1]!='\n'?"\n\n":"\n",section,key,value?"true":"false");
            grown=realloc(out,used+(size_t)add_length+2);if(!grown){free(out);return NULL;}out=grown;
            memcpy(out+used,add,(size_t)add_length+1);used+=(size_t)add_length;
        }
        modified=1;
    }
    if(changed)*changed=modified;
    return out;
}
#endif
