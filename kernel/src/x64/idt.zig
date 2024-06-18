const std = @import("std");

pub var IDT: [256]IdtEntry = std.mem.zeroes([256]IdtEntry);
pub var IdtR: IdtDescriptor = std.mem.zeroes(IdtDescriptor);

pub const IdtEntry = packed struct {
    offset1: u16 = 0,
    segment_selector: u16,
    ist: u3,
    _1: u5 = 0,
    gate_type: u4,
    _2: u1 = 0,
    dpl: u2,
    p: u1 = 1,
    offset2: u48 = 0,
    _3: u32 = 0,
    pub fn setOffset(self: *IdtEntry, offset: u64) void {
        self.offset1 = @truncate(offset);
        self.offset2 = @truncate(offset >> 16);
    }
    pub fn getOffset(self: IdtEntry) u64 {
        return (@as(u64, self.offset2) << 16) | self.offset1;
    }
};

pub const IdtDescriptor = packed struct {
    size: u16,
    offset: u64,
};

pub extern fn lidt(u64) callconv(.C) void;
comptime {
    asm (
        \\.globl lidt
        \\.type lidt @function
        \\lidt:
        \\  lidtq (%rdi)
        \\  retq
    );
}

pub fn load_idt() void {
    IdtR.size = @sizeOf(@TypeOf(IDT)) - 1;
    IdtR.offset = @intFromPtr(&IDT);
    const x = @intFromPtr(&IdtR);
    lidt(x);
}
