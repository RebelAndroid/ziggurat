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

pub extern fn getDs() callconv(.C) u16;
comptime {
    asm (
        \\.globl getDs
        \\.type getDs @function
        \\getDs:
        \\  movw %ds, %ax
        \\  retq
    );
}

pub extern fn getCs() callconv(.C) u16;
comptime {
    asm (
        \\.globl getCs
        \\.type getCs @function
        \\getCs:
        \\  movw %cs, %ax
        \\  retq
    );
}

pub extern fn getSs() callconv(.C) u16;
comptime {
    asm (
        \\.globl getSs
        \\.type getSs @function
        \\getSs:
        \\  movw %ss, %ax
        \\  retq
    );
}

inline fn breakpoint() void {
    asm volatile ("int $3");
}

pub export fn _start(rdi: u64, rsi: u64, rdx: u64, rcx: u64, r8: u64, r9: u64) callconv(.C) noreturn {
    _ = syscall(rdi, rsi, rdx, rcx, r8, r9);
    breakpoint();
    _ = syscall(7, 8, 9, 10, 11, 12);
    while (true) {}
}
