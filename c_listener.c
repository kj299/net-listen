/* listens to both TCP and UDP connections and allows the user to specify the port and IP address.
You can compile this code using gcc and run it with two arguments: port number for TCP and port number for UDP. For example:
gcc network.c -o network
./network 1234 5678
This will listen to incoming connections on port number `1234` for TCP and `5678` for UDP. If you do not provide two arguments when running this program it will print a usage message
add  help if the user does not add the required variables.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* this is for UNIX systems
#include <sys/socket.h>
#include <arpa/inet.h>
socklen_t type is defined WS2tcpip.h
*/
#include <winsock2.h>
#include <WS2tcpip.h>
#include <unistd.h>

#define BUF_SIZE 1024

int main(int argc, char *argv[]) {
    int tcp_sock, udp_sock;
    struct sockaddr_in tcp_addr, udp_addr;
    char buffer[BUF_SIZE];
    int tcp_port = 0;
    int udp_port = 0;

    if (argc != 3) {
        printf("Usage: %s <tcp port> <udp port>\n", argv[0]);
        return 1;
    }

    tcp_port = atoi(argv[1]);
    udp_port = atoi(argv[2]);

    // Create TCP socket
    tcp_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (tcp_sock == -1) {
        printf("Could not create TCP socket");
        return 1;
    }

    // Create UDP socket
    udp_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (udp_sock == -1) {
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
    listen(tcp_sock, 5);

    while (1) {
        struct sockaddr_in client;
        socklen_t client_len = sizeof(client);

        // Accept incoming connections on the TCP socket
        int client_sock = accept(tcp_sock, (struct sockaddr *) &client, &client_len);
        if (client_sock == -1) {
            printf("Could not accept TCP connection");
            continue;
        }

        // Receive data from the client
        memset(buffer, 0, BUF_SIZE);
        int recv_len = recv(client_sock, buffer, BUF_SIZE - 1, 0);
        if (recv_len == -1) {
            printf("Could not receive data from TCP client");
            continue;
        }

        printf("Received data from TCP client: %s\n", buffer);

        // Send data back to the client
        if (send(client_sock, buffer, strlen(buffer), 0) == -1) {
            printf("Could not send data to TCP client");
            continue;
        }

        close(client_sock);
        
        // Receive data from the client on the UDP socket
        memset(buffer, 0, BUF_SIZE);
        recv_len = recvfrom(udp_sock, buffer, BUF_SIZE - 1, 0,
                            (struct sockaddr *) &client,
                            &client_len);
        if (recv_len == -1) {
            printf("Could not receive data from UDP client");
            continue;
        }

        printf("Received data from UDP client: %s\n", buffer);

        // Send data back to the client on the UDP socket
        if (sendto(udp_sock, buffer, strlen(buffer), 0,
                   (struct sockaddr *) &client,
                   sizeof(client)) == -1) {
            printf("Could not send data to UDP client");
            continue;
        }
        
    }

    close(tcp_sock);
    close(udp_sock);

    return 0;
}
