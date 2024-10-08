const std = @import("std");
const gdt = @import("gdt.zig");
const reg = @import("registers.zig");

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
pub fn readFmask() reg.Rflags {
    return @bitCast(readMsr(FMASK_INDEX));
}

/// IA32_FMASK controls rflags
pub fn writeFmask(fmask: reg.Rflags) void {
    writeMsr(FMASK_INDEX, @bitCast(fmask));
}

const KERNEL_GS_INDEX: u32 = 0xC0000102;
/// IA32_FMASK controls rflags
pub fn readKernelGsBase() u64 {
    return readMsr(KERNEL_GS_INDEX);
}

/// IA32_FMASK controls rflags
pub fn writeKernelGsBase(gs_base: u64) void {
    writeMsr(KERNEL_GS_INDEX, gs_base);
}

const APIC_BASE_INDEX: u32 = 0x1B;
pub const ApicBase = packed struct {
    _1: u8 = 0,
    // set if this processor is the bootstrap processor
    bsp: bool,
    _2: u1 = 0,
    enable_x2apic: bool,
    enable_xapic: bool,
    apic_base: u24,
    _3: u28,
};

pub fn readApicBase() ApicBase {
    return @bitCast(readMsr(APIC_BASE_INDEX));
}

pub fn writeApicBase(apic_base: ApicBase) void {
    writeMsr(APIC_BASE_INDEX, @bitCast(apic_base));
}

// const MTRRCAP_INDEX: u32 = 0xFE;
// pub const MtrrCap = packed struct {
//     /// The number of variable range registers available
//     vcnt: u8,
//     /// Set if fixed range registers are supported
//     fix: bool,
//     _1: bool,
//     /// Set if write-combining memory type is supported
//     wc: bool,
//     /// Set if System-Management range register is supported
//     smrr: bool,
//     _2: u52,
// };

// pub fn readMtrrCap() MtrrCap {
//     return @bitCast(readMsr(MTRRCAP_INDEX));
// }

// pub fn writeMtrrCap(mtrrCap: MtrrCap) void {
//     writeMsr(MTRRCAP_INDEX, @bitCast(mtrrCap));
// }

// const MTRR_VAR_INDEX_BASE: u32 = 0x200;
// /// Figure 12-7 in Intel SDM Vol 3a. 12-25
// pub const MtrrPhysicalBase = packed struct {
//     type: u8,
//     _1: u4,
//     base: u40,
//     _2: u12,
// };

// /// Figure 12-7 in Intel SDM Vol 3a. 12-25
// pub const MtrrPhysicalMask = packed struct {
//     _1: u11,
//     valid: bool,
//     mask: u40,
//     _2: u12,
// };

test "msr sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(Efer));
    try std.testing.expectEqual(64, @bitSizeOf(Star));
    try std.testing.expectEqual(64, @bitSizeOf(ApicBase));
    // try std.testing.expectEqual(64, @bitSizeOf(MtrrCap));
}
