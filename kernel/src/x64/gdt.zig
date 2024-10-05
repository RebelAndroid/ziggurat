const std = @import("std");
const log = std.log.scoped(.gdt);
const tss = @import("tss.zig");

pub const Gdt: type = [9]GdtEntry;

pub const GdtDescriptor = extern struct {
    size: u16,
    offset: u64 align(2),
    pub fn get_entries(self: GdtDescriptor) []GdtEntry {
        const start: [*]GdtEntry = @ptrFromInt(self.offset);
        const length = @divExact(@as(u64, self.size) + 1, 8);
        return start[0..length];
    }
};

/// See Intel SDM Volume 3 Section 3.4.5 "Segment Descriptors"
pub const GdtEntry = packed struct {
    limit1: u16 = 0xFFFF,
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
    limit2: u4 = 0xF,
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
    pub fn set_base(self: *volatile GdtEntry, base: u64) void {
        self.base1 = @truncate(base);
        self.base2 = @truncate(base >> 16);
        self.base3 = @truncate(base >> 24);
    }
    pub fn get_limit(self: GdtEntry) u64 {
        return @as(u64, self.limit1) | @as(u64, self.limit2) << 16;
    }
    pub fn set_limit(self: *volatile GdtEntry, limit: u64) void {
        self.limit1 = @truncate(limit);
        self.limit2 = @truncate(limit >> 16);
    }
};

pub const SegmentSelector = packed struct {
    requestor_privilege_level: u2,
    /// When clear, this selector uses the GDT. When set, this selector uses the LDT.
    table_indicator: bool,
    /// The byte position of the selected descriptor entry divided by 8. This is the index in the
    /// table; note that some descriptor entries are 16 bytes and thus count as 2 entries.
    selector_index: u13,
};

pub const kernel_star_segment_selector = SegmentSelector{
    .requestor_privilege_level = 0,
    .table_indicator = false,
    .selector_index = 5,
};

pub const user_star_segment_selector = SegmentSelector{
    .requestor_privilege_level = 3,
    .table_indicator = false,
    .selector_index = 6,
};

pub const kernel_code_segment_selector = SegmentSelector{
    .requestor_privilege_level = 0,
    .table_indicator = false,
    .selector_index = kernel_star_segment_selector.selector_index, // 5
};

pub const kernel_data_segment_selector = SegmentSelector{
    .requestor_privilege_level = 0,
    .table_indicator = false,
    .selector_index = kernel_star_segment_selector.selector_index + 1, // 6
};

pub const user_data_segment_selector = SegmentSelector{
    .requestor_privilege_level = 3,
    .table_indicator = false,
    .selector_index = user_star_segment_selector.selector_index + 1, // 7
};
pub const user_code_segment_selector = SegmentSelector{
    .requestor_privilege_level = 3,
    .table_indicator = false,
    .selector_index = user_star_segment_selector.selector_index + 2, // 8
};

pub const tss_segment_selector = SegmentSelector{
    .requestor_privilege_level = 0,
    .table_indicator = false,
    .selector_index = 2,
};

/// Creates the GDT in memory. This function should be called once.
pub fn writeGdt(gdt: *Gdt, tss_ptr: *tss.TssIopb) void {
    // The first gdt entry is always a null descriptor
    gdt[0] = std.mem.zeroes(GdtEntry);

    // The second entry will be the kernel data segment
    // This segment must match what is required by SYSCALL, see intel software developers manual Vol 2B 4-695 - 4-496
    gdt[kernel_data_segment_selector.selector_index] = GdtEntry{
        // SS.Base := 0, default base
        // SS.Limit := 0xFFFFF, default limit
        // SS.Type := 3
        .accessed = true,
        .rw = true,
        .direction_conforming = false,
        .executable = false,
        // SS.S := 1
        .descriptor_type = true,
        // SS.DPL := 0
        .descriptor_privilege_level = 0,
        // SS.P := 1, default present
        // SS.B := 1
        .size = true,
        // SS.G := 1
        .granularity = true,

        .long_mode_code = false,
    };

    // The third entry will be the kernel code segment
    // This segment must match what is required by SYSCALL, see intel software developers manual Vol 2B 4-695 - 4-496
    gdt[kernel_code_segment_selector.selector_index] = GdtEntry{
        // CS.Base := 0, default base
        // CS.Limit := 0xFFFFF, default limit
        // CS.TYPE := 11
        .accessed = true,
        .rw = true,
        .direction_conforming = false,
        .executable = true,
        // CS.S := 1
        .descriptor_type = true,
        // CS.DPL := 0
        .descriptor_privilege_level = 0,
        // CS.P := 1, default present
        // CS.L := 1
        .long_mode_code = true,
        // CS.D := 0
        .size = false,
        // CS.G := 1
        .granularity = true,
    };

    // The fourth entry will be the user data segment
    // This segment must match what is required by SYSRET, see intel software developers manual Vol 2B 4-705 - 4-706
    gdt[user_data_segment_selector.selector_index] = GdtEntry{
        // SS.Base := 0, default base
        // SS.Limit := 0xFFFFF, default limit
        // SS.Type := 3
        .accessed = true,
        .rw = true,
        .direction_conforming = false,
        .executable = false,
        // SS.S := 1
        .descriptor_type = true,
        // SS.DPL := 3
        .descriptor_privilege_level = 3,
        // SS.P := 1, default present
        // SS.B := 1
        .size = true,
        // SS.G := 1
        .granularity = true,

        .long_mode_code = false,
    };

    // The fifth entry will be the user code segment
    // This segment must match what is required by SYSRET, see intel software developers manual Vol 2B 4-705 - 4-706
    gdt[user_code_segment_selector.selector_index] = GdtEntry{
        // CS.Base := 0, default base
        // CS.Limit := 0xFFFFF, default limit
        // CS.Type := 11
        .accessed = true,
        .rw = true,
        .direction_conforming = false,
        .executable = true,
        // CS.S := 1
        .descriptor_type = true,
        // CS.DPL := 3
        .descriptor_privilege_level = 3,
        // CS.P := 1, default present
        // CS.L := 1
        .long_mode_code = true,
        // CS.D := 0
        .size = false,
        // CS.G := 1
        .granularity = true,
    };

    // now we load the TSS
    const tss_base: u64 = @intFromPtr(tss_ptr);
    var tss_descriptor_bottom = tss.TssDescriptorBottom{
        .avl = 1,
        .typ = 9,
    };
    tss_descriptor_bottom.set_base(tss_base);
    tss_descriptor_bottom.set_limit(@sizeOf(tss.TssIopb));

    const tss_descriptor_top = tss.TssDescriptorTop{
        .base4 = @truncate(tss_base >> 32),
    };

    gdt[tss_segment_selector.selector_index] = @bitCast(tss_descriptor_bottom);
    gdt[tss_segment_selector.selector_index + 1] = @bitCast(tss_descriptor_top);
}

