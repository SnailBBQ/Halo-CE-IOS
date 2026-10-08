/*
GUEST_START.C

Entry point of the guest image. The host maps the image, fills in its
import table and calls __guest_start on the main thread, already running on
a stack in guest memory. This sets up musl (thread pointer, environment,
page size), runs the image's constructors and calls the game's main().
*/

#include "pthread_impl.h"
#include "libc.h"
#include "guest_host.h"
#include "halo_android_abi.h"

#include <stdlib.h>
#include <string.h>

extern char __guest_image_end[];
extern unsigned long long __host_import_table[];
extern const char __host_import_names[];
extern const unsigned int __host_import_count;
extern void (*__guest_init_start[])(void);
extern void (*__guest_init_end[])(void);

void __guest_start(const struct halo_guest_boot *boot);
void __guest_thread_start(unsigned int thread);
unsigned int __guest_thread_attach(void);
void __guest_thread_initialize_main(void);

extern char **__environ;
#ifdef HALO_IOS_GUEST
#ifdef HALO_IOS_FLEX_BASE
/* Non-JB Stage 3 ABI marker. The host refuses to start an arbitrary-base
 * arena unless this exact guest was built with x27 reserved as the arena
 * register and the flexible-base assembly conversion enabled. */
__attribute__((used)) static const char halo_ios_flex_base_guest_marker[] =
    "HALO_IOS_FLEX_BASE_GUEST_V1";
static const char halo_ios_flex_stage3_main_marker[] =
    "HALO_IOS_FLEX_STAGE3_MAIN";
#endif
#endif

__attribute__((section("__TEXT,__guest_header"), used))
const struct halo_guest_header __guest_header =
{
	HALO_GUEST_MAGIC,
	HALO_GUEST_ABI_VERSION,
	(uint32_t)__guest_image_end,
	(uint32_t)__host_import_table,
	(uint32_t)__host_import_names,
	(uint32_t)&__host_import_count,
	(uint32_t)__guest_start,
	(uint32_t)__guest_thread_start,
	(uint32_t)__guest_thread_attach,
	(uint32_t)__guest_init_start,
	(uint32_t)__guest_init_end,
};

/* the game's entry point (source/main/main.c) */
extern int main(int argc, char **argv);

void __guest_start(const struct halo_guest_boot *boot)
{
	void (**constructor)(void);
	int result;

#ifdef HALO_IOS_GUEST
#ifdef HALO_IOS_FLEX_BASE
	host_log(4, halo_ios_flex_base_guest_marker);
#endif
#endif
	libc.page_size = boot->page_size;
	libc.auxv = (size_t *)"\0\0\0\0\0\0\0";
	__environ = (char **)boot->environment;
	__guest_thread_initialize_main();

	for (constructor = __guest_init_start; constructor < __guest_init_end; constructor++)
		(*constructor)();

#ifdef HALO_IOS_GUEST
#ifdef HALO_IOS_FLEX_BASE
	host_log(4, halo_ios_flex_stage3_main_marker);
#endif
#endif
	result = main((int)boot->argc, (char **)boot->argv);
	exit(result);
}
