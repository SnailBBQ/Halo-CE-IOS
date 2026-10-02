/* Loopback checks of the iOS socket layer (port/ios/HaloIOS/halo_ios_net.c): Winsock sockaddr
 * layout, Winsock error codes and options, non-blocking connect, select and accept. A fake
 * guest memory stands in for the arena; guest addresses are offsets into it. */
#define _GNU_SOURCE
#include "../../port/ios/HaloIOS/halo_ios_net.c"
#include <ifaddrs.h>
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

    /* a datagram larger than the buffer is WSAEMSGSIZE (10040), not a short datagram */
    memcpy(memory + DATA, "0123456789", 10);
    CHECK(halo_net_sendto(b, DATA, 10, 0, ADDR2, 16) == 10, "send 10 bytes");
    set_i32(LEN2, 16);
    CHECK(halo_net_recvfrom(a, OUT, 4, 0, ADDR, LEN2) == -1 && halo_net_last_error() == 10040, "truncated datagram gives WSAEMSGSIZE, got %d", halo_net_last_error());

    /* select keeps the ready descriptors in the order given, whatever their numbers */
    {
        int s1 = halo_net_socket(2, 2, 17), s2 = halo_net_socket(2, 2, 17), s3 = halo_net_socket(2, 2, 17);
        uint32_t cursor = 0x900;
        put_addr(ADDR, 0x7f000001, 0);
        halo_net_bind(s1, ADDR, 16); halo_net_bind(s2, ADDR, 16); halo_net_bind(s3, ADDR, 16);
        set_i32(LEN, 16); halo_net_getsockname(s2, ADDR2, LEN);
        memcpy(memory + DATA, "z", 1);
        halo_net_sendto(b, DATA, 1, 0, ADDR2, 16);                 /* only s2 has data */
        set_i32(cursor, s3); set_i32(cursor + 4, s2); set_i32(cursor + 8, s1); set_i32(CNT_R, 3);
        CHECK(halo_net_select(cursor, CNT_R, 0, 0, 0, 0, 1, 0, 0) == 1 && get_i32(CNT_R) == 1 && get_i32(cursor) == s2, "select keeps only the ready descriptor");
        /* a descriptor that is not open fails the whole call, as select does */
        set_i32(cursor, 4000); set_i32(CNT_R, 1);
        CHECK(halo_net_select(cursor, CNT_R, 0, 0, 0, 0, 0, 0, 0) == -1 && halo_net_last_error() == 10009, "closed descriptor gives WSAEBADF, got %d", halo_net_last_error());
        /* poll takes descriptors above FD_SETSIZE; fake one by duplicating a socket high up */
        int high = fcntl(s1, F_DUPFD, 1100);
        if (high >= 1024) {
            set_i32(cursor, high); set_i32(CNT_R, 1);
            int ready_now = halo_net_select(cursor, CNT_R, 0, 0, 0, 0, 0, 0, 0);
            CHECK(ready_now == 0, "a descriptor numbered %d does not fail select", high);
            close(high);
        }
        halo_net_close(s1); halo_net_close(s2); halo_net_close(s3);
    }

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

    /* directed broadcast addresses from an interface list (what the search is sent to on iOS) */
    {
        struct sockaddr_in addr[4], mask[4], broad[4];
        struct ifaddrs chain[4];
        uint32_t out[8];
        memset(addr, 0, sizeof addr); memset(mask, 0, sizeof mask); memset(broad, 0, sizeof broad); memset(chain, 0, sizeof chain);
        for (int i = 0; i < 4; i++) { addr[i].sin_family = mask[i].sin_family = broad[i].sin_family = AF_INET; chain[i].ifa_addr = (struct sockaddr *)&addr[i]; chain[i].ifa_netmask = (struct sockaddr *)&mask[i]; chain[i].ifa_next = i < 3 ? &chain[i + 1] : NULL; }
        /* 0: Wi-Fi 192.168.1.20/24 with a broadcast address; 1: loopback; 2: cellular, down; 3: another /16 without one */
        addr[0].sin_addr.s_addr = htonl(0xC0A80114); mask[0].sin_addr.s_addr = htonl(0xFFFFFF00); broad[0].sin_addr.s_addr = htonl(0xC0A801FF);
        chain[0].ifa_flags = IFF_UP | IFF_BROADCAST; chain[0].ifa_broadaddr = (struct sockaddr *)&broad[0];
        addr[1].sin_addr.s_addr = htonl(0x7F000001); chain[1].ifa_flags = IFF_UP | IFF_LOOPBACK;
        addr[2].sin_addr.s_addr = htonl(0x0A000005); chain[2].ifa_flags = IFF_BROADCAST;
        addr[3].sin_addr.s_addr = htonl(0xAC100505); mask[3].sin_addr.s_addr = htonl(0xFFFF0000); chain[3].ifa_flags = IFF_UP | IFF_BROADCAST;
        int n = halo_net_directed_broadcasts(chain, out, 8);
        CHECK(n == 2 && out[0] == htonl(0xC0A801FF) && out[1] == htonl(0xAC10FFFF), "directed broadcasts: %d (%08x %08x)", n, ntohl(out[0]), ntohl(out[1]));
        chain[3].ifa_flags = 0;
        CHECK(halo_net_directed_broadcasts(chain, out, 8) == 1, "an interface that is down is skipped");
        CHECK(halo_net_directed_broadcasts(NULL, out, 8) == 0 && halo_net_directed_broadcasts(chain, out, 0) == 0, "empty list and zero capacity");
    }
    /* the limited broadcast never fails the game outright when loopback is all the machine has */
    {
        int udp = halo_net_socket(2, 2, 17);
        set_i32(OPT, 1);
        halo_net_setsockopt(udp, 0xffff, 0x0020, OPT, 4); /* SO_BROADCAST through Winsock numbers */
        put_addr(ADDR, 0xFFFFFFFF, 5150);
        memcpy(memory + DATA, "x", 1);
        int sent = halo_net_sendto(udp, DATA, 1, 0, ADDR, 16);
        CHECK(sent == 1 || sent == -1, "broadcast send returns a result without crashing (%d)", sent);
        if (sent == -1) CHECK(halo_net_last_error() != 0, "a failed broadcast reports a Winsock error");
        halo_net_close(udp);
    }

    /* names and the local address */
    strcpy((char *)memory + NAME, "127.0.0.1");
    CHECK(halo_net_resolve_ipv4(NAME) == htonl(0x7f000001), "resolve dotted quad");
    strcpy((char *)memory + NAME, "no-such-host.invalid");
    CHECK(halo_net_resolve_ipv4(NAME) == 0, "unresolvable name gives 0");
    { uint32_t local = halo_net_local_ipv4(); CHECK((ntohl(local) >> 24) != 127, "local address is never loopback"); }

    if (!failures) printf("PASS: iOS socket layer: UDP/TCP over loopback, Winsock addresses, errors and options, select, non-blocking connect\n");
    return failures ? 1 : 0;
}
