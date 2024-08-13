const std = @import("std");
const gdt = @import("gdt.zig");

pub extern fn readMsr(msr: u32) callconv(.C) u64;
comptime {
    asm (
        \\.globl readMsr
        \\.type readMsr @function
        \\readMsr:
        \\  movl %edi, %ecx
        \\  rdmsr
        \\  shlq $32, %rdx
        \\  orq %rdx, %rax
        \\  retq
    );
}

pub extern fn writeMsr(msr: u32, value: u64) callconv(.C) void;
comptime {
    asm (
        \\.globl writeMsr
        \\.type writeMsr @function
        \\writeMsr:
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

const EFER_INDEX = 0xC0000080;
pub fn readEfer() Efer {
    return @bitCast(readMsr(EFER_INDEX));
}

pub fn writeEfer(efer: Efer) void {
    writeMsr(EFER_INDEX, @bitCast(efer));
}

const STAR_INDEX: u32 = 0xC0000081;
pub const Star = packed struct {
    _1: u32 = 0,
    kernel_cs_selector: gdt.SegmentSelector,
    user_cs_selector: gdt.SegmentSelector,
};

pub fn readStar() Star {
    return @bitCast(readMsr(STAR_INDEX));
}

pub fn writeStar(star: Star) void {
    writeMsr(STAR_INDEX, @bitCast(star));
}

const LSTAR_INDEX: u32 = 0xC0000082;
/// IA32_LSTAR is the target of syscall
pub fn readLstar() u64 {
    return @bitCast(readMsr(LSTAR_INDEX));
}

/// IA32_LSTAR is the target of syscall
pub fn writeLstar(lstar: u64) void {
    writeMsr(LSTAR_INDEX, @bitCast(lstar));
}

const FMASK_INDEX: u32 = 0xC0000084;
/// IA32_FMASK controls rflags
pub fn readFmask() u64 {
    return @bitCast(readMsr(FMASK_INDEX));
}

/// IA32_FMASK controls rflags
pub fn writeFmask(fmask: u64) u64 {
    writeMsr(FMASK_INDEX, @bitCast(fmask));
}

test "msr sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(Efer));
    try std.testing.expectEqual(64, @bitSizeOf(Star));
}
