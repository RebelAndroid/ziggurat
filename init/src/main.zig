const std = @import("std");

pub export fn _start() void {
    asm volatile ("syscall");
}
