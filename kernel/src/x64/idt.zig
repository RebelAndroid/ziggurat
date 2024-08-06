const std = @import("std");
const gdt = @import("gdt.zig");

const log = std.log.scoped(.idt);

pub var IDT: [256]IdtEntry = std.mem.zeroes([256]IdtEntry);
pub var IdtR: IdtDescriptor = std.mem.zeroes(IdtDescriptor);

pub const IdtEntry = packed struct {
    offset1: u16 = 0,
    segment_selector: gdt.SegmentSelector,
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

extern fn lidt(u64) callconv(.C) void;
comptime {
    asm (
        \\.globl lidt
        \\.type lidt @function
        \\lidt:
        \\  lidtq (%rdi)
        \\  retq
    );
}

inline fn done() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

export fn pageFaultHandler(_: *u8, err: u64) callconv(.Interrupt) noreturn {
    const address = asm volatile (
        \\movq %CR2, %rax
        : [ret] "= {rax}" (-> usize),
    );
    log.err("page fault! At address: 0x{x} with error code: 0x{x}\n", .{ address, err });
    done();
}

export fn breakpointHandler() callconv(.Interrupt) void {
    log.info("breakpoint!\n", .{});
}

export fn generalProtectionHandler() callconv(.Interrupt) noreturn {
    log.info("General Protection Fault!\n", .{});
    done();
}

export fn doubleFaultHandler() callconv(.Interrupt) noreturn {
    log.info("Double Fault!\n", .{});
    done();
}

fn setIdtEntries() void {
    var breakpoint_entry: IdtEntry = .{
        .segment_selector = gdt.kernel_code_segment_selector,
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    breakpoint_entry.setOffset(@intFromPtr(&breakpointHandler));

    var page_fault_entry: IdtEntry = .{
        .segment_selector = gdt.kernel_code_segment_selector,
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    page_fault_entry.setOffset(@intFromPtr(&pageFaultHandler));

    var genprot_entry: IdtEntry = .{
        .segment_selector = gdt.kernel_code_segment_selector,
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    genprot_entry.setOffset(@intFromPtr(&generalProtectionHandler));

    var double_fault_entry: IdtEntry = .{
        .segment_selector = gdt.kernel_code_segment_selector,
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    double_fault_entry.setOffset(@intFromPtr(&doubleFaultHandler));

    IDT[3] = breakpoint_entry;
    IDT[8] = double_fault_entry;
    IDT[0xD] = genprot_entry;
    IDT[0xE] = page_fault_entry;
    log.warn("page fault entry: 0x{x}\n", .{@intFromPtr(&page_fault_entry)});
}

pub fn loadIdt() void {
    setIdtEntries();
    IdtR.size = @sizeOf(@TypeOf(IDT)) - 1;
    IdtR.offset = @intFromPtr(&IDT);
    const x = @intFromPtr(&IdtR);
    lidt(x);
}
