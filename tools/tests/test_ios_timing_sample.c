#undef NDEBUG
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "halo_timing_sample.h"
#include "halo_frame_diagnostics.h"
static unsigned reads;
static double tick(void){return ++reads*0.000001;}
int main(void){
 HaloTimingSampler sampler={0};unsigned samples=0;
 for(unsigned i=0;i<1048576;i++){
  HaloTimedSample s=halo_timing_begin(&sampler,10,tick);
  uint64_t ns=halo_timing_finish(s,tick);
  if(s.selected){samples++;assert(ns>=999 && ns<=1001);}else assert(!ns);
 }
 assert(samples>900 && samples<1150);assert(reads==samples*2);
 assert(halo_timing_estimated_ms(100,10,10000000)==100);
 assert(halo_timing_estimated_ms(100,0,10000000)==0);
 assert(!halo_timing_select(&sampler,0));assert(!halo_timing_select(&sampler,32));
 HaloTimedSample backward={1,100};assert(!halo_timing_finish(backward,tick));
 HaloTimedSample invalid={1,NAN};assert(!halo_timing_finish(invalid,tick));
 HaloSlowFrames frames={0},output;
 assert(halo_slow_frame_slot(&frames,25000000)==-1);
 assert(halo_slow_frame_slot(&frames,250000001)==-1);assert(frames.long_gaps==1);
 for(unsigned i=26;i<=40;i++){
  uint64_t ns=(uint64_t)i*1000000;int slot=halo_slow_frame_slot(&frames,ns);
  if(slot>=0)frames.frames[slot].interval_ns=ns;
 }
 assert(frames.slow_count==15 && frames.count==8);
 for(unsigned i=0;i<8;i++)assert(frames.frames[i].interval_ns>=33000000);
 assert(halo_slow_frame_slot(&frames,26000000)==-1);
 halo_slow_frames_take(&frames,&output);assert(frames.count==0 && frames.slow_count==0 && frames.long_gaps==0);
 assert(output.count==8 && output.slow_count==16 && output.long_gaps==1);
 frames.frames[0].interval_ns=1;assert(output.frames[0].interval_ns>=33000000);
 printf("PASS: %u clock samples / 1048576 calls, exact clock count, estimates and bounded slow-frame retention\n",samples);
 return 0;
}
