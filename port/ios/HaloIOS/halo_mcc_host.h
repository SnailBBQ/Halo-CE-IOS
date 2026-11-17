#ifndef HALO_IOS_MCC_HOST_H
#define HALO_IOS_MCC_HOST_H

/* OpenCE build 387 added optional Android host services. The iOS guest uses
 * a relocated 4 GiB arena, so an ordinary low fixed mmap cannot back MCC's
 * linked tag addresses. Refuse that map until its reservation can be checked
 * and committed through the guest arena. Hashing uses the engine's fallback.
 * Steam Workshop needs a Steam client, which the iOS host does not provide. */
#include <errno.h>
#include <stdint.h>
#include <string.h>

static long long ios_mcc_memory_reserve(uint32_t address, uint32_t size)
{
    (void)address;
    (void)size;
    return -ENOTSUP;
}

static int ios_mcc_memory_release(uint32_t address, uint32_t size)
{
    (void)address;
    (void)size;
    return -ENOTSUP;
}

/* Negative start lets mcc_resource_check.inl run its checked software hash. */
static int ios_mcc_hash_start(uint32_t request) { (void)request; return -1; }
static int ios_mcc_hash_wait(int id, int milliseconds, uint32_t result)
{ (void)id; (void)milliseconds; (void)result; return -1; }
static void ios_mcc_hash_cancel(int id) { (void)id; }

/* Hosting an MCC package needs an asynchronous SHA job. Decline it until
 * such a job is available; never provide an unverified package to a peer. */
static int ios_sha256_start(uint32_t path) { (void)path; return -1; }
static int ios_sha256_poll(int id, uint32_t digest, uint32_t size)
{ (void)id; (void)digest; (void)size; return -1; }
static void ios_sha256_cancel(int id) { (void)id; }

static void ios_steam_open(uint32_t root) { (void)root; }
static void ios_steam_close(void) {}
static int ios_steam_zero(void) { return 0; }
static int ios_steam_unavailable(void) { return -1; }
static void ios_steam_set_first(int value) { (void)value; }
static void ios_steam_set_chosen(int value) { (void)value; }
static void ios_steam_row(int place, uint32_t name, int name_size, uint32_t state, int state_size)
{ (void)place; (void)name; (void)name_size; (void)state; (void)state_size; }
static void ios_steam_details(int place, uint32_t title, int title_size, uint32_t text, int text_size,
                              uint32_t author, int author_size)
{ (void)place; (void)title; (void)title_size; (void)text; (void)text_size; (void)author; (void)author_size; }
static void ios_steam_choose(int place) { (void)place; }
static int ios_steam_picture(uint32_t key, uint32_t pixels)
{ (void)pixels; void *out = key ? halo_guest_ptr(key, 8) : NULL; if (out) memset(out, 0, 8); return 0; }
static int ios_steam_text_wanted(uint32_t initial, int size, uint32_t secret)
{ (void)initial; (void)size; (void)secret; return 0; }
static void ios_steam_text_caption(int kind, uint32_t text, int size)
{ (void)kind; char *out = text && size > 0 ? halo_guest_ptr(text, 1) : NULL; if (out) *out = 0; }
static void ios_steam_text_typed(int kind, uint32_t text, int saved)
{ (void)kind; (void)text; (void)saved; }
static int ios_steam_shared_fetch(uint32_t root) { (void)root; return -1; }
static int ios_steam_install_start(uint32_t root, uint32_t low, uint32_t high)
{ (void)root; (void)low; (void)high; return 0; }
static void ios_steam_install_progress(uint32_t progress)
{ void *out = progress ? halo_guest_ptr(progress, 3 * sizeof(uint32_t)) : NULL; if (out) memset(out, 0, 3 * sizeof(uint32_t)); }
static int ios_steam_author(uint32_t item, uint32_t name, int size)
{ (void)item; char *out = name && size > 0 ? halo_guest_ptr(name, 1) : NULL; if (out) *out = 0; return 0; }

/* The new managed-share POSIX calls are denied until the iOS host has the
 * same path and symlink checks as OpenCE's native implementation. */
static int ios_mcc_preview_read(const char *root, const char *relative, void *buffer, unsigned long capacity)
{ (void)root; (void)relative; (void)buffer; (void)capacity; return 0; }
static int ios_mcc_share_path_safe(const char *path) { (void)path; return 0; }
static int ios_mcc_share_publish(const char *from, const char *to)
{ (void)from; (void)to; return 0; }
static int ios_mcc_share_open(const char *path) { (void)path; return -1; }
static void ios_mcc_share_close(int descriptor) { (void)descriptor; }
static int ios_mcc_share_remove(const char *path, int directory)
{ (void)path; (void)directory; return 0; }
static void ios_upnp_cancel(void) {}

#endif
