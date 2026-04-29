/* listens to both TCP and UDP connections and allows the user to specify the port and IP address.
You can build with the supplied Makefile (which detects the OS) or directly:
  Linux (Ubuntu, RHEL):  gcc c_listener.c -o c_listener
  Windows (MinGW):       gcc c_listener.c -o c_listener.exe -lws2_32
Run with two arguments: TCP port and UDP port. For example:
  ./c_listener 1234 5678
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) || defined(_WIN64)
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #define CLOSE_SOCKET(s) closesocket(s)
  #define SOCK_INVALID    INVALID_SOCKET
  typedef SOCKET sock_t;
#else
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #include <unistd.h>
  #define CLOSE_SOCKET(s) close(s)
  #define SOCK_INVALID    (-1)
  typedef int sock_t;
#endif

#define BUF_SIZE 1024
#define MAX_RECV_LEN 1023 //need to leave room for the terminating null character when storing text in C and avoid buffer overflows
#define LISTEN_BACKLOG 5

int main(int argc, char *argv[]) {
    sock_t tcp_sock, udp_sock;
    struct sockaddr_in tcp_addr, udp_addr;
    char buffer[BUF_SIZE];
    int tcp_port = 0;
    int udp_port = 0;

    // Check the number of arguments
    if (argc != 3) {
        printf("Usage: %s <tcp port> <udp port>\n", argv[0]);
        return 1;
    }

#if defined(_WIN32) || defined(_WIN64)
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        printf("WSAStartup failed");
        return 1;
    }
#endif

    // Get the TCP port
    tcp_port = atoi(argv[1]);

    // Get the UDP port
    udp_port = atoi(argv[2]);

    // Create TCP socket
    tcp_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (tcp_sock == SOCK_INVALID) {
        printf("Could not create TCP socket");
        return 1;
    }

    // Create UDP socket
    udp_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (udp_sock == SOCK_INVALID) {
        printf("Could not create UDP socket");
        return 1;
    }

    // Prepare the sockaddr_in structure
    tcp_addr.sin_family = AF_INET;
    tcp_addr.sin_addr.s_addr = INADDR_ANY;
    tcp_addr.sin_port = htons(tcp_port);

    udp_addr.sin_family = AF_INET;
    udp_addr.sin_addr.s_addr = INADDR_ANY;
    udp_addr.sin_port = htons(udp_port);

    // Bind the TCP socket
    if (bind(tcp_sock, (struct sockaddr *) &tcp_addr, sizeof(tcp_addr)) == -1) {
        printf("Could not bind TCP socket");
        return 1;
    }

    // Bind the UDP socket
    if (bind(udp_sock, (struct sockaddr *) &udp_addr, sizeof(udp_addr)) == -1) {
        printf("Could not bind UDP socket");
        return 1;
    }

    // Listen for incoming connections on the TCP socket
    if (listen(tcp_sock, LISTEN_BACKLOG) == -1) {
        printf("Could not listen on TCP socket");
        return 1;
    }

    while (1) {
        struct sockaddr_in client;
        socklen_t client_len = sizeof(client);

        // Accept incoming connections on the TCP socket
        sock_t client_sock = accept(tcp_sock, (struct sockaddr *) &client, &client_len);
        if (client_sock == SOCK_INVALID) {
            printf("Could not accept TCP connection");
            continue;
        }

        // Receive data from the client on the TCP socket
        memset(buffer, 0, BUF_SIZE);
        int recv_len = recv(client_sock, buffer, MAX_RECV_LEN, 0);
        if (recv_len == -1) {
            printf("Could not receive data from TCP client");
            continue;
        }
    }

    CLOSE_SOCKET(tcp_sock);
    CLOSE_SOCKET(udp_sock);

#if defined(_WIN32) || defined(_WIN64)
    WSACleanup();
#endif

    return 0;
}
