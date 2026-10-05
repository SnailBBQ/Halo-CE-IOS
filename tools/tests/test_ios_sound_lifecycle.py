"""Compile the real definition-preemption path and its iOS caller guards."""
from pathlib import Path
import re, subprocess, tempfile, os
root=Path(__file__).resolve().parents[2]
s=(root/'source/sound/sound_manager.c').read_text(encoding='utf-8')
m=re.search(r'static void sound_set_definition_end\s*\([^;]*?\)\s*\{',s)
start=m.start(); pos=m.end(); depth=1
while depth:
 depth+=(s[pos]=='{')-(s[pos]=='}');pos+=1
fn=s[start:pos]
a=s.index('long changing_sound_index ='); b=s.index('#else',a)
guard=s[a:b]
outer=s[s.index('/* The looping update may'):]
assert 'if (channel->sound_index == NONE)\n\t\t\t\tcontinue;' in outer
cache=(root/'source/cache/xbox_sound_cache.c').read_text(encoding='utf-8')
assert re.search(r'263,\s*cache_sound->software_reference_count\);',cache)
code=r'''
#include <assert.h>
#define NONE -1
#define TRUE 1
#define _sound_waiting_for_cache_bit 1
#define SET_FLAG(flags,bit,value) ((flags)|=(bit))
struct sound_datum {int flags,definition_index,next_definition_index,pitch_range_index,permutation_index,playing_channel_index;float pitch;};
struct sound_definition {int unused;};
struct sound_channel_summary {int like_source_count,maximum_source_instance_count,like_definition_count,maximum_instance_count,like_source_channels[2],like_definition_channels[2];};
struct sound_channel_datum {int sound_index;};
static struct sound_datum current;
static struct sound_definition definition;
static struct sound_channel_datum channels[2];
static struct sound_channel_summary summary;
static int chosen, stopped, continued,alive;
static void *sound_data;
static struct sound_datum *datum_get(void *data,long index){(void)data;assert(index==10 && alive);return &current;}
static struct sound_datum *sound_get(long index){return datum_get(sound_data,index);}
static struct sound_definition *sound_definition_get(long index){assert(index==2);return &definition;}
static int sound_definition_find_pitch_range_by_pitch(void *d,float p,int old){(void)d;(void)p;(void)old;return 3;}
static int sound_definition_next_permutation(void *d,int p,int old){(void)d;(void)p;assert(old==NONE);return 4;}
static void sound_channel_summary_build(struct sound_channel_summary *out,long index){assert(index==10);*out=summary;}
static short sound_find_like_channel(long index,int *list,int count){(void)list;(void)count;assert(index==10);return chosen;}
static struct sound_channel_datum *channel_get(short index){assert(index==0 || index==1);return &channels[index];}
static void sound_stop(long index){stopped=index;if(index==10){alive=0;channels[0].sound_index=NONE;}}
'''+fn+'\nstatic void caller(void){struct sound_channel_datum *channel=&channels[0];\n'+guard+r'''
assert(alive);continued++;
}
static void reset(void){current=(struct sound_datum){.next_definition_index=2,.playing_channel_index=0};channels[0].sound_index=10;channels[1].sound_index=11;summary=(struct sound_channel_summary){.maximum_source_instance_count=2,.maximum_instance_count=2};chosen=NONE;stopped=continued=0;alive=1;}
int main(void){
reset();caller();assert(continued==1 && !stopped && current.definition_index==2);
reset();summary.like_source_count=2;caller();assert(stopped==10 && !continued && !alive);
reset();summary.like_source_count=2;chosen=0;caller();assert(stopped==10 && !continued);
reset();summary.like_definition_count=2;caller();assert(stopped==10 && !continued);
reset();summary.like_definition_count=2;chosen=1;caller();assert(stopped==11 && continued==1 && alive);
return 0;}
'''
with tempfile.TemporaryDirectory() as td:
 c=Path(td)/'sound.c';exe=Path(td)/('sound.exe' if os.name=='nt' else 'sound')
 c.write_text(code,encoding='utf-8')
 subprocess.run(['cc','-std=c11','-O0',str(c),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
print('PASS: real sound definition preemption; self-stop guards, other-channel preemption and live continuation; underflow assertion retained')
