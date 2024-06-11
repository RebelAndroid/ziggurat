const limine = @import("limine");
const std = @import("std");
const pmm = @import("pmm.zig");
const reg = @import("x64/registers.zig");
const paging = @import("x64/page_table.zig");

// The Limine requests can be placed anywhere, but it is important that
// the compiler does not optimise them away, so, usually, they should
// be made volatile or equivalent. In Zig, `export var` is what we use.
pub export var framebuffer_request: limine.FramebufferRequest = .{};
pub export var hhdm_request: limine.HhdmRequest = .{};
pub export var memory_map_request: limine.MemoryMapRequest = .{};
pub export var rdsp_request: limine.RsdpRequest = .{};

// Set the base revision to 2, this is recommended as this is the latest
// base revision described by the Limine boot protocol specification.
// See specification for further info.
pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };

inline fn done() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

fn out_byte(port: u16, data: u8) void {
    _ = asm volatile ("outb %al, %dx"
        : [ret] "= {rax}" (-> usize),
        : [port] "{dx}" (port),
          [data] "{al}" (data),
    );
}

inline fn breakpoint() void {
    asm volatile ("int $3");
}

fn serial_init() void {
    const port: u16 = 0x3f8; // base IO port for the serial port
    out_byte(port + 1, 0x00); // disable interrupts
    out_byte(port + 3, 0x80); // set DLAB
    out_byte(port + 0, 0x03); // set divisor (low byte)
    out_byte(port + 1, 0x00); // set divisor (high byte)
    out_byte(port + 3, 0x03); // clear DLAB, set character length to 8 bits, 1 stop bit, no parity bits
    out_byte(port + 2, 0xC7); // enable and clear FIFO's, set interrupt trigger to highest value (this is not used)
    out_byte(port + 4, 0x0F); // set DTR, RTS, OUT1, and OUT2
}

const Context = struct {};
const WriteError = error{};

fn serial_print(_: Context, text: []const u8) WriteError!usize {
    for (text) |b| {
        out_byte(0x03F8, b);
    }
    return text.len;
}

const IdtEntry = packed struct {
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
    fn setOffset(self: *IdtEntry, offset: u64) void {
        self.offset1 = @truncate(offset);
        self.offset2 = @truncate(offset >> 16);
    }
    fn getOffset(self: IdtEntry) u64 {
        return (@as(u64, self.offset2) << 16) | self.offset1;
    }
};

var IDT: [256]IdtEntry = std.mem.zeroes([256]IdtEntry);

const IdtDescriptor = packed struct {
    size: u16,
    offset: u64,
};

var IdtR: IdtDescriptor = std.mem.zeroes(IdtDescriptor);

pub const serial_writer: std.io.GenericWriter(Context, WriteError, serial_print) = .{
    .context = Context{},
};

// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_revision.is_supported()) {
        done();
    }
    serial_init();

    // Ensure we got a framebuffer.
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            _ = try serial_writer.write("framebuffer response had no framebuffers\n");
            done();
        }

        // Get the first framebuffer's information.
        //const framebuffer = framebuffer_response.framebuffers()[0];

        if (hhdm_request.response) |hhdm_response| {
            if (memory_map_request.response) |memory_map_response| {
                if (rdsp_request.response) |rdsp_response| {
                    const entries = memory_map_response.entries_ptr[0..memory_map_response.entry_count];
                    main(hhdm_response.offset, entries, rdsp_response.address);
                }
            }
        }
    }

    // We're done, just hang...
    done();
}

export fn page_fault_handler() callconv(.Interrupt) void {
    const address = asm volatile (
        \\movq %CR2, %rax
        : [ret] "= {rax}" (-> usize),
    );
    try serial_writer.print("page fault! occured at address: 0x{X}\n", .{address});
}

export fn breakpoint_handler() callconv(.Interrupt) void {
    try serial_writer.print("breakpoint!\n", .{});
}

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

fn main(hhdm_offset: u64, memory_map_entries: []*limine.MemoryMapEntry, rdsp_location: *anyopaque) noreturn {
    try serial_writer.print("hhdm offset: 0x{X}\n", .{hhdm_offset});
    for (memory_map_entries) |e| {
        try serial_writer.print("base: 0x{X}, length: 0x{X}, kind: {}\n", .{ e.base, e.length, e.kind });
    }
    try serial_writer.print("rdsp: 0x{X}\n", .{@intFromPtr(rdsp_location) - hhdm_offset});

    var breakpoint_entry: IdtEntry = .{
        .segment_selector = (5 << 3),
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    breakpoint_entry.setOffset(@intFromPtr(&breakpoint_handler));

    var page_fault_entry: IdtEntry = .{
        .segment_selector = (5 << 3),
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    page_fault_entry.setOffset(@intFromPtr(&page_fault_handler));

    IDT[3] = breakpoint_entry;
    IDT[0xE] = page_fault_entry;

    IdtR.size = @sizeOf(@TypeOf(IDT)) - 1;
    IdtR.offset = @intFromPtr(&IDT);

    const x = @intFromPtr(&IdtR);
    lidt(x);

    breakpoint();

    var frame_allocator = pmm.FrameAllocator{
        .hhdm_offset = hhdm_offset,
    };

    for (memory_map_entries) |e| {
        if (e.kind != limine.MemoryMapEntryType.usable) {
            continue;
        }
        frame_allocator.free_frames(e.base, e.length / 0x1000);
    }

    const cr3: reg.CR3 = reg.get_cr3();
    try serial_writer.print("PML4 physical address: {X}\n", .{cr3.get_pml4()});

    // const page = paging.Page{
    //     .four_kb = @bitCast(hhdm_offset - 0x8000),
    // };

    // const result = cr3.map(page, 0x1000, hhdm_offset, &frame_allocator);
    // try serial_writer.print("result: {!}\n", .{result});

    const p = cr3.translate(@bitCast(hhdm_offset + 0x1000), hhdm_offset);
    try serial_writer.print("physical address: 0x{X}\n", .{p});

    const page2 = paging.Page{
        .four_kb = @bitCast(hhdm_offset + 0x1000),
    };

    const result2 = cr3.map(page2, 0x2000, hhdm_offset, &frame_allocator);
    try serial_writer.print("result: {!}\n", .{result2});

    const p2 = cr3.translate(@bitCast(hhdm_offset + 0x1000), hhdm_offset);
    try serial_writer.print("physical address: 0x{X}\n", .{p2});

    try serial_writer.print("done", .{});

    done();
}
