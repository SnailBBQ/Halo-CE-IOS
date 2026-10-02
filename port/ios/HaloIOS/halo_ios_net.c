#include "halo_ios_net.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>

/* Winsock error codes (winsockx.h) */
#define WSAEINTR 10004
#define WSAEBADF 10009
#define WSAEACCES 10013
#define WSAEFAULT 10014
#define WSAEINVAL 10022
#define WSAEMFILE 10024
#define WSAEWOULDBLOCK 10035
#define WSAEINPROGRESS 10036
#define WSAEALREADY 10037
#define WSAENOTSOCK 10038
#define WSAEDESTADDRREQ 10039
#define WSAEMSGSIZE 10040
#define WSAEPROTOTYPE 10041
#define WSAENOPROTOOPT 10042
#define WSAEPROTONOSUPPORT 10043
#define WSAEOPNOTSUPP 10045
#define WSAEAFNOSUPPORT 10047
#define WSAEADDRINUSE 10048
#define WSAEADDRNOTAVAIL 10049
#define WSAENETDOWN 10050
#define WSAENETUNREACH 10051
#define WSAECONNABORTED 10053
#define WSAECONNRESET 10054
#define WSAENOBUFS 10055
#define WSAEISCONN 10056
#define WSAENOTCONN 10057
#define WSAETIMEDOUT 10060
#define WSAECONNREFUSED 10061
#define WSAEHOSTUNREACH 10065

/* Winsock option values (winsockx.h) */
#define WINSOCK_SOL_SOCKET 0xffff
#define WINSOCK_SO_REUSEADDR 0x0004
#define WINSOCK_SO_KEEPALIVE 0x0008
#define WINSOCK_SO_BROADCAST 0x0020
#define WINSOCK_SO_LINGER 0x0080
#define WINSOCK_SO_SNDBUF 0x1001
#define WINSOCK_SO_RCVBUF 0x1002
#define WINSOCK_SO_ERROR 0x1007
#define WINSOCK_SO_TYPE 0x1008
#define WINSOCK_IP_TTL 7
#define WINSOCK_IP_TOS 8

#define GUEST_SOCKADDR_IN_SIZE 16
#define GUEST_AF_INET 2

static halo_net_resolver g_resolver;
static __thread int32_t g_last_error;

void halo_ios_net_set_resolver(halo_net_resolver resolver) { g_resolver = resolver; }

static void *resolve(uint32_t va, size_t size)
{
    return (g_resolver && va) ? g_resolver(va, size) : NULL;
}

static int fail(void)
{
    switch (errno)
    {
    case EINTR: g_last_error = WSAEINTR; break;
    case EBADF: g_last_error = WSAEBADF; break;
    case EACCES: case EPERM: g_last_error = WSAEACCES; break;
    case EFAULT: g_last_error = WSAEFAULT; break;
    case EMFILE: case ENFILE: g_last_error = WSAEMFILE; break;
    case EAGAIN: g_last_error = WSAEWOULDBLOCK; break;
    case EINPROGRESS: g_last_error = WSAEINPROGRESS; break;
    case EALREADY: g_last_error = WSAEALREADY; break;
    case ENOTSOCK: g_last_error = WSAENOTSOCK; break;
    case EDESTADDRREQ: g_last_error = WSAEDESTADDRREQ; break;
    case EMSGSIZE: g_last_error = WSAEMSGSIZE; break;
    case EPROTOTYPE: g_last_error = WSAEPROTOTYPE; break;
    case ENOPROTOOPT: g_last_error = WSAENOPROTOOPT; break;
    case EPROTONOSUPPORT: g_last_error = WSAEPROTONOSUPPORT; break;
    case EOPNOTSUPP: g_last_error = WSAEOPNOTSUPP; break;
    case EAFNOSUPPORT: g_last_error = WSAEAFNOSUPPORT; break;
    case EADDRINUSE: g_last_error = WSAEADDRINUSE; break;
    case EADDRNOTAVAIL: g_last_error = WSAEADDRNOTAVAIL; break;
    case ENETDOWN: g_last_error = WSAENETDOWN; break;
    case ENETUNREACH: g_last_error = WSAENETUNREACH; break;
    case ECONNABORTED: g_last_error = WSAECONNABORTED; break;
    case ECONNRESET: g_last_error = WSAECONNRESET; break;
    case ENOBUFS: case ENOMEM: g_last_error = WSAENOBUFS; break;
    case EISCONN: g_last_error = WSAEISCONN; break;
    case ENOTCONN: g_last_error = WSAENOTCONN; break;
    case ETIMEDOUT: g_last_error = WSAETIMEDOUT; break;
    case ECONNREFUSED: g_last_error = WSAECONNREFUSED; break;
    case EHOSTUNREACH: g_last_error = WSAEHOSTUNREACH; break;
    default: g_last_error = WSAEINVAL; break;
    }
    return -1;
}

