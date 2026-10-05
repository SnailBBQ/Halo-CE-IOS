#include <assert.h>
#include "halo_coop_input.h"
int main(void) {
    int a,b;
    halo_coop_route(0,0,&a,&b);assert(a==-1&&b==0);
    halo_coop_route(1,0,&a,&b);assert(a==-1&&b==0);
    halo_coop_route(0,1,&a,&b);assert(a==-1&&b==1);
    halo_coop_route(1,1,&a,&b);assert(a==0&&b==1);
    uint32_t held[2]={0};int32_t axes[2][6]={{0}};
    assert(halo_coop_switch_ready(held,axes));
    held[0]=1;assert(!halo_coop_switch_ready(held,axes));held[0]=0;
    held[1]=2;assert(!halo_coop_switch_ready(held,axes));held[1]=0;
    axes[0][0]=8000;assert(halo_coop_switch_ready(held,axes));
    axes[0][0]=8001;assert(!halo_coop_switch_ready(held,axes));axes[0][0]=0;
    axes[1][5]=-8001;assert(!halo_coop_switch_ready(held,axes));
    axes[1][5]=INT32_MIN;assert(!halo_coop_switch_ready(held,axes));
    return 0;
}
