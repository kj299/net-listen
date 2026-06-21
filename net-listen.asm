; net-listen (NASM / Win64)
;
; Minimal TCP listener for Windows x64 written in raw assembly. It binds to
; 0.0.0.0:LISTEN_PORT, accepts one client at a time, echoes everything the
; client sends to stdout, then waits for the next connection.
;
; Microsoft x64 calling convention is used throughout:
;   - first four integer args go in RCX, RDX, R8, R9
;   - further args go on the stack starting at [RSP+32]
;   - callees may clobber the 32-byte "shadow space" at [RSP..RSP+31]
;   - RSP must be 16-byte aligned at every CALL instruction
;
; The entry point allocates a single 48-byte scratch frame (32 shadow +
; 8 for WriteFile's 5th arg + 8 padding) and reuses it for the lifetime of
; the program — no other prologue/epilogue is needed.
;
; Build:
;   nasm -f win64 net-listen.asm -o net-listen.obj
;   gcc -nostartfiles -Wl,-e,start net-listen.obj -o asm_listener.exe \
;       -lws2_32 -lkernel32

default rel
bits 64

%define AF_INET           2
%define SOCK_STREAM       1
%define IPPROTO_TCP       6
%define SOMAXCONN         128
%define LISTEN_PORT       1234
%define BUF_SIZE          1024
%define STD_OUTPUT_HANDLE -11

extern WSAStartup, WSACleanup, socket, bind, listen, accept, recv
extern closesocket, htons
extern GetStdHandle, WriteFile, ExitProcess

section .data
banner          db `net-listen (asm): listening on TCP/1234\r\n`
banner_len      equ $ - banner
msg_accepted    db `[asm] connection accepted\r\n`
msg_accepted_len equ $ - msg_accepted
msg_closed      db `[asm] connection closed\r\n`
msg_closed_len  equ $ - msg_closed
err_wsa         db `[asm] WSAStartup failed\r\n`
err_wsa_len     equ $ - err_wsa
err_sock        db `[asm] socket() failed\r\n`
err_sock_len    equ $ - err_sock
err_bind        db `[asm] bind() failed\r\n`
err_bind_len    equ $ - err_bind
err_lstn        db `[asm] listen() failed\r\n`
err_lstn_len    equ $ - err_lstn
err_acc         db `[asm] accept() failed\r\n`
err_acc_len     equ $ - err_acc

section .bss
align 8
wsadata         resb 408            ; sizeof(WSADATA) on 64-bit
sockaddr        resb 16             ; sockaddr_in
peer            resb 16
peer_len        resd 1
buffer          resb BUF_SIZE
hStdOut         resq 1
listen_s        resq 1
client_s        resq 1

section .text
global start

; PRINT ptr, len — WriteFile(hStdOut, ptr, len, NULL, NULL)
; Caller must already own a 48-byte scratch frame so [RSP+32] is writable.
%macro PRINT 2
    lea     rdx, [%1]
    mov     r8d, %2
    mov     rcx, [hStdOut]
    xor     r9, r9
    mov     qword [rsp+32], 0
    call    WriteFile
%endmacro

; DIE ptr, len — print message then ExitProcess(1)
%macro DIE 2
    PRINT   %1, %2
    mov     ecx, 1
    call    ExitProcess
%endmacro

start:
    ; Loaders may call the entry point with RSP in any alignment; force
    ; 16-byte alignment, then reserve a 48-byte scratch frame so RSP is
    ; 0 mod 16 at every subsequent CALL site.
    and     rsp, -16
    sub     rsp, 48

    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    mov     [hStdOut], rax

    ; WSAStartup(MAKEWORD(2,2), &wsadata)
    mov     ecx, 0x0202
    lea     rdx, [wsadata]
    call    WSAStartup
    test    eax, eax
    jz      .wsa_ok
    DIE     err_wsa, err_wsa_len
.wsa_ok:

    ; socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    mov     ecx, AF_INET
    mov     edx, SOCK_STREAM
    mov     r8d, IPPROTO_TCP
    call    socket
    cmp     rax, -1
    jne     .sock_ok
    DIE     err_sock, err_sock_len
.sock_ok:
    mov     [listen_s], rax

    ; sockaddr_in: family=AF_INET, port=htons(LISTEN_PORT), addr=INADDR_ANY
    mov     ecx, LISTEN_PORT
    call    htons
    mov     word  [sockaddr],    AF_INET
    mov     word  [sockaddr+2],  ax
    mov     dword [sockaddr+4],  0
    mov     dword [sockaddr+8],  0
    mov     dword [sockaddr+12], 0

    mov     rcx, [listen_s]
    lea     rdx, [sockaddr]
    mov     r8d, 16
    call    bind
    test    eax, eax
    jz      .bind_ok
    DIE     err_bind, err_bind_len
.bind_ok:

    mov     rcx, [listen_s]
    mov     edx, SOMAXCONN
    call    listen
    test    eax, eax
    jz      .listen_ok
    DIE     err_lstn, err_lstn_len
.listen_ok:

    PRINT   banner, banner_len

.accept_loop:
    mov     dword [peer_len], 16
    mov     rcx, [listen_s]
    lea     rdx, [peer]
    lea     r8,  [peer_len]
    call    accept
    cmp     rax, -1
    jne     .accept_ok
    PRINT   err_acc, err_acc_len
    jmp     .accept_loop
.accept_ok:
    mov     [client_s], rax
    PRINT   msg_accepted, msg_accepted_len

.recv_loop:
    mov     rcx, [client_s]
    lea     rdx, [buffer]
    mov     r8d, BUF_SIZE
    xor     r9d, r9d
    call    recv
    test    eax, eax
    jle     .client_done            ; 0 = orderly close, <0 = error

    ; Echo the recv'd bytes to stdout. Inline because the byte count is
    ; in EAX, not a static label that PRINT could LEA.
    mov     r8d, eax
    lea     rdx, [buffer]
    mov     rcx, [hStdOut]
    xor     r9, r9
    mov     qword [rsp+32], 0
    call    WriteFile
    jmp     .recv_loop

.client_done:
    mov     rcx, [client_s]
    call    closesocket
    PRINT   msg_closed, msg_closed_len
    jmp     .accept_loop
