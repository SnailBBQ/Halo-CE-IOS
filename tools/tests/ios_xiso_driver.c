#include "halo_xiso.h"
#include <stdio.h>
#include <stdlib.h>
static int progress(void *context,const char *file,uint64_t done,uint64_t total){
    (void)file;(void)total;return *(int *)context && done>=262144;
}
int main(int argc,char **argv){
    if(argc<3)return 2;char error[512];int cancel=argc>3?atoi(argv[3]):0;
    int result=halo_xiso_extract(argv[1],argv[2],progress,&cancel,error,sizeof(error));
    printf("%d\n%s\n",result,error);return result==1?0:result==-1?3:1;
}
