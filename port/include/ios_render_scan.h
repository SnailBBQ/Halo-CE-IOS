#ifndef HALO_IOS_RENDER_SCAN_H
#define HALO_IOS_RENDER_SCAN_H
#include <stdint.h>
/* Fixed-width ILP32 packets. Native helpers retain no guest addresses or state.
   Results are written only after every input has validated and the scan ends. */
enum halo_render_scan_kind { HALO_SCAN_INDICES=1, HALO_SCAN_PALETTE,
    HALO_SCAN_SHADER, HALO_SCAN_TEXTURE, HALO_SCAN_SHADER_HASH };
/* Packet interpretation (all unused fields zero):
   INDICES: head=input u16 span, size=element count, result=two u32 bounds.
   PALETTE: head=256 u32 colors (zero allowed), result=one u32 hash.
   SHADER_HASH: head=key bytes, size=byte count divisible by four, result=u32.
   SHADER: head=list, size=node bytes, next=next-pointer offset,
     key_offset/key_size=node key span, key=comparison bytes,
     hash_offset/hash=optional filter, use_hash=0 none/1 filter/2 single node,
     result=u32 guest node address (zero means miss).
   TEXTURE: head/list, size/node bytes, next/next-pointer offset,
     key_offset=three adjacent resource words, key=four words including palette
     hash, hash_offset=palette-hash offset, hash=last-used-frame offset,
     result=three u32 words: matched address, variant count, oldest address.
   The unusual TEXTURE field reuse keeps one small fixed-width packet; it is
   decoded only after kind validation. No native/guest struct pointers cross ABI. */
struct halo_render_scan_packet { uint32_t kind,head,size,next,key_offset,key_size,
    key,hash_offset,hash,use_hash,result; };
#ifdef HALO_IOS_GUEST
void host_render_scan(unsigned int packet);
void host_uniform_apply(int location,unsigned int shadow,unsigned int value,unsigned int count,unsigned int scalar);
#endif
#endif
