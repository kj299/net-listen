/*
 * net-listen (C)
 *
 * Listens on a TCP and a UDP port simultaneously and prints every byte it
 * receives, tagged with the peer that sent it. Both sockets share one event
 * loop via select(), so neither protocol is starved while the other is idle.
 *
 * Portable across Linux (Ubuntu, Red Hat) and Windows: the platform-specific
 * socket details are isolated in the shim block below, and the rest of the
 * program is written against that shim.
 *
 * Usage:   c_listener <tcp-port> <udp-port>
 * Stop:    Ctrl+C (graceful shutdown)
 *
 * Build (Linux):   gcc c_listener.c -o c_listener
 * Build (MinGW):   gcc c_listener.c -o c_listener.exe -lws2_32
 * Build (MSVC):    cl c_listener.c ws2_32.lib
 * Or just run `make` / `mingw32-make`, which detects the platform for you.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>   /* sig_atomic_t — standard C, available on every target */

/* ---- platform shim ---------------------------------------------------- */
#if defined(_WIN32) || defined(_WIN64)
  #define WIN32_LEAN_AND_MEAN
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <windows.h>
  #ifdef _MSC_VER
    #pragma comment(lib, "ws2_32.lib")
  #endif
  typedef SOCKET sock_t;
  #define BAD_SOCKET    INVALID_SOCKET
  #define SOCK_ERR      SOCKET_ERROR
  #define close_sock(s) closesocket(s)
#else
  #include <sys/socket.h>
  #include <sys/select.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #include <unistd.h>
  #include <errno.h>
  typedef int sock_t;
  #define BAD_SOCKET    (-1)
  #define SOCK_ERR      (-1)
  #define close_sock(s) close(s)
#endif
/* ----------------------------------------------------------------------- */

#define BUF_SIZE       1024
#define LISTEN_BACKLOG 16

static volatile sig_atomic_t g_stop = 0;

#if defined(_WIN32) || defined(_WIN64)
static BOOL WINAPI on_console_event(DWORD event) {
    (void)event;
    g_stop = 1;
    return TRUE;
}
#else
static void on_signal(int sig) {
    (void)sig;
    g_stop = 1;
}
#endif

/* Report the last socket error using the platform's native facility. */
static void log_sock_error(const char *where) {
#if defined(_WIN32) || defined(_WIN64)
    int err = WSAGetLastError();
    char *msg = NULL;
    DWORD n = FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, (DWORD)err, 0, (LPSTR)&msg, 0, NULL);
    if (n && msg) {
        fprintf(stderr, "[%s] error %d: %s", where, err, msg);
    } else {
        fprintf(stderr, "[%s] error %d\n", where, err);
    }
    if (msg) LocalFree(msg);
#else
    fprintf(stderr, "[%s] error %d: %s\n", where, errno, strerror(errno));
#endif
}

static int parse_port(const char *s, unsigned short *out) {
    char *end = NULL;
    long v = strtol(s, &end, 10);
    if (end == s || *end != '\0' || v < 1 || v > 65535) return 0;
    *out = (unsigned short)v;
    return 1;
}

static sock_t make_listener(int type, unsigned short port) {
    int proto = (type == SOCK_STREAM) ? IPPROTO_TCP : IPPROTO_UDP;
    sock_t s = socket(AF_INET, type, proto);
    if (s == BAD_SOCKET) {
        log_sock_error("socket");
        return BAD_SOCKET;
    }

    /* SO_REUSEADDR lets us re-bind quickly after restart while a previous
     * socket is still in TIME_WAIT — important for an iteratively-tested tool. */
    int reuse = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR,
               (const char *)&reuse, sizeof(reuse));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port        = htons(port);

    if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) == SOCK_ERR) {
        log_sock_error("bind");
        close_sock(s);
        return BAD_SOCKET;
    }
    if (type == SOCK_STREAM &&
        listen(s, LISTEN_BACKLOG) == SOCK_ERR) {
        log_sock_error("listen");
        close_sock(s);
        return BAD_SOCKET;
    }
    return s;
}

static void format_peer(const struct sockaddr_in *peer, char *out, size_t n) {
    char ip[INET_ADDRSTRLEN] = "?";
    inet_ntop(AF_INET, (void *)&peer->sin_addr, ip, sizeof(ip));
    snprintf(out, n, "%s:%u", ip, ntohs(peer->sin_port));
}

