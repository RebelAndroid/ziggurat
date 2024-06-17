const std = @import("std");
const log = std.log.scoped(.gdt);

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

pub const SegmentSelector = packed struct {
    requestor_privilege_level: u2,
    /// When clear, this selector uses the GDT. When set, this selector uses the LDT.
    table_indicator: bool,
    /// The byte position of the selected descriptor entry divided by 8. This is the index in the table; note that some descriptor entries are 16 bytes and thus count as 2 entries.
    selector_index: u13,
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

pub extern fn set_data_segment_registers(SegmentSelector) callconv(.C) void;
comptime {
    asm (
        \\.globl set_data_segment_registers
        \\.type set_data_segment_registers @function
        \\set_data_segment_registers:
        \\  movw %di, %es
        \\  movw %di, %ss
        \\  movw %di, %ds
        \\  movw %di, %fs
        \\  movw %di, %gs
        \\  retq
    );
}

pub extern fn set_code_segment_register(SegmentSelector) callconv(.C) void;
pub extern fn set_code_segment_register_2() callconv(.C) void;
comptime {
    asm (
        \\.globl set_code_segment_register
        \\.globl set_code_segment_register_2
        \\.type set_code_segment_register @function
        \\.type set_code_segment_register_2 @function
        \\set_code_segment_register:
        \\  push %rdi
        \\  leaq set_code_segment_register_2, %rax
        \\  push %rax
        \\  lretq
        \\set_code_segment_register_2:
        \\  retq
    );
}

pub fn load_gdt() void {
    GdtR.offset = @intFromPtr(&Gdt);
    GdtR.size = @sizeOf(@TypeOf(Gdt)) - 1;
    const x = @intFromPtr(&GdtR);
    lgdt(x);
    const data_segment_selector = SegmentSelector{
        .requestor_privilege_level = 0,
        .table_indicator = false,
        .selector_index = 2,
    };
    const code_segment_selector = SegmentSelector{
        .requestor_privilege_level = 0,
        .table_indicator = false,
        .selector_index = 1,
    };
    set_data_segment_registers(data_segment_selector);
    log.info("location of set_code_segment_register: 0x{X}\n", .{@intFromPtr(&set_code_segment_register)});
    log.info("location of set_code_segment_register_2: 0x{X}\n", .{@intFromPtr(&set_code_segment_register_2)});
    set_code_segment_register(code_segment_selector);
}
