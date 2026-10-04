"""Execute the actual iOS Jump-thrust block against campaign/seat/input cases."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "source/units/bipeds.c").read_text(encoding="utf-8")
start = source.index("    /* Touch-friendly thrust:")
body = source[source.index("    if (ios_cheat_enabled", start):source.index("#endif", start)]
harness = r'''
#include <stdio.h>
#define NONE (-1)
#define TRUE 1
#define MAX(a,b) ((a)>(b)?(a):(b))
#define TEST_FLAG(v,b) ((v)&(1u<<(b)))
#define SET_FLAG(v,b,on) ((v)=(on)?((v)|(1u<<(b))):((v)&~(1u<<(b))))
enum { IOS_CHEAT_JETPACK=1,_unit_control_jump_bit=0,_biped_airborne_bit=1 };
static int campaign,enabled;
static int ios_cheat_enabled(long index,unsigned flag){return campaign && enabled && index==7 && flag==IOS_CHEAT_JETPACK;}
struct Biped {struct {long parent_seat_index;unsigned control_flags;} unit;
struct {struct {float k;} translational_velocity;} object;struct {unsigned flags;} biped;};
static void tick(long biped_index,struct Biped *biped){ BODY }
#define CHECK(v) do{if(!(v)){printf("FAIL: line %d\n",__LINE__);return 1;}}while(0)
int main(void){
struct Biped b={0};b.unit.parent_seat_index=NONE;b.unit.control_flags=1;
campaign=enabled=1;tick(7,&b);CHECK(b.object.translational_velocity.k==.12f && TEST_FLAG(b.biped.flags,_biped_airborne_bit));
b.object.translational_velocity.k=.2f;tick(7,&b);CHECK(b.object.translational_velocity.k==.2f);
b.object.translational_velocity.k=-.1f;b.unit.control_flags=0;tick(7,&b);CHECK(b.object.translational_velocity.k==-.1f);
b.unit.control_flags=1;b.unit.parent_seat_index=0;tick(7,&b);CHECK(b.object.translational_velocity.k==-.1f);
b.unit.parent_seat_index=NONE;campaign=0;tick(7,&b);CHECK(b.object.translational_velocity.k==-.1f);
campaign=1;tick(8,&b);CHECK(b.object.translational_velocity.k==-.1f);
enabled=0;tick(7,&b);CHECK(b.object.translational_velocity.k==-.1f);
puts("PASS: Jump thrust, release, stronger impulses, seat exclusion and campaign/owner gate");return 0;}
'''.replace("BODY", body)
with tempfile.TemporaryDirectory() as folder:
    source_path = Path(folder) / "jetpack.c"
    output = Path(folder) / "jetpack-test"
    source_path.write_text(harness, encoding="utf-8")
    subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", str(source_path), "-o", str(output)], check=True)
    subprocess.run([str(output)], check=True)
