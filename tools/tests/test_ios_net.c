/* Loopback checks of the iOS socket layer (port/ios/HaloIOS/halo_ios_net.c): Winsock sockaddr
 * layout, Winsock error codes and options, non-blocking connect, select and accept. A fake
 * guest memory stands in for the arena; guest addresses are offsets into it. */
#define _GNU_SOURCE
#include "../../port/ios/HaloIOS/halo_ios_net.c"
#include <stdio.h>
#include <stdlib.h>

static uint8_t memory[1 << 16];
static void *resolver(uint32_t va, size_t size)
{
    if (va == 0 || (size_t)va + size > sizeof(memory)) return NULL;
    return memory + va;
}

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

enum { ADDR = 0x100, ADDR2 = 0x140, LEN = 0x180, LEN2 = 0x184, DATA = 0x200, OUT = 0x400, LIST_R = 0x600, CNT_R = 0x640,
       LIST_W = 0x660, CNT_W = 0x6a0, OPT = 0x700, OPTLEN = 0x710, NAME = 0x800 };

static void put_addr(uint32_t at, uint32_t ip_host_order, uint16_t port_host_order)
{
    memset(memory + at, 0, 16);
    memory[at] = 2;                                   /* Winsock: 16-bit family, little endian */
    uint16_t port = htons(port_host_order); memcpy(memory + at + 2, &port, 2);
    uint32_t ip = htonl(ip_host_order);     memcpy(memory + at + 4, &ip, 4);
}
static uint16_t addr_port(uint32_t at) { uint16_t p; memcpy(&p, memory + at + 2, 2); return ntohs(p); }
static uint32_t addr_ip(uint32_t at)   { uint32_t i; memcpy(&i, memory + at + 4, 4); return ntohl(i); }
static void set_i32(uint32_t at, int32_t v) { memcpy(memory + at, &v, 4); }
static int32_t get_i32(uint32_t at) { int32_t v; memcpy(&v, memory + at, 4); return v; }

