const std = @import("std");

pub const GdtDescriptor = packed struct {
    size: u16,
    offset: u64,
    pub fn get_entries(self: GdtDescriptor) []GdtEntry {
        const start: [*]GdtEntry = @ptrFromInt(self.offset);
        const length = (@as(u64, self.size) + 1) / 8;
        return start[0..length];
    }
};

pub var GdtR: GdtDescriptor = std.mem.zeroes(GdtDescriptor);

pub var Gdt: [3]GdtEntry = std.mem.zeroes([3]GdtEntry);

pub const GdtEntry = packed struct {
    limit1: u16 = 0,
    base1: u16 = 0,
    base2: u8 = 0,
    accessed: bool = false,
    /// Code segments: readable if set, data segments: writable if set
    rw: bool,
    /// Code selectors: can only be executed from ring in dpl if clear, can be executed in at most DPL if set.
    ///
    /// Data selectors: the segment grows up if clear, the segment grows down if set,
    direction_conforming: bool,
    /// data segment if clear, code segment if set
    executable: bool,
    /// set to define a code or data segment
    descriptor_type: bool = true,
    descriptor_privilege_level: u2,
    present: bool = true,
    limit2: u4 = 0,
    _1: bool = false,
    /// this descriptor defines a 64-bit code segment if set
    long_mode_code: bool,
    /// clear to define a 16 bit protected mode segment, set to define a 32 bit protected mode segment, should always be clear when long_mode_code is set
    size: bool,
    /// scale limit by 1 if clear, scale limit by 4KiB if set
    granularity: bool,
    base3: u8 = 0,
    pub fn get_base(self: GdtEntry) u64 {
        return @as(u64, self.base1) | (@as(u64, self.base2) << 16) | (@as(u64, self.base3) << 24);
    }
    pub fn set_base(self: GdtEntry, base: u64) void {
        self.base1 = @truncate(base);
        self.base2 = @truncate(base >> 16);
        self.base3 = @truncate(base >> 24);
    }
    pub fn get_limit(self: GdtEntry) u64 {
        return @as(u64, self.limit1) | @as(u64, self.limit2) << 16;
    }
    pub fn set_limit(self: GdtEntry, limit: u64) void {
        self.limit1 = @truncate(limit);
        self.limit2 = @truncate(limit >> 16);
    }
};

pub extern fn lgdt(u64) callconv(.C) void;
comptime {
    asm (
        \\.globl lgdt
        \\.type lgdt @function
        \\lgdt:
        \\  lgdtq (%rdi)
        \\  retq
    );
}

pub extern fn sgdt(*GdtDescriptor) callconv(.C) void;
comptime {
    asm (
        \\.globl sgdt
        \\.type sgdt @function
        \\sgdt:
        \\  sgdtq (%rdi)
        \\  retq
    );
}

pub fn load_gdt() void {
    GdtR.offset = @intFromPtr(&Gdt);
    GdtR.size = @sizeOf(@TypeOf(Gdt)) - 1;
    const x = @intFromPtr(&GdtR);
    lgdt(x);
}
