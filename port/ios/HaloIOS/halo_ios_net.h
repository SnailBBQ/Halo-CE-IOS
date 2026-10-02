#ifndef HALO_IOS_NET_H
#define HALO_IOS_NET_H

/*
 * BSD sockets for the iOS-hosted guest (system link and internet play).
 *
 * The guest speaks Winsock: a 16-byte sockaddr_in with a 16-bit family and
 * Winsock error codes. iOS speaks BSD (sin_len + 8-bit family). Every entry
 * point takes guest virtual addresses, resolves them through the callback set
 * with halo_ios_net_set_resolver, and translates addresses, options and errors,
 * exactly as port/linux/src/posix_net.c does for Linux and Android.
 */

#include <stddef.h>
#include <stdint.h>

typedef void *(*halo_net_resolver)(uint32_t guest_va, size_t size);
void halo_ios_net_set_resolver(halo_net_resolver resolver);

int32_t halo_net_last_error(void);
int32_t halo_net_socket(int32_t family, int32_t type, int32_t protocol);
int32_t halo_net_close(int32_t socket);
int32_t halo_net_bind(int32_t socket, uint32_t address, int32_t length);
int32_t halo_net_connect(int32_t socket, uint32_t address, int32_t length);
int32_t halo_net_listen(int32_t socket, int32_t backlog);
int32_t halo_net_accept(int32_t socket, uint32_t address, uint32_t length);
int32_t halo_net_send(int32_t socket, uint32_t buffer, int32_t length, int32_t flags);
int32_t halo_net_sendto(int32_t socket, uint32_t buffer, int32_t length, int32_t flags, uint32_t address, int32_t address_length);
int32_t halo_net_recv(int32_t socket, uint32_t buffer, int32_t length, int32_t flags);
int32_t halo_net_recvfrom(int32_t socket, uint32_t buffer, int32_t length, int32_t flags, uint32_t address, uint32_t address_length);
int32_t halo_net_shutdown(int32_t socket, int32_t how);
int32_t halo_net_set_nonblocking(int32_t socket, int32_t nonblocking);
int32_t halo_net_bytes_available(int32_t socket, uint32_t count);
int32_t halo_net_set_nodelay(int32_t socket);
int32_t halo_net_setsockopt(int32_t socket, int32_t level, int32_t name, uint32_t value, int32_t length);
int32_t halo_net_getsockopt(int32_t socket, int32_t level, int32_t name, uint32_t value, uint32_t length);
int32_t halo_net_getsockname(int32_t socket, uint32_t address, uint32_t length);
int32_t halo_net_getpeername(int32_t socket, uint32_t address, uint32_t length);
int32_t halo_net_select(uint32_t read, uint32_t read_count, uint32_t write, uint32_t write_count,
                        uint32_t error, uint32_t error_count, int32_t seconds, int32_t microseconds, int32_t infinite);
uint32_t halo_net_local_ipv4(void);
uint32_t halo_net_resolve_ipv4(uint32_t host);

#endif
