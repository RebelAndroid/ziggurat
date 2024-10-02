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

pub const TssDescriptorBottom = packed struct {
    limit1: u16 = 0,
    base1: u16 = 0,
    base2: u8 = 0,
    /// See table 3-2 Intel SDM Vol 3. 3-14
    typ: u4 = 0,
    _1: u1 = 0,
    dpl: u2 = 0,
    p: bool = true,
    limit2: u4 = 0,
    avl: u1 = 0,
    _2: u2 = 0,
    g: u1 = 0,
    base3: u8 = 0,
    pub fn set_limit(self: *volatile TssDescriptorBottom, limit: u64) void {
        self.limit1 = @truncate(limit);
        self.limit2 = @truncate(limit >> 16);
    }
    pub fn set_base(self: *volatile TssDescriptorBottom, base: u64) void {
        self.base1 = @truncate(base);
        self.base2 = @truncate(base >> 16);
        self.base3 = @truncate(base >> 24);
    }
};

pub const TssDescriptorTop = packed struct {
    base4: u32,
    _1: u32 = 0,
};

pub fn writeTss(tss_iopb: *TssIopb, kernel_stack: u64) void {
    tss_iopb.tss.rsp[0] = kernel_stack;
    tss_iopb.tss.iopb = 104; // the iopb immediately follows the tss
}

test "tss sizes" {
    try std.testing.expectEqual(104, @sizeOf(Tss));
}
