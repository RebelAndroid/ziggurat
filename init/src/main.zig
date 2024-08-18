const std = @import("std");

extern fn syscall(rdi: u64, rsi: u64, rdx: u64, rcx: u64, r8: u64, r9: u64) callconv(.C) u64;
comptime {
    asm (
        \\
        \\.globl syscall
        \\.type syscall @function
        \\syscall:
        \\  movq %rcx, %r10 # mov rcx into r10
        \\  syscall
        \\  retq
    );
}

pub export fn _start() noreturn {
    _ = syscall(1, 2, 3, 4, 5, 6);
    asm volatile ("int $3");
    while (true) {}
}