static int bad_pointer(void)
{
    errno = EFAULT;
    return fail();
}

static int succeed(int result)
{
    if (result < 0)
        return fail();
    g_last_error = 0;
    return result;
}

int32_t halo_net_last_error(void) { return g_last_error; }

/* ---------- addresses: Winsock sockaddr_in <-> BSD sockaddr_in */

static int address_to_host(const uint8_t *guest, int32_t length, struct sockaddr_in *host)
{
    if (length < 8)
    {
        errno = EINVAL;
        return -1;
    }
    if ((guest[0] | (guest[1] << 8)) != GUEST_AF_INET)
    {
        errno = EAFNOSUPPORT;
        return -1;
    }
    memset(host, 0, sizeof(*host));
#ifdef __APPLE__
    host->sin_len = sizeof(*host);
#endif
    host->sin_family = AF_INET;
    memcpy(&host->sin_port, guest + 2, 2);
    memcpy(&host->sin_addr, guest + 4, 4);
    return 0;
}

static void address_to_guest(const struct sockaddr_storage *host, uint8_t out[GUEST_SOCKADDR_IN_SIZE])
{
    memset(out, 0, GUEST_SOCKADDR_IN_SIZE);
    if (host->ss_family == AF_INET)
    {
        const struct sockaddr_in *in = (const struct sockaddr_in *)host;

        out[0] = GUEST_AF_INET;
        memcpy(out + 2, &in->sin_port, 2);
        memcpy(out + 4, &in->sin_addr, 4);
    }
}

/* writes a returned address back through the guest's address/length pair */
static int store_address(uint32_t address_va, uint32_t length_va, const struct sockaddr_storage *host)
{
    int32_t *length;
    uint8_t *guest;
    uint8_t translated[GUEST_SOCKADDR_IN_SIZE];
    int32_t capacity;

    if (!address_va || !length_va)
        return 0;
    length = resolve(length_va, sizeof(*length));
    if (!length)
        return -1;
    capacity = *length;
    if (capacity < 0)
        capacity = 0;
    guest = resolve(address_va, (size_t)(capacity > 0 ? capacity : 1));
    if (!guest)
        return -1;
    address_to_guest(host, translated);
    memcpy(guest, translated, (size_t)(capacity < GUEST_SOCKADDR_IN_SIZE ? capacity : GUEST_SOCKADDR_IN_SIZE));
    *length = GUEST_SOCKADDR_IN_SIZE;
    return 0;
}

/* ---------- sockets */

static void quiet_socket(int descriptor)
{
    int one = 1;

    fcntl(descriptor, F_SETFD, FD_CLOEXEC);
#ifdef SO_NOSIGPIPE
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#else
    (void)one;
#endif
}

int32_t halo_net_socket(int32_t family, int32_t type, int32_t protocol)
{
    int descriptor = socket(family, type, protocol);

    if (descriptor >= 0)
        quiet_socket(descriptor);
    return succeed(descriptor);
}

int32_t halo_net_close(int32_t socket_descriptor)
{
    return succeed(close(socket_descriptor));
}

int32_t halo_net_bind(int32_t s, uint32_t address, int32_t length)
{
    const uint8_t *guest = resolve(address, (size_t)(length > 0 ? length : 1));
    struct sockaddr_in host;

    if (!guest)
        return bad_pointer();
    if (address_to_host(guest, length, &host) != 0)
        return fail();
    return succeed(bind(s, (struct sockaddr *)&host, sizeof(host)));
}

