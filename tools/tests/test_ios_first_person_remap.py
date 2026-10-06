from pathlib import Path
import argparse, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'source/interface/first_person_weapons.c').read_text(encoding='utf-8-sig')
start = source.rindex('static void model_remap_node_matrices_to_match_animation_graph(')
opening = source.index('{', start)
depth=1; end=opening+1
while depth:
    depth += (source[end]=='{') - (source[end]=='}')
    end += 1
function=source[start:end]
harness=r'''
#include <assert.h>
#include <float.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#define HALO_IOS_GUEST 1
#define MAXIMUM_NODES_PER_ANIMATION 64
#define NONE -1
#define TRUE 1
#define FALSE 0
#define MIN(a,b) ((a)<(b)?(a):(b))
#define _error_log 0
typedef int boolean;
typedef float real;
typedef struct { real x,y,z; } real_point3d;
typedef struct { real i,j,k; } real_vector3d;
typedef struct real_matrix4x3 {
    real scale;
    real_vector3d forward,left,up;
    real_point3d position;
} real_matrix4x3;
struct model { struct { long count; } nodes; } fake_model;
struct animation_graph { struct { long count; } nodes; } fake_graph;
static struct { struct { real_point3d position; } camera; } render;
static struct model *model_definition_get(long index) { (void)index; return &fake_model; }
static struct animation_graph *animation_graph_definition_get(long index) { (void)index; return &fake_graph; }
static long game_time_get(void) { return 0; }
#define match_assert(file,line,condition) assert(condition)
static void error(int level, const char *format, ...) { (void)level; (void)format; }
'''+function+r'''
int main(void)
{
    real_matrix4x3 bones[64], out[64];
    short remap[64];
    memset(bones,0,sizeof(bones));
    for (int i=0;i<64;++i) {
        bones[i].scale=1; bones[i].forward.i=1; bones[i].left.j=1; bones[i].up.k=1;
        bones[i].position.x=(float)i;
        remap[i]=(short)i;
    }
    fake_model.nodes.count=fake_graph.nodes.count=3;
    remap[0]=2;remap[1]=0;remap[2]=1;
    memset(out,0x5a,sizeof(out));
    model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap);
    assert(!memcmp(out,&bones[2],sizeof(*out)));
    assert(!memcmp(out+1,bones,sizeof(*out)));
    assert(!memcmp(out+2,bones+1,sizeof(*out)));
    real_matrix4x3 sentinel[64];
    memset(sentinel,0x5a,sizeof(sentinel));
    remap[0]=-1; memcpy(out,sentinel,sizeof(out));
    model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap);
    assert(!memcmp(out,sentinel,sizeof(out)));
    remap[0]=3; memcpy(out,sentinel,sizeof(out));
    model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap);
    assert(!memcmp(out,sentinel,sizeof(out)));
    remap[0]=0;
    bones[0].scale=NAN;
    for (int i=0;i<10;++i) { memcpy(out,sentinel,sizeof(out)); model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap); assert(!memcmp(out,sentinel,sizeof(out))); }
    bones[0].scale=1; bones[0].position.x=INFINITY; memcpy(out,sentinel,sizeof(out));
    model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap); assert(!memcmp(out,sentinel,sizeof(out)));
    bones[0].position.x=0;
    fake_model.nodes.count=65; memcpy(out,sentinel,sizeof(out));
    model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap); assert(!memcmp(out,sentinel,sizeof(out)));
    fake_model.nodes.count=3;fake_graph.nodes.count=65; memcpy(out,sentinel,sizeof(out));
    model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap); assert(!memcmp(out,sentinel,sizeof(out)));
    fake_graph.nodes.count=0; memcpy(out,sentinel,sizeof(out));
    model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap); assert(!memcmp(out,sentinel,sizeof(out)));
    fake_model.nodes.count=fake_graph.nodes.count=64;
    for (int i=0;i<64;++i) remap[i]=(short)i;
    model_remap_node_matrices_to_match_animation_graph(1,out,2,bones,remap);
    assert(!memcmp(out,bones,sizeof(bones)));
    puts("first-person actual remap: valid ordering, bounds and repeated nonfinite rejection passed");
    return 0;
}
'''
parser=argparse.ArgumentParser()
parser.add_argument('--emit',type=Path)
args=parser.parse_args()
if args.emit:
    args.emit.write_text(harness,encoding='utf-8')
else:
    with tempfile.TemporaryDirectory() as folder:
        src=Path(folder)/'remap.c'; exe=Path(folder)/'remap'
        src.write_text(harness,encoding='utf-8')
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(src),'-lm','-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
