const limine = @import("limine");
const std = @import("std");

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

// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_revision.is_supported()) {
        done();
    }
    serial_init();

    const serial_writer: std.io.GenericWriter(Context, WriteError, serial_print) = .{
        .context = Context{},
    };
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
    const serial_writer: std.io.GenericWriter(Context, WriteError, serial_print) = .{
        .context = Context{},
    };
    const address = asm volatile (
        \\movq %CR2, %rax
        : [ret] "= {rax}" (-> usize),
    );
    try serial_writer.print("page fault! occured at address: 0x{X}\n", .{address});
}

export fn breakpoint_handler() callconv(.Interrupt) void {
    const serial_writer: std.io.GenericWriter(Context, WriteError, serial_print) = .{
        .context = Context{},
    };
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

const FrameAllocator = struct {
    front: u64 = 0,
    hhdm_offset: u64,
    fn free_frames(self: *FrameAllocator, start: u64, size: u64) void {
        if (self.front == 0) {
            // linked list is empty
            self.front = start;
            const node = FrameAllocatorNode{
                .size = size,
                .next = 0,
            };
            const node_ptr: *FrameAllocatorNode = @ptrFromInt(start + self.hhdm_offset);
            node_ptr.* = node;
        } else {
            const node = FrameAllocatorNode{
                .size = size,
                .next = self.front,
            };
            const node_ptr: *FrameAllocatorNode = @ptrFromInt(start + self.hhdm_offset);
            node_ptr.* = node;
            // add the new node to the front of the list
            self.front = start;
        }
    }
    fn allocate_frame(self: *FrameAllocator) u64 {
        if (self.front == 0) {
            // linked list is empty, big sad
            return 0; // TODO: actual errors?
        }
        const node_ptr: *FrameAllocatorNode = @ptrFromInt(self.front + self.hhdm_offset);
        node_ptr.size -= 1;
        // return the last frame in this node
        const out = self.front + 0x1000 * node_ptr.size;
        if (node_ptr.size == 0) {
            // if the node has no more pages left, remove it
            self.front = node_ptr.next;
        }
        return out;
    }
};
const FrameAllocatorNode = packed struct {
    size: u64 = 0,
    next: u64 = 0,
};

const CR3 = packed struct {
    _1: u3,
    pwt: u1,
    pcd: u1,
    _2: u7,
    pml4: u52,
};

extern fn get_cr3() callconv(.C) u64;
extern fn set_cr3(u64) callconv(.C) void;
comptime {
    asm (
        \\.globl get_cr3
        \\.type get_cr3 @function
        \\get_cr3:
        \\  movq %cr3, %rax
        \\  retq
        \\.globl set_cr3
        \\.type set_cr3 @function
        \\set_cr3:
        \\  movq %rdi, %cr3
        \\  retq
    );
}

/// packed struct representing CR4 values
/// more info at Intel Software Developer's Manual Vol. 3A 2-17
const CR4 = packed struct {
    /// Virtual-8086 Mode Extensions: enables interrupt and exceptions handling extensions in virtual-8086 mode
    vme: bool,
    /// Protected-Mode Virtual Interrupts: enables virtual interrupt flag in protected mode
    pvi: bool,
    /// Time Stamp Disable: restricts execution of RDTSC instruction to ring 0 (also applies to RDTSCP if available)
    tsd: bool,
    /// Debug Extensions: ?
    de: bool,
    /// Page Size Extensions: enables 4MB pages with 32 bit paging
    pse: bool,
    /// Physical Address Extension: Allows paging for physical addresses larger than 32 bits, must be set for long mode paging (IA-32e)
    pae: bool,
    /// Machine-Check Enable: enables the machine-check exception
    mce: bool,
    /// Page Global Enable: enables global pages
    pge: bool,
    /// Performance-Monitoring Counter Enable: allows RDPMC instruction to execute at any privilege level (only in ring 0 if clear)
    pce: bool,
    /// Operating System Support For FXSAVE and FXRSTOR instructions: enables FXSAVE and FXSTOR,
    /// allows the processor to execute most SSE/SSE2/SSE3/SSSE3/SSE4 (others always available)
    osfxsr: bool,
    /// Operating System Support for Unmasked SIMD Floating-Point Exceptions: indicates support for handling unmasked SIMD floating-point exceptions
    osxmmexcpt: bool,
    /// User-Mode Instruction Prevention: prevents rings > 0 from executing SGDT, SIDT, SMSW, and STR
    umip: bool,
    /// 57-bit linear addresses: enables 5-level paging (57 bit virtual addresses)
    la57: bool,
    /// VMX-Enable: enables VMX
    vmxe: bool,
    /// SMX-Enable: enables SMX
    smxe: bool,
    _2: bool,
    /// FSGSBASE-Enable: enables RDFSBASE, RDGSBASE, WRFSBASE, and WRGSBASE
    fsgsbase: bool,
    /// PCID-Enable: enables process-context identifiers
    pcide: bool,
    /// Enables XSAVE, XRSTOR, XGETBV, and XSETBV
    osxsave: bool,
    /// Key-Locker-Enable: enables LOADIWKEY
    kl: bool,
    /// SMEP-Enable: enables supervisor-mode execution prevention
    smep: bool,
    /// SMAP-Enable: enables supervisor-mode access prevention
    smap: bool,
    /// Enable protection keys for user-mode pages: ?
    pke: bool,
    /// Control-Flow Enforcement Technology: enables CET when set
    cet: bool,
    /// Enable protection keys for supervisor-mode pages
    pks: bool,
    /// User Interrupts Enable: enables user interrupts
    uintr: bool,
    _4: u38,
};

extern fn get_cr4() callconv(.C) u64;
extern fn set_cr4(u64) callconv(.C) void;
comptime {
    asm (
        \\.globl get_cr4
        \\.type get_cr4 @function
        \\get_cr4:
        \\  movq %cr4, %rax
        \\  retq
        \\.globl set_cr4
        \\.type set_cr4 @function
        \\set_cr4:
        \\  movq %rdi, %cr4
        \\  retq
    );
}

fn main(hhdm_offset: u64, memory_map_entries: []*limine.MemoryMapEntry, rdsp_location: *anyopaque) noreturn {
    const serial_writer: std.io.GenericWriter(Context, WriteError, serial_print) = .{
        .context = Context{},
    };
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

    var frame_allocator = FrameAllocator{
        .hhdm_offset = hhdm_offset,
    };

    for (memory_map_entries) |e| {
        if (e.kind != limine.MemoryMapEntryType.usable) {
            continue;
        }
        frame_allocator.free_frames(e.base, e.length / 0x1000);
    }

    const cr3: CR3 = @bitCast(get_cr3());
    try serial_writer.print("cr3: {X}\n", .{cr3.pml4 << 12});

    const cr4: CR4 = @bitCast(get_cr4());
    try serial_writer.print("cr4: {}\n", .{cr4});

    try serial_writer.print("done", .{});

    done();
}