int32_t halo_net_connect(int32_t s, uint32_t address, int32_t length)
{
    const uint8_t *guest = resolve(address, (size_t)(length > 0 ? length : 1));
    struct sockaddr_in host;
    int result;

    if (!guest)
        return bad_pointer();
    if (address_to_host(guest, length, &host) != 0)
        return fail();
    result = connect(s, (struct sockaddr *)&host, sizeof(host));
    /* A non-blocking connect under way is WSAEWOULDBLOCK in Winsock, which is
       what the game waits on before it selects for the socket to be writeable. */
    if (result < 0 && errno == EINPROGRESS)
    {
        g_last_error = WSAEWOULDBLOCK;
        return -1;
    }
    return succeed(result);
}

int32_t halo_net_listen(int32_t s, int32_t backlog)
{
    return succeed(listen(s, backlog));
}

int32_t halo_net_accept(int32_t s, uint32_t address, uint32_t length)
{
    struct sockaddr_storage host;
    socklen_t host_length = sizeof(host);
    int descriptor = accept(s, (struct sockaddr *)&host, &host_length);

    if (descriptor < 0)
        return fail();
    quiet_socket(descriptor);
    if (store_address(address, length, &host) != 0)
    {
        close(descriptor);
        return bad_pointer();
    }
    return succeed(descriptor);
}

static int send_flags(int32_t flags)
{
    int result = flags & 7; /* MSG_OOB, MSG_PEEK and MSG_DONTROUTE are shared */
#ifdef MSG_NOSIGNAL
    result |= MSG_NOSIGNAL;
#endif
    return result;
}

int32_t halo_net_send(int32_t s, uint32_t buffer, int32_t length, int32_t flags)
{
    const void *data = resolve(buffer, (size_t)(length > 0 ? length : 1));

    if (!data || length < 0)
        return bad_pointer();
    return succeed((int)send(s, data, (size_t)length, send_flags(flags)));
}

int32_t halo_net_sendto(int32_t s, uint32_t buffer, int32_t length, int32_t flags, uint32_t address, int32_t address_length)
{
    const void *data = resolve(buffer, (size_t)(length > 0 ? length : 1));
    const uint8_t *guest = resolve(address, (size_t)(address_length > 0 ? address_length : 1));
    struct sockaddr_in host;

    if (!data || length < 0 || !guest)
        return bad_pointer();
    if (address_to_host(guest, address_length, &host) != 0)
        return fail();
    return succeed((int)sendto(s, data, (size_t)length, send_flags(flags), (struct sockaddr *)&host, sizeof(host)));
}

int32_t halo_net_recv(int32_t s, uint32_t buffer, int32_t length, int32_t flags)
{
    void *data = resolve(buffer, (size_t)(length > 0 ? length : 1));

    if (!data || length < 0)
        return bad_pointer();
    return succeed((int)recv(s, data, (size_t)length, flags & 7));
}

int32_t halo_net_recvfrom(int32_t s, uint32_t buffer, int32_t length, int32_t flags, uint32_t address, uint32_t address_length)
{
    void *data = resolve(buffer, (size_t)(length > 0 ? length : 1));
    struct sockaddr_storage host;
    socklen_t host_length = sizeof(host);
    int result;

    if (!data || length < 0)
        return bad_pointer();
    memset(&host, 0, sizeof(host));
    result = (int)recvfrom(s, data, (size_t)length, flags & 7, (struct sockaddr *)&host, &host_length);
    if (result < 0)
        return fail();
    if (store_address(address, address_length, &host) != 0)
        return bad_pointer();
    return succeed(result);
}

int32_t halo_net_shutdown(int32_t s, int32_t how)
{
    return succeed(shutdown(s, how));
}

int32_t halo_net_set_nonblocking(int32_t s, int32_t nonblocking)
{
    int flags = fcntl(s, F_GETFL);

    if (flags < 0)
        return fail();
    flags = nonblocking ? (flags | O_NONBLOCK) : (flags & ~O_NONBLOCK);
    return succeed(fcntl(s, F_SETFL, flags));
}

int32_t halo_net_set_nodelay(int32_t s)
{
    int one = 1;

    return succeed(setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one)));
}

int32_t halo_net_bytes_available(int32_t s, uint32_t count)
{
    uint32_t *out = resolve(count, sizeof(*out));
    int available = 0;
    int result;

    if (!out)
        return bad_pointer();
    result = ioctl(s, FIONREAD, &available);
    if (result >= 0)
        *out = (uint32_t)available;
    return succeed(result);
}

