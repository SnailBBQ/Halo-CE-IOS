"""Exercise build 98 broker parsing, native split routing and confirmed quit dispatch."""
from pathlib import Path
import os, subprocess, tempfile
r=Path(__file__).resolve().parents[2]
def function(path, signature):
 s=(r/path).read_text(encoding='utf-8');start=s.index(signature);begin=s.index('{',start);depth=1;i=begin+1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i]
quit_fn=function('port/linux/src/sdl_platform.c','void platform_request_quit(void)')
split_fn=function('port/linux/game/menu_functions.c','unsigned char pc_menu_split_players(void)')
brokers_fn=function('port/linux/src/p2p_signal.c','static void brokers_list(')
common=r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
static jmp_buf stopped;
static int exited,pushed;
void host_exit(int code) __attribute__((noreturn));
void host_exit(int code){assert(code==0);exited++;longjmp(stopped,1);}
typedef struct {int type;} SDL_Event;
#define SDL_EVENT_QUIT 256
static void SDL_PushEvent(SDL_Event *event){assert(event->type==SDL_EVENT_QUIT);pushed++;}
#define NONE -1
static int player_spawn_count,local_count,playing_count,published;
static struct {int adding,controller;} lobby_join={0,NONE};
static short lobby_local_player_count(void){return local_count;}
static short players_port_local_player_count(void){return playing_count;}
static void host_settings_value(unsigned index,void *address,unsigned value){assert(index==(unsigned)-2 && !address);published=value;}
static const char *broker_name="brokers.txt",*contents;
static char opened[1024];
static const char *config_string(const char *key){assert(!strcmp(key,"network.brokers_file"));return broker_name;}
static void config_folder(char *out,size_t size){snprintf(out,size,"/data/Halo/");}
static char *config_file_read(const char *path,size_t *size){snprintf(opened,sizeof(opened),"%s",path);if(!contents)return NULL;*size=strlen(contents);char *copy=malloc(*size+1);assert(copy);memcpy(copy,contents,*size+1);return copy;}
static void platform_log(const char *text,...){(void)text;}
'''
main=r'''
int main(void){
 if(!setjmp(stopped))platform_request_quit();
#ifdef HALO_IOS_GUEST
 assert(exited==1 && !pushed);
#elif defined(HALO_ANDROID)
 assert(!exited && !pushed);
#else
 assert(!exited && pushed==1);
#endif
 assert(!pc_menu_split_players());
 lobby_join.adding=1;assert(pc_menu_split_players());lobby_join.adding=0;
 lobby_join.controller=1;assert(pc_menu_split_players());lobby_join.controller=NONE;
 local_count=2;assert(pc_menu_split_players());local_count=0;
 playing_count=2;assert(pc_menu_split_players());playing_count=0;
 player_spawn_count=2;assert(pc_menu_split_players());player_spawn_count=1;
 assert(!pc_menu_split_players());
#ifdef HALO_IOS_GUEST
 assert(published==1);
#endif
 char list[1024];contents="# note\r\nfirst.example:1883 # omitted\nsecond.example:1883\n";
 brokers_list(list,sizeof(list));assert(!strcmp(opened,"/data/Halo/brokers.txt"));
 assert(strstr(list,"first.example:1883") && strstr(list,"second.example:1883") && !strstr(list,"omitted") && !strstr(list,"note"));
 broker_name="/custom/network.txt";brokers_list(list,sizeof(list));assert(!strcmp(opened,broker_name));
 broker_name="C:\\custom\\network.txt";brokers_list(list,sizeof(list));assert(!strcmp(opened,broker_name));
 contents=NULL;brokers_list(list,sizeof(list));assert(!*list);
 puts("PASS: real quit dispatch, shared split routing and broker file parsing");return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);source=p/'test.c';source.write_bytes((common+quit_fn+'\n'+split_fn+'\n'+brokers_fn+'\n'+main).encode())
 for flags in (['-DHALO_IOS_GUEST=1','-DHALO_ANDROID=1'],['-DHALO_ANDROID=1'],[]):
  binary=p/'test';subprocess.run([os.environ.get('CC','cc'),'-std=c11','-Wall','-Wextra','-Werror','-Wno-unused-function',*flags,str(source),'-o',str(binary)],check=True);subprocess.run([str(binary)],check=True)
wf=(r/'.github/workflows/ios.yml').read_text(encoding='utf-8')
assert 'cp port/assets/network/brokers.txt "$APP/brokers.txt"' in wf
assert (r/'port/assets/network/brokers.txt').is_file()
runner=(r/'port/ios/HaloIOS/halo_guest_runner.m').read_text(encoding='utf-8')
assert 'if(g_guest_exit_code==0)halo_ios_quit_app();' in runner
assert 'NSDataWritingAtomic error:&brokerError' in runner
print('PASS: broker packaging and atomic installation; only normal zero-code guest exit quits the app')

for declaration in ("static _Atomic(uint32_t) g_phys_held[2];", "static _Atomic(int32_t) g_phys_axis[2][6];"):
 assert runner.index(declaration)<runner.index("static int ios_settings_value("), "native input state must be declared before the routing guard"
