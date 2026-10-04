"""Exercise the actual one-shot grenade handler, including map capacity and invalid data."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
s=(ROOT/'source/game/cheats.c').read_text(encoding='utf-8')
a=s.index('    if (action == 400 || action == 401) {')
b=s.index('    if (ios_world_action(action)) return;',a)
body=s[a:b]
harness=r'''
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
struct game_globals_grenade {short maximum_count;};
struct game_globals {struct {int count;} grenades;};
struct player_datum {long unit_index;};
struct unit_datum {struct {signed char grenade_counts[2];} unit;};
static struct game_globals globals={{2}};static struct game_globals_grenade types[2]={{4},{4}};
static struct player_datum player={7};static struct unit_datum unit;
static int present=1,adds;static char toast[128];
static struct game_globals *scenario_get_game_globals(void){return present?&globals:NULL;}
static long cheat_player_index(void){return 0;}
static struct player_datum *player_get(long i){(void)i;return &player;}
static struct unit_datum *unit_get(long i){(void)i;return &unit;}
static void host_toast(const char *s){snprintf(toast,sizeof(toast),"%s",s);}
static short unit_add_grenade_type_to_inventory(long i,short t,short n){(void)i;adds++;unit.unit.grenade_counts[t]+=n;return unit.unit.grenade_counts[t];}
#define TAG_BLOCK_GET_ELEMENT(block,index,type) (&types[index])
static void give(unsigned action){BODY}
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x);return 1;}}while(0)
int main(void){
 give(400);CHECK(unit.unit.grenade_counts[0]==4 && unit.unit.grenade_counts[1]==0 && adds==1);
 give(400);CHECK(adds==1);give(401);CHECK(unit.unit.grenade_counts[1]==4 && adds==2);
 types[0].maximum_count=8;give(400);CHECK(unit.unit.grenade_counts[0]==8 && adds==3);
 unit.unit.grenade_counts[0]=10;give(400);CHECK(unit.unit.grenade_counts[0]==10 && adds==3);
 types[0].maximum_count=0;give(400);CHECK(adds==3 && strstr(toast,"unsupported"));
 types[0].maximum_count=128;give(400);CHECK(adds==3 && strstr(toast,"unsupported"));
 types[0].maximum_count=4;unit.unit.grenade_counts[0]=-1;give(400);CHECK(adds==3 && strstr(toast,"invalid"));
 globals.grenades.count=1;give(401);CHECK(adds==3 && strstr(toast,"not available"));
 present=0;give(400);CHECK(adds==3 && strstr(toast,"not available"));
 puts("PASS: grenade types, one-shot refills, map capacities, over-capacity preservation and invalid inventory/metadata rejection");return 0;
}
'''.replace('BODY',body)
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'test.c').write_text(harness,encoding='utf-8')
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(p/'test.c'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
