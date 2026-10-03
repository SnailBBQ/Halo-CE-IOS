"""Exercise the actual engine crosshair query with controlled collision outcomes.

The Apple workflow also compiles its real engine headers. --emit writes the
same fixture for environments with a compiler other than cc.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "source/game/aim_assist.c").read_text(encoding="utf-8")
start = source.index("boolean ios_crosshair_has_enemy(")
end = source.index("\n#endif", start)
function = source[start:end]
assert '"host_touch_auto_fire"' in (ROOT / "tools/ios_gl_stubs.py").read_text(encoding="utf-8")
assert 'MAP("host_touch_auto_fire", ios_touch_auto_fire)' in (ROOT / "port/ios/HaloIOS/halo_guest_runner.m").read_text(encoding="utf-8")

fixture = r'''
#include <assert.h>
#include <math.h>
#include <stdio.h>
typedef int boolean;
typedef struct { float x,y,z; } real_point3d;
typedef struct { float i,j,k; } real_vector3d;
#define FALSE 0
#define TRUE 1
#define NONE (-1)
#define TEST_FLAG(mask,bit) (((mask) & (1u << (bit))) != 0)
enum { _object_dead_bit=0, _object_invisible_bit=1, _object_mask_unit=6,
    _collision_user_aim_assist=3, _collision_test_for_projectiles_flags=7,
    MAXIMUM_COLLISION_USER_STACK_DEPTH=16 };
struct player_datum { long unit_index; short team_index; };
struct collision_result { long object_index; };
struct object_datum { struct { int type; unsigned damage_flags,flags; short owner_team_index; } object; };
static struct player_datum player;
static struct object_datum target;
static int global_current_collision_user_depth=1;
static int global_current_collision_users[16];
static int collision_hit, target_exists, ray_calls, zero_direction;
static long hit_index;
static struct player_datum *player_get(long index) { assert(index==0); return &player; }
static void director_camera_deterministic(long unit,real_point3d *p,real_vector3d *v) {
    assert(unit==10);p->x=1;p->y=2;p->z=3;v->i=zero_direction?0:2;v->j=0;v->k=0;
}
static float normalize3d(real_vector3d *v) {
    float n=sqrtf(v->i*v->i+v->j*v->j+v->k*v->k);
    if(n) { v->i/=n;v->j/=n;v->k/=n; } return n;
}
static void scale_vector3d(const real_vector3d *v,float scale,real_vector3d *out) {
    out->i=v->i*scale;out->j=v->j*scale;out->k=v->k*scale;
}
static int collision_test_vector(int flags,const real_point3d *p,const real_vector3d *v,long ignore,struct collision_result *out) {
    assert(flags==_collision_test_for_projectiles_flags && ignore==10);
    assert(p->x==1 && p->y==2 && p->z==3 && v->i==128 && v->j==0 && v->k==0);
    assert(global_current_collision_user_depth==2 && global_current_collision_users[1]==_collision_user_aim_assist);
    ray_calls++;out->object_index=hit_index;return collision_hit;
}
static struct object_datum *object_try_and_get(long index) { assert(index==hit_index);return target_exists?&target:NULL; }
static int game_team_is_enemy(short a,short b) { return a!=b; }
'''
fixture += function
fixture += r'''
static void reset(void) {
    player.unit_index=10;player.team_index=0;target.object.type=1;
    target.object.damage_flags=target.object.flags=0;target.object.owner_team_index=1;
    collision_hit=target_exists=1;hit_index=20;ray_calls=zero_direction=0;
    global_current_collision_user_depth=1;
}
static void expect(int value) { assert(ios_crosshair_has_enemy(0)==value);assert(global_current_collision_user_depth==1); }
int main(void) {
    reset();expect(1);assert(ray_calls==1);
    reset();collision_hit=0;expect(0);
    reset();hit_index=NONE;expect(0); /* scenery/wall is the first collision */
    reset();target_exists=0;expect(0);
    reset();hit_index=10;expect(0);
    reset();target.object.type=3;expect(0);
    reset();target.object.damage_flags=1u<<_object_dead_bit;expect(0);
    reset();target.object.flags=1u<<_object_invisible_bit;expect(0);
    reset();target.object.owner_team_index=0;expect(0);
    reset();zero_direction=1;expect(0);assert(ray_calls==0);
    reset();player.unit_index=NONE;expect(0);assert(ray_calls==0);
    reset();global_current_collision_user_depth=16;
    assert(!ios_crosshair_has_enemy(0) && ray_calls==0 && global_current_collision_user_depth==16);
    puts("PASS: touch auto-fire exact ray, enemy/dead/friendly/scenery checks and balanced collision scope");
    return 0;
}
'''
if len(sys.argv) == 3 and sys.argv[1] == "--emit":
    Path(sys.argv[2]).write_text(fixture, encoding="utf-8")
else:
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)
        c = path / "aim.c"
        exe = path / "aim"
        c.write_text(fixture, encoding="utf-8")
        subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror", str(c), "-lm", "-o", str(exe)], check=True)
        subprocess.run([str(exe)], check=True)