static int translate_option(int32_t level, int32_t name, int *host_level, int *host_name)
{
    if (level == WINSOCK_SOL_SOCKET)
    {
        *host_level = SOL_SOCKET;
        switch (name)
        {
        case WINSOCK_SO_REUSEADDR: *host_name = SO_REUSEADDR; return 0;
        case WINSOCK_SO_KEEPALIVE: *host_name = SO_KEEPALIVE; return 0;
        case WINSOCK_SO_BROADCAST: *host_name = SO_BROADCAST; return 0;
        case WINSOCK_SO_LINGER: *host_name = SO_LINGER; return 0;
        case WINSOCK_SO_SNDBUF: *host_name = SO_SNDBUF; return 0;
        case WINSOCK_SO_RCVBUF: *host_name = SO_RCVBUF; return 0;
        case WINSOCK_SO_ERROR: *host_name = SO_ERROR; return 0;
        case WINSOCK_SO_TYPE: *host_name = SO_TYPE; return 0;
        default: return -1;
        }
    }
    *host_level = level;
    *host_name = name;
    if (level == IPPROTO_IP)
    {
        /* Winsock numbers IP_TTL and IP_TOS differently from BSD; the multicast options match */
        if (name == WINSOCK_IP_TTL) *host_name = IP_TTL;
        else if (name == WINSOCK_IP_TOS) *host_name = IP_TOS;
    }
    return 0;
}

int32_t halo_net_setsockopt(int32_t s, int32_t level, int32_t name, uint32_t value, int32_t length)
{
    const void *data = resolve(value, (size_t)(length > 0 ? length : 1));
    int host_level, host_name;

    if (!data || length < 0)
        return bad_pointer();
    if (translate_option(level, name, &host_level, &host_name) != 0)
    {
        /* Xbox-only options such as SO_ENCRYPT have nothing to do here */
        g_last_error = 0;
        return 0;
    }
    return succeed(setsockopt(s, host_level, host_name, data, (socklen_t)length));
}

int32_t halo_net_getsockopt(int32_t s, int32_t level, int32_t name, uint32_t value, uint32_t length_va)
{
    int32_t *length = resolve(length_va, sizeof(*length));
    void *data;
    int host_level, host_name;
    socklen_t host_length;
    int result;

    if (!length || *length < 0)
        return bad_pointer();
    data = resolve(value, (size_t)(*length > 0 ? *length : 1));
    if (!data)
        return bad_pointer();
    if (translate_option(level, name, &host_level, &host_name) != 0)
    {
        g_last_error = WSAENOPROTOOPT;
        return -1;
    }
    host_length = (socklen_t)*length;
    result = getsockopt(s, host_level, host_name, data, &host_length);
    *length = (int32_t)host_length;
    return succeed(result);
}

int32_t halo_net_getsockname(int32_t s, uint32_t address, uint32_t length)
{
    struct sockaddr_storage host;
    socklen_t host_length = sizeof(host);

    memset(&host, 0, sizeof(host));
    if (getsockname(s, (struct sockaddr *)&host, &host_length) < 0)
        return fail();
    if (store_address(address, length, &host) != 0)
        return bad_pointer();
    return succeed(0);
}

int32_t halo_net_getpeername(int32_t s, uint32_t address, uint32_t length)
{
    struct sockaddr_storage host;
    socklen_t host_length = sizeof(host);

    memset(&host, 0, sizeof(host));
    if (getpeername(s, (struct sockaddr *)&host, &host_length) < 0)
        return fail();
    if (store_address(address, length, &host) != 0)
        return bad_pointer();
    return succeed(0);
}

/* ---------- select over explicit descriptor lists */

static int fill_set(fd_set *set, const int32_t *descriptors, int count, int maximum)
{
    FD_ZERO(set);
    for (int index = 0; index < count; index++)
    {
        if (descriptors[index] >= 0 && descriptors[index] < FD_SETSIZE)
        {
            FD_SET(descriptors[index], set);
            if (descriptors[index] > maximum)
                maximum = descriptors[index];
        }
    }
    return maximum;
}

static void keep_ready(fd_set *set, int32_t *descriptors, int32_t *count)
{
    int kept = 0;

    for (int index = 0; index < *count; index++)
        if (descriptors[index] >= 0 && descriptors[index] < FD_SETSIZE && FD_ISSET(descriptors[index], set))
            descriptors[kept++] = descriptors[index];
    *count = kept;
}

