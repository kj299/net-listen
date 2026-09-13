#!/usr/bin/env python3
"""Drive a running c_listener through its whole feature surface.

Used by the sanitizer CI job: the listener is built with ASan/UBSan, this
script exercises every code path that touches network input, and the job then
fails if the sanitizers reported anything.

Usage: exercise.py <tcp-port> <udp-port>
"""
import socket
import sys
import time

HOST = "127.0.0.1"


def main() -> int:
    tcp_port, udp_port = int(sys.argv[1]), int(sys.argv[2])

    # --- UDP: empty datagram, hostile bytes, and a full-buffer datagram -----
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.sendto(b"", (HOST, udp_port))                      # zero length
    udp.sendto(b"\x1b]0;title\x07esc\x00nul", (HOST, udp_port))
    udp.sendto(b"U" * 1023, (HOST, udp_port))              # exactly max recv
    udp.sendto(b"V" * 4096, (HOST, udp_port))              # oversized, truncated
    time.sleep(0.3)

    # --- TCP: a batch of concurrent clients kept open simultaneously --------
    held = []
    for i in range(40):
        s = socket.socket()
        s.connect((HOST, tcp_port))
        s.sendall(f"client-{i}".encode())
        held.append(s)
    time.sleep(0.4)

    # UDP must still be served while all those TCP clients are connected.
    udp.sendto(b"not-starved", (HOST, udp_port))
    time.sleep(0.2)

    # --- interleaved churn: close some, write on others, add new ones -------
    for i, s in enumerate(held):
        if i % 3 == 0:
            s.close()
    time.sleep(0.2)
    for i, s in enumerate(held):
        if i % 3 != 0:
            s.sendall(f"again-{i}".encode())
    time.sleep(0.2)
    for _ in range(5):
        s = socket.socket()
        s.connect((HOST, tcp_port))
        s.sendall(b"late-joiner")
        held.append(s)
    time.sleep(0.3)

    # --- abrupt disconnect (RST) rather than an orderly close --------------
    rude = socket.socket()
    rude.connect((HOST, tcp_port))
    rude.sendall(b"about-to-reset")
    rude.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER,
                    b"\x01\x00\x00\x00\x00\x00\x00\x00")
    rude.close()
    time.sleep(0.3)

    # --- hostile payload and max-size write over TCP ----------------------
    hostile = socket.socket()
    hostile.connect((HOST, tcp_port))
    hostile.sendall(b"\x1b[2J\x00\x07\xff\xfe binary-ish")
    time.sleep(0.15)
    hostile.sendall(b"W" * 1023)
    time.sleep(0.15)
    hostile.close()

    for s in held:
        try:
            s.close()
        except OSError:
            pass
    udp.close()
    time.sleep(0.4)
    return 0


if __name__ == "__main__":
    sys.exit(main())