static void handle_tcp_client(sock_t listener) {
    struct sockaddr_in peer;
    socklen_t peer_len = sizeof(peer);
    sock_t c = accept(listener, (struct sockaddr *)&peer, &peer_len);
    if (c == BAD_SOCKET) {
        log_sock_error("accept");
        return;
    }

    char who[64];
    format_peer(&peer, who, sizeof(who));
    printf("[tcp] connection from %s\n", who);
    fflush(stdout);

    char buf[BUF_SIZE];
    for (;;) {
        int n = recv(c, buf, (int)sizeof(buf) - 1, 0);
        if (n == 0) {
            printf("[tcp] %s closed\n", who);
            fflush(stdout);
            break;
        }
        if (n == SOCK_ERR) {
            log_sock_error("recv");
            break;
        }
        buf[n] = '\0';
        printf("[tcp] %s (%d B): %s\n", who, n, buf);
        fflush(stdout);
    }
    close_sock(c);
}

static void handle_udp_datagram(sock_t s) {
    char buf[BUF_SIZE];
    struct sockaddr_in peer;
    socklen_t peer_len = sizeof(peer);
    int n = recvfrom(s, buf, (int)sizeof(buf) - 1, 0,
                     (struct sockaddr *)&peer, &peer_len);
    if (n == SOCK_ERR) {
        log_sock_error("recvfrom");
        return;
    }
    buf[n] = '\0';
    char who[64];
    format_peer(&peer, who, sizeof(who));
    printf("[udp] %s (%d B): %s\n", who, n, buf);
    fflush(stdout);
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <tcp-port> <udp-port>\n",
                argc > 0 ? argv[0] : "c_listener");
        return 1;
    }
    unsigned short tcp_port = 0, udp_port = 0;
    if (!parse_port(argv[1], &tcp_port) ||
        !parse_port(argv[2], &udp_port)) {
        fprintf(stderr, "ports must be integers in 1..65535\n");
        return 1;
    }

#if defined(_WIN32) || defined(_WIN64)
    WSADATA wsa;
    int rc = WSAStartup(MAKEWORD(2, 2), &wsa);
    if (rc != 0) {
        fprintf(stderr, "WSAStartup failed: %d\n", rc);
        return 1;
    }
    SetConsoleCtrlHandler(on_console_event, TRUE);
#else
    signal(SIGINT, on_signal);
#endif

    sock_t tcp_sock = make_listener(SOCK_STREAM, tcp_port);
    sock_t udp_sock = make_listener(SOCK_DGRAM,  udp_port);
    if (tcp_sock == BAD_SOCKET || udp_sock == BAD_SOCKET) {
        if (tcp_sock != BAD_SOCKET) close_sock(tcp_sock);
        if (udp_sock != BAD_SOCKET) close_sock(udp_sock);
#if defined(_WIN32) || defined(_WIN64)
        WSACleanup();
#endif
        return 1;
    }

    printf("listening: tcp/%u udp/%u  (Ctrl+C to stop)\n", tcp_port, udp_port);
    fflush(stdout);

    /* select()'s first argument is ignored on Windows but must be the
     * highest fd + 1 on POSIX; computing it is harmless on both. */
    sock_t maxfd = (tcp_sock > udp_sock) ? tcp_sock : udp_sock;

    while (!g_stop) {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(tcp_sock, &rfds);
        FD_SET(udp_sock, &rfds);
        struct timeval tv = { 1, 0 };
        int ready = select((int)maxfd + 1, &rfds, NULL, NULL, &tv);
        if (ready == SOCK_ERR) {
#if !defined(_WIN32) && !defined(_WIN64)
            if (errno == EINTR) continue;  /* interrupted by SIGINT */
#endif
            log_sock_error("select");
            break;
        }
        if (ready == 0) continue;
        if (FD_ISSET(tcp_sock, &rfds)) handle_tcp_client(tcp_sock);
        if (FD_ISSET(udp_sock, &rfds)) handle_udp_datagram(udp_sock);
    }

    printf("shutting down\n");
    fflush(stdout);
    close_sock(tcp_sock);
    close_sock(udp_sock);
#if defined(_WIN32) || defined(_WIN64)
    WSACleanup();
#endif
    return 0;
}
