const std = @import("std");
const gdt = @import("gdt.zig");
const reg = @import("registers.zig");
const apic = @import("apic.zig");

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

const PageFaultErrorCode = packed struct {
    present: bool,
    write: bool,
    user: bool,
    reserved_write: bool,
    instruction_fetch: bool,
    protection_key: bool,
    shadow_stack: bool,
    _1: u8,
    software_guard_extensions: bool,
    _2: u16,
    _3: u32,
};

export fn pageFaultHandler(_: *u8, err: u64) callconv(.Interrupt) noreturn {
    const address = asm volatile (
        \\movq %CR2, %rax
        : [ret] "= {rax}" (-> usize),
    );
    const err2: PageFaultErrorCode = @bitCast(err);
    log.err("page fault! At address: 0x{x} with error code: {}\n", .{ address, err2 });
    done();
}

export fn breakpointHandler() callconv(.Interrupt) void {
    log.info("breakpoint!\n", .{});
}

export fn generalProtectionHandler(_: *u8, err: u64) callconv(.Interrupt) noreturn {
    if (err != 0) {
        const segment_selector: gdt.SegmentSelector = @bitCast(@as(u16, @truncate(err)));
        log.info("General Protection Fault! segment: 0x{x}, {}\n", .{ err, segment_selector });
    } else {
        log.info("General Protection Fault! not segment related\n", .{});
    }

    done();
}

export fn doubleFaultHandler() callconv(.Interrupt) noreturn {
    log.info("Double Fault!\n", .{});
    done();
}

export fn timer_handler() callconv(.Interrupt) void {
    log.info("timer!\n", .{});
    apic.write_eoi(0);
}

export fn spurious_interrupt_handler() callconv(.Interrupt) void {
    log.info("spurious interrupt!\n", .{});
}

fn setIdtEntries() void {
    var breakpoint_entry: IdtEntry = .{
        .segment_selector = gdt.kernel_code_segment_selector,
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 3,
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

    var timer_entry: IdtEntry = .{
        .segment_selector = gdt.kernel_code_segment_selector,
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    timer_entry.setOffset(@intFromPtr(&timer_handler));

    var spurious_interrupt_entry: IdtEntry = .{
        .segment_selector = gdt.kernel_code_segment_selector,
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    spurious_interrupt_entry.setOffset(@intFromPtr(&spurious_interrupt_handler));

    IDT[3] = breakpoint_entry;
    IDT[8] = double_fault_entry;
    IDT[0xD] = genprot_entry;
    IDT[0xE] = page_fault_entry;
    IDT[0x31] = timer_entry;
    IDT[0xFF] = spurious_interrupt_entry;
}

pub fn loadIdt() void {
    setIdtEntries();
    IdtR.size = @sizeOf(@TypeOf(IDT)) - 1;
    IdtR.offset = @intFromPtr(&IDT);
    const x = @intFromPtr(&IdtR);
    lidt(x);
}

test "idt sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(PageFaultErrorCode));
}