int main(void)
{
    halo_ios_net_set_resolver(resolver);

    /* UDP echo across loopback, through the Winsock address layout */
    int a = halo_net_socket(2, 2, 17), b = halo_net_socket(2, 2, 17);
    CHECK(a >= 0 && b >= 0, "udp sockets %d %d", a, b);
    put_addr(ADDR, 0x7f000001, 0);
    CHECK(halo_net_bind(a, ADDR, 16) == 0, "bind a (error %d)", halo_net_last_error());
    set_i32(LEN, 16);
    CHECK(halo_net_getsockname(a, ADDR2, LEN) == 0 && get_i32(LEN) == 16, "getsockname");
    CHECK(memory[ADDR2] == 2 && memory[ADDR2 + 1] == 0, "family is 16-bit 2");
    uint16_t port_a = addr_port(ADDR2);
    CHECK(port_a != 0 && addr_ip(ADDR2) == 0x7f000001, "bound to %08x:%u", addr_ip(ADDR2), port_a);
    memcpy(memory + DATA, "halo", 4);
    CHECK(halo_net_sendto(b, DATA, 4, 0, ADDR2, 16) == 4, "sendto (error %d)", halo_net_last_error());
    set_i32(LEN2, 16);
    CHECK(halo_net_recvfrom(a, OUT, 64, 0, ADDR, LEN2) == 4, "recvfrom (error %d)", halo_net_last_error());
    CHECK(!memcmp(memory + OUT, "halo", 4) && get_i32(LEN2) == 16 && memory[ADDR] == 2 && addr_ip(ADDR) == 0x7f000001,
          "source address translated");

    /* nothing waiting: a non-blocking receive is WSAEWOULDBLOCK, select reports nothing ready */
    CHECK(halo_net_set_nonblocking(a, 1) == 0, "nonblocking");
    CHECK(halo_net_recv(a, OUT, 16, 0) == -1 && halo_net_last_error() == 10035, "empty recv gives WSAEWOULDBLOCK, got %d", halo_net_last_error());
    set_i32(LIST_R, a); set_i32(CNT_R, 1);
    CHECK(halo_net_select(LIST_R, CNT_R, 0, 0, 0, 0, 0, 20000, 0) == 0 && get_i32(CNT_R) == 0, "select with nothing ready");
    CHECK(halo_net_sendto(b, DATA, 4, 0, ADDR2, 16) == 4, "second datagram");
    set_i32(LIST_R, a); set_i32(CNT_R, 1);
    CHECK(halo_net_select(LIST_R, CNT_R, 0, 0, 0, 0, 1, 0, 0) == 1 && get_i32(CNT_R) == 1 && get_i32(LIST_R) == a, "select reports a readable");
    uint32_t available = 0; (void)available;
    CHECK(halo_net_bytes_available(a, OPT) == 0 && get_i32(OPT) == 4, "bytes available %d", get_i32(OPT));
    CHECK(halo_net_recv(a, OUT, 16, 2 /* MSG_PEEK */) == 4 && halo_net_recv(a, OUT, 16, 0) == 4, "peek then read");

    /* TCP: non-blocking connect is WSAEWOULDBLOCK, then writeable; accept reports the peer */
    int listener = halo_net_socket(2, 1, 6), client = halo_net_socket(2, 1, 6);
    put_addr(ADDR, 0x7f000001, 0);
    CHECK(halo_net_bind(listener, ADDR, 16) == 0 && halo_net_listen(listener, 4) == 0, "listen");
    set_i32(LEN, 16);
    CHECK(halo_net_getsockname(listener, ADDR2, LEN) == 0, "listener name");
    CHECK(halo_net_set_nonblocking(client, 1) == 0 && halo_net_set_nodelay(client) == 0, "client options");
    int rc = halo_net_connect(client, ADDR2, 16);
    CHECK(rc == 0 || halo_net_last_error() == 10035, "connect gives 0 or WSAEWOULDBLOCK, got rc %d err %d", rc, halo_net_last_error());
    set_i32(LIST_W, client); set_i32(CNT_W, 1);
    CHECK(halo_net_select(0, 0, LIST_W, CNT_W, 0, 0, 2, 0, 0) == 1 && get_i32(CNT_W) == 1, "connect completes (writeable)");
    set_i32(LEN, 16);
    int server = halo_net_accept(listener, ADDR, LEN);
    CHECK(server >= 0 && get_i32(LEN) == 16 && addr_ip(ADDR) == 0x7f000001 && memory[ADDR] == 2, "accept (error %d)", halo_net_last_error());
    memcpy(memory + DATA, "ping!", 5);
    CHECK(halo_net_send(client, DATA, 5, 0) == 5, "tcp send");
    set_i32(LIST_R, server); set_i32(CNT_R, 1);
    CHECK(halo_net_select(LIST_R, CNT_R, 0, 0, 0, 0, 1, 0, 0) == 1, "tcp readable");
    CHECK(halo_net_recv(server, OUT, 16, 0) == 5 && !memcmp(memory + OUT, "ping!", 5), "tcp recv");
    set_i32(LEN, 16);
    CHECK(halo_net_getpeername(client, ADDR, LEN) == 0 && addr_port(ADDR) == addr_port(ADDR2), "peer name");

    /* connection refused on a closed port (blocking connect) */
    int refused = halo_net_socket(2, 1, 6);
    halo_net_close(listener);
    CHECK(halo_net_connect(refused, ADDR2, 16) == -1 && halo_net_last_error() == 10061, "refused gives WSAECONNREFUSED, got %d", halo_net_last_error());

    /* a failed connect shows in the error set, not the writeable set */
    int refused2 = halo_net_socket(2, 1, 6);
    CHECK(halo_net_set_nonblocking(refused2, 1) == 0, "nb");
    halo_net_connect(refused2, ADDR2, 16);
    set_i32(LIST_W, refused2); set_i32(CNT_W, 1);
    int ready = halo_net_select(0, 0, LIST_W, CNT_W, 0, 0, 2, 0, 0);
    CHECK(get_i32(CNT_W) == 0 && ready <= 0, "failed connect must not look writeable (ready %d count %d)", ready, get_i32(CNT_W));

    /* Winsock options and errors */
    set_i32(OPT, 1);
    CHECK(halo_net_setsockopt(a, 0xffff, 0x0004, OPT, 4) == 0, "SO_REUSEADDR through Winsock numbers");
    CHECK(halo_net_setsockopt(a, 0xffff, 0x7777, OPT, 4) == 0 && halo_net_last_error() == 0, "unknown Winsock options are ignored");
    set_i32(OPTLEN, 4);
    CHECK(halo_net_getsockopt(a, 0xffff, 0x1008, OPT, OPTLEN) == 0 && get_i32(OPT) == 2, "SO_TYPE is SOCK_DGRAM, got %d", get_i32(OPT));
    CHECK(halo_net_getsockopt(a, 0xffff, 0x7777, OPT, OPTLEN) == -1 && halo_net_last_error() == 10042, "unknown getsockopt gives WSAENOPROTOOPT");
    memset(memory + ADDR, 0, 16); memory[ADDR] = 23; /* AF_INET6 in Winsock */
    CHECK(halo_net_bind(a, ADDR, 16) == -1 && halo_net_last_error() == 10047, "AF_INET6 gives WSAEAFNOSUPPORT, got %d", halo_net_last_error());
    CHECK(halo_net_bind(a, 0xfffffff0u, 16) == -1 && halo_net_last_error() == 10014, "bad guest pointer gives WSAEFAULT");
    CHECK(halo_net_close(9999) == -1 && halo_net_last_error() == 10009, "bad descriptor gives WSAEBADF");

    /* names and the local address */
    strcpy((char *)memory + NAME, "127.0.0.1");
    CHECK(halo_net_resolve_ipv4(NAME) == htonl(0x7f000001), "resolve dotted quad");
    strcpy((char *)memory + NAME, "no-such-host.invalid");
    CHECK(halo_net_resolve_ipv4(NAME) == 0, "unresolvable name gives 0");
    (void)halo_net_local_ipv4();

    if (!failures) printf("PASS: iOS socket layer: UDP/TCP over loopback, Winsock addresses, errors and options, select, non-blocking connect\n");
    return failures ? 1 : 0;
}
