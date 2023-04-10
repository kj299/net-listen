; asm language to listen to network
; To run assembly code, you need to assemble it first using an assembler such as NASM or GAS. Once you have assembled the code, you can link it with a linker such as ld to create an ; executable file. Here’s an example of how to assemble and link an assembly program using NASM and ld:
; nasm -f elf64 -o program.o program.asm
; ld -s -o program program.o
; This will create an executable file called program from the assembly code in program.asm. You can then run the program by typing:
; ./program

section .data
    BUF_SIZE equ 1024

section .bss
    buffer resb BUF_SIZE

section .text
    global _start

_start:
    ; Create TCP socket
    mov eax, 1          ; socketcall()
    xor ebx, ebx        ; socket type = SOCK_STREAM
    mov ecx, 0x2        ; protocol = IPPROTO_IP
    mov edx, eax        ; save socket call number for later use
    mov eax, 0x66       ; socketcall() number
    int 0x80            ; call kernel

    cmp eax, 0          ; check for errors
    jl error

    mov esi, eax        ; save TCP socket descriptor

    ; Create UDP socket
    mov eax, edx        ; restore socket call number
    xor ebx, ebx        ; socket type = SOCK_DGRAM
    mov ecx, 0x2        ; protocol = IPPROTO_IP
    mov edx, eax        ; save socket call number for later use
    int 0x80            ; call kernel

    cmp eax, 0          ; check for errors
    jl error

    mov edi, eax        ; save UDP socket descriptor

    ; Prepare the sockaddr_in structure for TCP
    xor eax, eax        ; zero out eax register
    mov al, 0x2         ; AF_INET = 2
    xor ebx, ebx        ; zero out ebx register
    push ebx            ; INADDR_ANY = 0.0.0.0
    push word [tcp_port]     ; port number for TCP (in network byte order)
    mov ecx, esp        ; pointer to sockaddr_in structure for TCP
                        ; esp points to port number on top of stack,
                        ; INADDR_ANY is below it (pushed first)
                        ; and AF_INET is in al register (pushed last)

    ; Prepare the sockaddr_in structure for UDP
    xor ebx, ebx        ; zero out ebx register again
    push ebx            ; INADDR_ANY = 0.0.0.0 again
    push word [udp_port]     ; port number for UDP (in network byte order)
    mov edx, esp        ; pointer to sockaddr_in structure for UDP

bind_tcp:
    ; Bind the TCP socket to the specified port and INADDR_ANY address
    xor eax, eax        ; zero out eax register again
    mov al, 0x16        ; bind() syscall number = 22 (in decimal)
                        ; this is different from x86-64 architecture!
                        ;
                        ; bind(int sockfd,
                        ;      const struct sockaddr *addr,
                        ;      socklen_t addrlen);
                        ;
                        ; sockfd - file descriptor of the socket to bind to;
                        ;
                        ; addr - pointer to a struct sockaddr containing the address to bind to;
                        ;
                        ; addrlen - length of the address structure in bytes.
                        ;
                        ;
                        ;
                        ;
                        ;
                        ;
                        ;
                        ;
                        ;
                        ;
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        
