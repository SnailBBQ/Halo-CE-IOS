/*
GUEST_MISC.C

Runtime support functions the guest's code generator (clang's Darwin
arm64_32 target) or the platform layer expect, which neither the game nor
musl provides.
*/

#include "guest_host.h"

#include <math.h>
#include <string.h>

/* Darwin's combined sine and cosine, which clang substitutes for
sin()/cos() pairs of the same argument */
struct guest_sincos_result { double sine, cosine; };
struct guest_sincosf_result { float sine, cosine; };

__attribute__((no_builtin)) struct guest_sincos_result __sincos_stret(double x)
{
	struct guest_sincos_result result;

	/* no_builtin: clang would turn sincos(), like a sin() and cos() pair,
	back into a call to this function */
	sincos(x, &result.sine, &result.cosine);
	return result;
}

__attribute__((no_builtin)) struct guest_sincosf_result __sincosf_stret(float x)
{
	struct guest_sincosf_result result;

	sincosf(x, &result.sine, &result.cosine);
	return result;
}

/* Darwin's exp10, which clang substitutes for pow(10, x) (so these must
not be written with pow, which would become calls to themselves) */
__attribute__((no_builtin)) float __exp10f(float x)
{
	return exp10f(x);
}

__attribute__((no_builtin)) double __exp10(double x)
{
	return exp10(x);
}

__attribute__((no_builtin)) void __bzero(void *buffer, size_t size)
{
	memset(buffer, 0, size);
}

/* no_builtin: the loop must not become a call to itself */
__attribute__((no_builtin)) void memset_pattern4(void *buffer, const void *pattern, size_t size)
{
	unsigned char *out = buffer;
	size_t index;

	for (index = 0; index < size; index++)
		out[index] = ((const unsigned char *)pattern)[index & 3];
}

/* no_builtin: the loop must not become a call to itself */
__attribute__((no_builtin)) void memset_pattern8(void *buffer, const void *pattern, size_t size)
{
	unsigned char *out = buffer;
	size_t index;

	for (index = 0; index < size; index++)
		out[index] = ((const unsigned char *)pattern)[index & 7];
}

/* no_builtin: the loop must not become a call to itself */
__attribute__((no_builtin)) void memset_pattern16(void *buffer, const void *pattern, size_t size)
{
	unsigned char *out = buffer;
	size_t index;

	for (index = 0; index < size; index++)
		out[index] = ((const unsigned char *)pattern)[index & 15];
}

void __stack_chk_fail(void)
{
	host_abort("stack smashing detected");
}

/* <execinfo.h>: the guest has no unwinder */
int backtrace(void **frames, int size)
{
	(void)frames;
	(void)size;
	return 0;
}

void backtrace_symbols_fd(void *const *frames, int size, int fd)
{
	(void)frames;
	(void)size;
	(void)fd;
}

#ifdef HALO_IOS_GUEST
/* Keep return values in guest address space; host addresses must not escape. */
extern void host_memory_copy(unsigned int, unsigned int, unsigned int, int);
extern void host_memory_fill(unsigned int, int, unsigned int);
extern void *__real_memcpy(void *, const void *, size_t);
extern void *__real_memmove(void *, const void *, size_t);
extern void *__real_memset(void *, int, size_t);
__attribute__((no_builtin)) void *__wrap_memcpy(void *dst, const void *src, size_t n)
{
    if (n < 256) return __real_memcpy(dst, src, n);
    host_memory_copy((unsigned int)dst, (unsigned int)src, n, 0);
    return dst;
}
__attribute__((no_builtin)) void *__wrap_memmove(void *dst, const void *src, size_t n)
{
    if (n < 256) return __real_memmove(dst, src, n);
    host_memory_copy((unsigned int)dst, (unsigned int)src, n, 1);
    return dst;
}
__attribute__((no_builtin)) void *__wrap_memset(void *dst, int value, size_t n)
{
    if (n < 256) return __real_memset(dst, value, n);
    host_memory_fill((unsigned int)dst, value, n);
    return dst;
}
#endif
