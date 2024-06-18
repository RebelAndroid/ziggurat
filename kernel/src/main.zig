const limine = @import("limine");
const std = @import("std");
const pmm = @import("pmm.zig");
const reg = @import("x64/registers.zig");
const paging = @import("x64/page_table.zig");
const cpuid = @import("x64/cpuid.zig");
const idt = @import("x64/idt.zig");
const gdt = @import("x64/gdt.zig");

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

pub const std_options = .{
    .log_level = .info,
    .logFn = serial_log,
};

pub fn serial_log(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const scope_name = @tagName(scope);
    const level_name = level.asText();
    try serial_writer.print("[{s}] ({s}): ", .{ level_name, scope_name });
    try serial_writer.print(format, args);
}

const main_log = std.log.scoped(.main);

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

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    main_log.err("panic: {s}\n", .{message});
    done();
}

const serial_writer: std.io.GenericWriter(Context, WriteError, serial_print) = .{
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
            main_log.err("frame buffer response had no framebuffers", .{});
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
    main_log.err("page fault! occured at address: 0x{X}\n", .{address});
}

export fn breakpoint_handler() callconv(.Interrupt) void {
    main_log.info("breakpoint!\n", .{});
}

fn main(hhdm_offset: u64, memory_map_entries: []*limine.MemoryMapEntry, rdsp_location: *anyopaque) noreturn {
    main_log.info("rdsp: 0x{X}\n", .{@intFromPtr(rdsp_location) - hhdm_offset});

    var frame_allocator = pmm.FrameAllocator{
        .hhdm_offset = hhdm_offset,
    };

    for (memory_map_entries) |e| {
        if (e.kind != limine.MemoryMapEntryType.usable) {
            continue;
        }
        frame_allocator.free_frames(e.base, e.length / 0x1000);
    }

    main_log.info("vendor string: {s}\n", .{cpuid.get_vendor_string()});

    var current_gdtr: gdt.GdtDescriptor = std.mem.zeroes(gdt.GdtDescriptor);
    gdt.sgdt(&current_gdtr);
    main_log.info("current gdtr: size: 0x{X}, offset: 0x{X}\n", .{ current_gdtr.size, current_gdtr.offset });
    const gdt_entries = current_gdtr.get_entries();
    for (gdt_entries) |e| {
        main_log.info("gdt entry: base: {X}, limit: {X}, size: {}, executable: {}, long mode code: {}, type: {}, DPL: {}\n", .{ e.get_base(), e.get_limit(), e.size, e.executable, e.long_mode_code, e.descriptor_type, e.descriptor_privilege_level });
    }

    // The first gdt entry is always a null descriptor
    gdt.Gdt[0] = std.mem.zeroes(gdt.GdtEntry);
    // The second entry will be the code segment
    gdt.Gdt[1] = gdt.GdtEntry{
        .executable = true,
        .rw = false,
        .descriptor_privilege_level = 0,
        .direction_conforming = false,
        .granularity = false,
        .size = false,
        .long_mode_code = true,
    };
    // The third entry will be the data segment
    gdt.Gdt[2] = gdt.GdtEntry{
        .executable = false,
        .rw = true,
        .descriptor_privilege_level = 0,
        .direction_conforming = false,
        .granularity = false,
        .size = false,
        .long_mode_code = false,
    };
    gdt.load_gdt();

    var breakpoint_entry: idt.IdtEntry = .{
        .segment_selector = (1 << 3),
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    breakpoint_entry.setOffset(@intFromPtr(&breakpoint_handler));

    var page_fault_entry: idt.IdtEntry = .{
        .segment_selector = (1 << 3),
        .ist = 0,
        .gate_type = 0xF,
        .dpl = 0,
    };
    page_fault_entry.setOffset(@intFromPtr(&page_fault_handler));

    idt.IDT[3] = breakpoint_entry;
    idt.IDT[0xE] = page_fault_entry;

    idt.load_idt();

    breakpoint();

    main_log.info("done\n", .{});

    done();
}
