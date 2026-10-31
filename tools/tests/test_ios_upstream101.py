"""Exercise OpenCE 101 controller routing and in-progress lobby behavior."""
from pathlib import Path
import os,re,subprocess,tempfile,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[2]
def function(path,name):
 s=(root/path).read_text(encoding='utf-8');m=re.search(r'static boolean '+name+r'\s*\([^;]*?\)\s*\{',s);assert m
 p=m.end();depth=1
 while depth:depth+=(s[p]=='{')-(s[p]=='}');p+=1
 return s[m.start():p]
code=r'''
#include <assert.h>
#define TRUE 1
#define FALSE 0
#define NONE -1
#define MAXIMUM_LOCAL_PLAYERS 4
#define MAXIMUM_NUMBER_OF_LOCAL_PLAYERS 4
#define BUTTON_START 7
#define BUTTON_Y 8
#define LOBBY_NAME "lobby"
typedef int boolean;
struct widget_instance {short local_player_index;struct widget_instance *parent;};
struct advertised_game {int open,player_count,maximum_player_count;};
static struct advertised_game game={1,3,8};static struct advertised_game *active=&game;
static int playing[4],dispatched,failed,full,joined,initialized,posted;
static int route_by_controller,read_every_controller,dedicated_calls,dedicated_value;
static int lobby_joined_dedicated,listed_host;
static int we_are_at_the_main_menu=1,player_spawn_count=2,split_players=1,port_players=2;
static int pc_menu_split_players(void){return split_players;}
static int players_port_local_player_count(void){return port_players;}
static boolean pc_menu_screen_routes_by_controller(const struct widget_instance *w){(void)w;return route_by_controller;}
static boolean pc_menu_screen_reads_every_controller(const struct widget_instance *w){(void)w;return read_every_controller;}
static short controllers[2]={0,1};
static struct {int adding,controller;} lobby_join={0,NONE};
static short player_ui_get_single_player_local_player_controller(short p){return controllers[p];}
static struct advertised_game *preview_game(void){return active;}
static short lobby_local_player_count(void){return playing[0]+playing[1]+playing[2]+playing[3];}
static int lobby_controller_playing(short c){return c>=0 && c<4 && playing[c];}
static void player_ui_local_player_left_multiplayer_game(short c){assert(c>=0 && c<4);playing[c]=0;}
static void lobby_join_reset(void){lobby_join.adding=0;lobby_join.controller=NONE;}
static boolean campaign_fail(void){failed++;return FALSE;}
static void display_error_text_deferred(const void *text,int index){(void)text;assert(index==NONE);full++;}
static struct widget_instance *focused_leaf(struct widget_instance *w){return w;}
static void ui_widget_port_dispatch_event(struct widget_instance *w,int event,short c,boolean *deleted){(void)w;(void)c;(void)deleted;assert(event==BUTTON_START);dispatched++;}
static void event_manager_post_button(short c,int button){assert(c==0 && button==BUTTON_Y);posted++;}
static boolean multiplayer_player(short c){initialized++;playing[c]=1;return TRUE;}
static boolean p2p_joined_listed_host(void){return listed_host;}
static void lobby_dedicated_set(struct advertised_game *g,boolean dedicated){assert(g==active);dedicated_calls++;dedicated_value=dedicated;}
static boolean ui_widget_port_join(struct widget_instance *w,struct advertised_game *g,const char *name,boolean *deleted){(void)w;(void)name;(void)deleted;assert(g==active);joined=lobby_local_player_count();return TRUE;}
'''
code+=function('source/interface/ui_widget.c','widget_takes_any_controller')+'\n'+function('source/interface/ui_widget.c','widget_takes_events_of_controller')
for name in ('preview_add','preview_leave','preview_join'):code+='\n'+function('port/linux/game/menu_functions.c',name)
code+=r'''
int main(void){struct widget_instance w={0};boolean deleted=0;
assert(widget_takes_events_of_controller(&w,0));assert(widget_takes_events_of_controller(&w,1));assert(!widget_takes_events_of_controller(&w,2));assert(!widget_takes_events_of_controller(&w,-1));
we_are_at_the_main_menu=0;assert(!widget_takes_events_of_controller(&w,1));we_are_at_the_main_menu=1;player_spawn_count=1;assert(!widget_takes_events_of_controller(&w,1));player_spawn_count=2;
w.local_player_index=NONE;assert(widget_takes_events_of_controller(&w,2));w.local_player_index=1;assert(widget_takes_events_of_controller(&w,1));assert(!widget_takes_events_of_controller(&w,0));
/* build 182: with one person playing (not split) any controller drives the first player's menus */
w.local_player_index=0;split_players=0;assert(widget_takes_events_of_controller(&w,1) && widget_takes_events_of_controller(&w,2));
we_are_at_the_main_menu=0;port_players=2;assert(!widget_takes_events_of_controller(&w,2));port_players=1;assert(widget_takes_events_of_controller(&w,2));
we_are_at_the_main_menu=1;port_players=2;split_players=1;assert(!widget_takes_events_of_controller(&w,2));w.local_player_index=1;
/* Build 335: a routed screen accepts every controller at its root, but a child only takes its own. */
route_by_controller=1;assert(widget_takes_events_of_controller(&w,0));
struct widget_instance root={0};w.parent=&root;
assert(widget_takes_events_of_controller(&w,1) && !widget_takes_events_of_controller(&w,0));
w.parent=0;route_by_controller=0;w.local_player_index=0;read_every_controller=1;
assert(widget_takes_events_of_controller(&w,2));read_every_controller=0;w.local_player_index=1;
playing[0]=1;assert(!preview_add(&w,1,&deleted) && lobby_join.controller==1 && posted==1);
playing[1]=1;assert(!preview_add(&w,1,&deleted) && dispatched==1);
assert(preview_join(&w,0,&deleted) && joined==2 && !initialized && dedicated_calls==1 && !dedicated_value);
assert(!preview_leave(1) && !playing[1] && playing[0]);assert(preview_leave(0) && !lobby_local_player_count());
lobby_joined_dedicated=1;listed_host=1;
assert(preview_join(&w,0,&deleted) && initialized==1 && joined==1 && dedicated_calls==2 && dedicated_value);
game.player_count=7;assert(!preview_add(&w,1,&deleted) && full==1);
active=0;assert(!preview_add(&w,1,&deleted));assert(!preview_join(&w,0,&deleted));active=&game;
lobby_join.adding=1;assert(!preview_leave(2) && !lobby_join.adding && playing[0]);playing[1]=1;assert(preview_leave(2) && !lobby_local_player_count());
return 0;}
'''
with tempfile.TemporaryDirectory() as td:
 src=Path(td)/'test.c';exe=Path(td)/('test.exe' if os.name=='nt' else 'test');src.write_text(code,encoding='utf-8')
 subprocess.run([os.environ.get('CC','cc'),'-std=c11','-O0','-Wall','-Wextra','-Werror',str(src),'-o',str(exe)],check=True);subprocess.run([str(exe)],check=True)
xml=ET.parse(root/'port/assets/menus/ce/main_menu.multiplayer_type_select.lobby.xml')
widgets={w.attrib.get('name','').rsplit('/',1)[-1]:w for w in xml.iter('widget')}
assert any(e.attrib.get('run')=='port lobby preview add' for e in widgets['preview_screen'].findall('on'))
assert 'preview_button_add' in widgets
s=(root/'source/networking/network_game_globals.c').read_text(encoding='utf-8')
a=s.index('else if (!global_network_game_client)',s.index('boolean network_game_client_start_frame'))
b=s.index('else',a+8)
assert 'game_connection_set(0);' in s[a:b] and 'main_menu_ensure_player_queues_exist();' in s[a:b]
print('PASS: OpenCE101 co-op event routing, preview add/leave/join/full states, generated menu wiring and missing-client recovery branch')
