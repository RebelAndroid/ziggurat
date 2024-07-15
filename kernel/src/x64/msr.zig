const std = @import("std");
pub extern fn read_msr(msr: u32) callconv(.C) u64;
comptime {
    asm (
        \\.globl read_msr
        \\.type read_msr @function
        \\read_msr:
        \\  movl %edi, %ecx
        \\  rdmsr
        \\  shlq $32, %rdx
        \\  orq %rdx, %rax
        \\  retq
    );
}

pub const Efer = packed struct {
    system_call_extensions: bool,
    _1: u7,
    long_mode_enable: bool,
    _2: u1,
    long_mode_active: bool,
    no_execute_enable: bool,
    secure_virtual_machine_enable: bool,
    long_mode_segment_limit_enable: bool,
    fast_fxsave_fxrstor: bool,
    translation_cache_extension: bool,
    _3: u48,
};

test "msr sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(Efer));
}
