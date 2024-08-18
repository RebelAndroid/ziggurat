const std = @import("std");

pub const Tss = extern struct {
    _1: u32 = 0,
    rsp: [3]u64 align(4) = [_]u64{ 0, 0, 0 },
    _2: u64 align(4) = 0,
    ist: [7]u64 align(4) = [_]u64{ 0, 0, 0, 0, 0, 0, 0 },
    _3: u64 align(4) = 0,
    _4: u16 = 0,
    iopb: u16 = 0,
};

pub const TssIopb = extern struct {
    tss: Tss = Tss{},
    iopb: u8 = 0xFF,
};

pub var tss_iopb: TssIopb align(4096) = TssIopb{};

pub fn initTss(kernel_stack: u64) void {
    tss_iopb.tss.rsp[0] = kernel_stack;
    tss_iopb.tss.iopb = 104; // the iopb immediately follows the tss
}

test "tss sizes" {
    try std.testing.expectEqual(104, @sizeOf(Tss));
}