/// Loads the gdt into the gdt descriptor register. This function should be called once on every CPU.
pub fn loadGdt(gdtr: *volatile GdtDescriptor, gdt: *Gdt) void {
    gdtr.offset = @intFromPtr(gdt);
    gdtr.size = @sizeOf(Gdt) - 1;
    const x = @intFromPtr(gdtr);
    log.debug("loading gdtr at 0x{x}\n", .{x});
    log.debug("size: 0x{x}, offset: 0x{x}\n", .{ gdtr.size, gdtr.offset });
    lgdt(x);

    setDataSegmentRegisters(kernel_data_segment_selector);
    setCodeSegmentRegisters(kernel_code_segment_selector, @intFromPtr(&set_code_segment_register_2));

    log.debug("flushing tss\n", .{});
    flushTss(@bitCast(tss_segment_selector));
    log.debug("flushed tss\n", .{});
}

extern fn lgdt(u64) callconv(.C) void;
comptime {
    asm (
        \\.globl lgdt
        \\.type lgdt @function
        \\lgdt:
        \\  lgdtq (%rdi)
        \\  retq
    );
}

extern fn sgdt(*GdtDescriptor) callconv(.C) void;
comptime {
    asm (
        \\.globl sgdt
        \\.type sgdt @function
        \\sgdt:
        \\  sgdtq (%rdi)
        \\  retq
    );
}

extern fn flushTss(u16) callconv(.C) void;
comptime {
    asm (
        \\.globl flushTss
        \\.type flushTss @function
        \\flushTss:
        \\  ltr %di
        \\  retq
    );
}

extern fn setDataSegmentRegisters(SegmentSelector) callconv(.C) void;
comptime {
    asm (
        \\.globl setDataSegmentRegisters
        \\.type setDataSegmentRegisters @function
        \\setDataSegmentRegisters:
        \\  movw %di, %es
        \\  movw %di, %ss
        \\  movw %di, %ds
        \\  movw %di, %fs
        \\  movw %di, %gs
        \\  retq
    );
}

extern fn setCodeSegmentRegisters(SegmentSelector, u64) callconv(.C) void;
extern fn set_code_segment_register_2() callconv(.C) void;
comptime {
    asm (
        \\.globl setCodeSegmentRegisters
        \\.globl set_code_segment_register_2
        \\.type setCodeSegmentRegisters @function
        \\.type set_code_segment_register_2 @function
        \\setCodeSegmentRegisters:
        \\  push %rdi
        \\  push %rsi
        \\  lretq
        \\set_code_segment_register_2:
        \\  retq
    );
}

test "gdt sizes" {
    try std.testing.expectEqual(16, @bitSizeOf(SegmentSelector));
    try std.testing.expectEqual(64, @bitSizeOf(GdtEntry));
    try std.testing.expectEqual(8, @sizeOf(GdtEntry));
    try std.testing.expectEqual(10, @sizeOf(GdtDescriptor));
    try std.testing.expectEqual(0, @offsetOf(GdtDescriptor, "size"));
    try std.testing.expectEqual(2, @offsetOf(GdtDescriptor, "offset"));
}
