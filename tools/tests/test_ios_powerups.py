from pathlib import Path
import argparse,subprocess,tempfile,os
r=Path(__file__).resolve().parents[2]
s=(r/'source/game/cheats.c').read_text(encoding='utf-8')
start=s.index('static void ios_powerups_tick(void) {');end=s.index('/* UI request IDs',start)
body=s[start:end]
h=r'''
#include <stdio.h>
#include "halo_ios_campaign_options.h"
#define NONE (-1)
#define TEST_FLAG(a,b) ((a)&(1u<<(b)))
enum {_object_dead_bit=0,_object_shield_over_charging_bit=1,_player_powerup_active_camouflage=0};
struct player_datum {long unit_index;};
struct unit_datum {struct {unsigned damage_flags;float shield_vitality;} object;};
static struct player_datum player={4};static struct unit_datum unit;
static HaloCampaignOptions ios_options;static int solo=1,camo_calls,charge_calls,last_duration;
static long cheat_player_index(void){return 0;}
#define MAXIMUM_LOCAL_PLAYERS 4
static short ios_target_players(long *out){long i=cheat_player_index();if(i==NONE)return 0;out[0]=i;return 1;}
static struct player_datum *player_try_and_get(long i){return i==0?&player:0;}
static int ios_cheat_local_unit(long i){return solo&&i==4;}
static struct unit_datum *unit_get(long i){(void)i;return &unit;}
static void player_handle_powerup_minor(long i,short type,short duration){(void)i;(void)type;camo_calls++;last_duration=duration;}
static int object_double_charge_shield(long i){(void)i;charge_calls++;return 1;}
'''+body+r'''
#define CHECK(x) do {if(!(x)){printf("FAIL line %d\n",__LINE__);return 1;}}while(0)
int main(void) {
 ios_options.flags=IOS_CHEAT_CAMO|IOS_CHEAT_OVERSHIELD;ios_powerups_tick();CHECK(camo_calls==1&&last_duration==2&&charge_calls==1);
 unit.object.shield_vitality=2;ios_powerups_tick();CHECK(unit.object.shield_vitality==3);
 unit.object.shield_vitality=2;ios_options.flags=0;ios_powerups_tick();CHECK(unit.object.shield_vitality==2&&camo_calls==2);
 ios_options.flags=IOS_CHEAT_CAMO|IOS_CHEAT_OVERSHIELD;solo=0;ios_powerups_tick();CHECK(camo_calls==2&&charge_calls==1);
 solo=1;unit.object.damage_flags=1;ios_powerups_tick();CHECK(camo_calls==2&&charge_calls==1);
 puts("PASS: infinite powerups refresh only living solo player, release stops refresh, normal overshield stays damage-consumable");return 0;
}
'''
parser=argparse.ArgumentParser();parser.add_argument('--emit');args=parser.parse_args()
if args.emit:Path(args.emit).write_text(h,encoding='utf-8')
else:
 with tempfile.TemporaryDirectory() as temp:
  file=Path(temp)/'test.c';file.write_text(h,encoding='utf-8');exe=Path(temp)/'test'
  subprocess.run([os.environ.get('CC','cc'),'-std=c11','-Wall','-Wextra','-Werror','-I'+str(r/'port/include'),str(file),'-o',str(exe)],check=True)
  subprocess.run([str(exe)],check=True)
