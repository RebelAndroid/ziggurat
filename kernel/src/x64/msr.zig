const std = @import("std");
const gdt = @import("gdt.zig");

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

pub const Star = packed struct {
    _1: u32 = 0,
    kernel_cs_selector: gdt.SegmentSelector,
    user_cs_selector: gdt.SegmentSelector,
};

pub fn read_star() Star {
    return @bitCast(read_msr(0xC0000081));
}

pub fn write_star(star: Star) void {
    write_msr(0xC0000081, @bitCast(star));
}

/// IA32_LSTAR is the target of syscall
pub fn read_lstar() u64 {
    return @bitCast(read_msr(0xC0000082));
}

/// IA32_LSTAR is the target of syscall
pub fn write_lstar(lstar: u64) void {
    write_msr(0xC0000081, @bitCast(lstar));
}

/// IA32_FMASK controls rflags
pub fn read_fmask() u64 {
    return @bitCast(read_msr(0xC0000084));
}

/// IA32_FMASK controls rflags
pub fn write_fmask(fmask: u64) u64 {
    write_msr(0xC0000084, @bitCast(fmask));
}

test "msr sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(Efer));
    try std.testing.expectEqual(64, @bitSizeOf(Star));
}
