const std = @import("std");

const Tss = extern struct {
    _1: u32,
    rsp: [3]u64 align(4),
    _2: u64 align(4),
    ist: [7]u64 align(4),
    _3: u64 align(4),
    _4: u16,
    iopb: u16,
};

const TssIopb = extern struct {
    tss: Tss,
    iopb: u8 = 0xFF,
};

test "tss sizes" {
    try std.testing.expectEqual(104, @sizeOf(Tss));
}
