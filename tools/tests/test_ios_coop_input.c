#include <assert.h>
#include "halo_coop_input.h"
int main(void) {
    int a,b;
    halo_coop_route(0,0,&a,&b);assert(a==-1&&b==0);
    halo_coop_route(1,0,&a,&b);assert(a==-1&&b==0);
    halo_coop_route(0,1,&a,&b);assert(a==-1&&b==1);
    halo_coop_route(1,1,&a,&b);assert(a==0&&b==1);
    return 0;
}
