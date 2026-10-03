"""Exercise production GPU mirror against a zero-generation iOS memory-watch host."""
from pathlib import Path
import argparse, subprocess, tempfile, os
ROOT=Path(__file__).resolve().parents[2]
PREFIX='#include <assert.h>\n#include <stdio.h>\n#include <stdint.h>\n#include <stdlib.h>\n#include <string.h>\n#define HALO_IOS_GUEST 1\n#define HALO_ANDROID 1\n#define TRUE 1\n#define FALSE 0\ntypedef int BOOL;\ntypedef unsigned GLuint;\ntypedef intptr_t GLintptr;\ntypedef intptr_t GLsizeiptr;\n#define PLATFORM_CONTIGUOUS_BASE ((unsigned long)(uintptr_t)memory)\n#define PLATFORM_CONTIGUOUS_SIZE 0x800000UL\n#define GL_COPY_WRITE_BUFFER 1\n#define GL_DYNAMIC_DRAW 2\nstatic unsigned char memory[PLATFORM_CONTIGUOUS_SIZE];\nstatic unsigned char gpu[2][0x400000];\nstatic struct { unsigned long frame; } device;\nstatic struct { unsigned long mirrored_bytes; } stats;\nstatic GLuint binding;\nstatic unsigned uploads;\nstatic unsigned long memory_watch_generation(unsigned long a,unsigned long b){(void)a;(void)b;return 0;}\nstatic void memory_watch_protect(unsigned long a,unsigned long b){(void)a;(void)b;}\nstatic void glGenBuffers(int n,GLuint *b){static GLuint next=1;assert(n==1);*b=next++;assert(*b<=2);}\nstatic void glBindBuffer(int target,GLuint b){assert(target==1);assert(b&&b<=2);binding=b;}\nstatic void glBufferData(int target,unsigned long size,const void *p,int usage){assert(target==1&&size==0x400000&&p==NULL&&usage==2);}\nstatic void glBufferSubData(int target,GLintptr offset,GLsizeiptr size,const void *p){assert(target==1&&offset>=0&&size>0&&offset+size<=0x400000);memcpy(gpu[binding-1]+offset,p,(size_t)size);++uploads;}\nstatic void host_gl_buffer_write(int target,unsigned int offset,unsigned int size,const void *p){glBufferSubData(target,offset,size,p);}\n'
TAIL='\nstatic void draw(unsigned long offset,unsigned long size){GLuint b;unsigned long o,g;assert(mirror_range(PLATFORM_CONTIGUOUS_BASE+offset,size,&b,&o,&g));assert(!memcmp(gpu[b-1]+o,memory+offset,size));}\nint main(void){\n memset(memory,1,sizeof(memory));draw(0,64);\n memory[0]=2;draw(0,64); /* same frame, zero generation */\n for(unsigned i=0;i<20;++i){++device.frame;memory[0]=(unsigned char)i;draw(0,64);}\n memset(memory,0xa5,sizeof(memory));draw(0,8192); /* map address reuse */\n memory[8192]=0x77;draw(4096,8192); /* overlapping refreshed ranges */\n draw(0,0x120000); /* batching >256 pages */\n GLuint b;unsigned long o;\n assert(!mirror_range(PLATFORM_CONTIGUOUS_BASE+0x3ffff0,32,&b,&o,NULL));\n assert(!mirror_range(PLATFORM_CONTIGUOUS_BASE,~0UL,&b,&o,NULL));\n assert(!mirror_range(PLATFORM_CONTIGUOUS_BASE,0,&b,&o,NULL));\n assert(!mirror_range(PLATFORM_CONTIGUOUS_BASE+PLATFORM_CONTIGUOUS_SIZE,1,&b,&o,NULL));\n assert(uploads>20);puts("zero-generation mirror coherence: passed");return 0;\n}\n'
def source():
    text=(ROOT/'port/linux/src/d3d8_gl.c').read_text(encoding='utf-8-sig')
    start=text.index('#define MIRROR_SEGMENT_SIZE')
    end=text.index('/* the smallest and largest index of an index range',start)
    return PREFIX+text[start:end]+TAIL
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--emit');args=parser.parse_args()
    if args.emit: Path(args.emit).write_text(source(),encoding='utf-8')
    else:
        with tempfile.TemporaryDirectory() as directory:
            c=Path(directory)/'mirror.c';exe=Path(directory)/'mirror'
            c.write_text(source(),encoding='utf-8')
            subprocess.run([os.environ.get('CC','cc'),'-std=c11','-Wall','-Wextra','-Werror',str(c),'-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)