/* one guest list: its descriptor array and its count, both resolved */
struct guest_list
{
    int32_t *descriptors;
    int32_t *count;
};

static int resolve_list(struct guest_list *list, uint32_t array_va, uint32_t count_va)
{
    list->descriptors = NULL;
    list->count = NULL;
    if (!array_va || !count_va)
        return 0;
    list->count = resolve(count_va, sizeof(int32_t));
    if (!list->count || *list->count < 0 || *list->count > FD_SETSIZE)
        return -1;
    list->descriptors = resolve(array_va, (size_t)(*list->count > 0 ? *list->count : 1) * sizeof(int32_t));
    return list->descriptors ? 0 : -1;
}

int32_t halo_net_select(uint32_t read_va, uint32_t read_count_va, uint32_t write_va, uint32_t write_count_va,
                        uint32_t error_va, uint32_t error_count_va, int32_t seconds, int32_t microseconds, int32_t infinite)
{
    struct guest_list read, write, error;
    fd_set read_set, write_set, error_set;
    struct timeval timeout;
    int maximum = -1;
    int result;

    if (resolve_list(&read, read_va, read_count_va) || resolve_list(&write, write_va, write_count_va) ||
        resolve_list(&error, error_va, error_count_va))
        return bad_pointer();
    maximum = fill_set(&read_set, read.descriptors, read.descriptors ? *read.count : 0, maximum);
    maximum = fill_set(&write_set, write.descriptors, write.descriptors ? *write.count : 0, maximum);
    maximum = fill_set(&error_set, error.descriptors, error.descriptors ? *error.count : 0, maximum);
    timeout.tv_sec = seconds;
    timeout.tv_usec = microseconds;
    result = select(maximum + 1, read.descriptors ? &read_set : NULL, write.descriptors ? &write_set : NULL,
                    error.descriptors ? &error_set : NULL, infinite ? NULL : &timeout);
    if (result < 0)
        return fail();
    if (write.descriptors)
    {
        /* Winsock reports a socket writeable once its connect has succeeded; one whose
           connect failed is in the error set. POSIX reports it writeable with the failure
           in SO_ERROR, so move those out of the writeable set. */
        for (int index = 0; index < *write.count; index++)
        {
            int descriptor = write.descriptors[index];
            int pending = 0;
            socklen_t length = sizeof(pending);

            if (descriptor >= 0 && descriptor < FD_SETSIZE && FD_ISSET(descriptor, &write_set) &&
                getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &pending, &length) == 0 && pending)
            {
                FD_CLR(descriptor, &write_set);
                result--;
                errno = pending;
                fail();
            }
        }
    }
    if (read.descriptors)
        keep_ready(&read_set, read.descriptors, read.count);
    if (write.descriptors)
        keep_ready(&write_set, write.descriptors, write.count);
    if (error.descriptors)
        keep_ready(&error_set, error.descriptors, error.count);
    /* like Winsock, a select with nothing ready leaves the last error as it was */
    if (result > 0)
        g_last_error = 0;
    return result;
}

/* ---------- addresses of this machine and of names */

uint32_t halo_net_local_ipv4(void)
{
    struct ifaddrs *addresses, *entry;
    uint32_t wifi = 0, other = 0;

    if (getifaddrs(&addresses) != 0)
        return 0;
    for (entry = addresses; entry; entry = entry->ifa_next)
    {
        if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET || !(entry->ifa_flags & IFF_UP) ||
            (entry->ifa_flags & IFF_LOOPBACK))
            continue;
        uint32_t address = ((struct sockaddr_in *)entry->ifa_addr)->sin_addr.s_addr;

        if (!strcmp(entry->ifa_name, "en0"))
            wifi = address;
        else if (!other)
            other = address;
    }
    freeifaddrs(addresses);
    return wifi ? wifi : other;
}

uint32_t halo_net_resolve_ipv4(uint32_t host_va)
{
    const char *host = resolve(host_va, 1);
    struct addrinfo hints, *results;
    uint32_t address = 0;

    if (!host)
        return 0;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    if (getaddrinfo(host, NULL, &hints, &results) != 0)
        return 0;
    if (results && results->ai_addr && results->ai_addr->sa_family == AF_INET)
        address = ((struct sockaddr_in *)results->ai_addr)->sin_addr.s_addr;
    freeaddrinfo(results);
    return address;
}
