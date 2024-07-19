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

pub extern fn write_msr(msr: u32, value: u64) callconv(.C) void;
comptime {
    asm (
        \\.globl write_msr
        \\.type write_msr @function
        \\write_msr:
        \\  movl %edi, %ecx
        \\  movq %rsi, %rax
        \\  movq %rsi, %rdx
        \\  shrq $32, %rdx
        \\  wrmsr
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

pub fn read_efer() Efer {
    return @bitCast(read_msr(0xC0000080));
}

pub fn write_efer(efer: Efer) void {
    write_msr(0xC0000080, @bitCast(efer));
}

test "msr sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(Efer));
}
