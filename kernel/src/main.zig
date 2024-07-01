const limine = @import("limine");
const std = @import("std");
const pmm = @import("pmm.zig");
const reg = @import("x64/registers.zig");
const paging = @import("x64/page_table.zig");
const cpuid = @import("x64/cpuid.zig");
const idt = @import("x64/idt.zig");
const gdt = @import("x64/gdt.zig");
const acpi = @import("acpi.zig");
const serial_log = @import("serial-log.zig");
const framebuffer_log = @import("framebuffer-log.zig");

extern fn AcpiInitializeSubsystem() callconv(.C) void;

// The Limine requests can be placed anywhere, but it is important that
// the compiler does not optimise them away, so, usually, they should
// be made volatile or equivalent. In Zig, `export var` is what we use.
pub export var framebuffer_request: limine.FramebufferRequest = .{};
pub export var hhdm_request: limine.HhdmRequest = .{};
pub export var memory_map_request: limine.MemoryMapRequest = .{};
pub export var rsdp_request: limine.RsdpRequest = .{};

// Set the base revision to 2, this is recommended as this is the latest
// base revision described by the Limine boot protocol specification.
// See specification for further info.
pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };

pub const std_options = .{
    .log_level = .info,
    .logFn = serial_log.serial_log,
};

const main_log = std.log.scoped(.main);

inline fn done() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

inline fn breakpoint() void {
    asm volatile ("int $3");
}

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    main_log.err("panic: {s}\n", .{message});
    done();
}

// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_revision.is_supported()) {
        done();
    }
    serial_log.init();

    // Ensure we got a framebuffer.
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            main_log.err("frame buffer response had no framebuffers", .{});
            done();
        }

        // Get the first framebuffer's information.
        const framebuffer = framebuffer_response.framebuffers()[0];

        if (hhdm_request.response) |hhdm_response| {
            if (memory_map_request.response) |memory_map_response| {
                if (rsdp_request.response) |rsdp_response| {
                    const entries = memory_map_response.entries_ptr[0..memory_map_response.entry_count];
                    main(hhdm_response.offset, entries, @alignCast(@ptrCast(rsdp_response.address)), framebuffer);
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

fn main(hhdm_offset: u64, memory_map_entries: []*limine.MemoryMapEntry, xsdp: *acpi.Xsdp, framebuffer: *limine.Framebuffer) noreturn {
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

    main_log.info("xsdp location: {}\n", .{xsdp});

    main_log.info("framebuffer: {}\n", .{framebuffer});

    framebuffer_log.draw_rect(framebuffer.address, framebuffer.pitch, 0, 0, framebuffer.width, framebuffer.height, framebuffer_log.white);
    framebuffer_log.draw_rect(framebuffer.address, framebuffer.pitch, 50, 50, 50, 50, framebuffer_log.red);
    framebuffer_log.draw_rect(framebuffer.address, framebuffer.pitch, 200, 50, 50, 500, framebuffer_log.green);
    framebuffer_log.draw_rect(framebuffer.address, framebuffer.pitch, 500, 500, 100, 20, framebuffer_log.blue);

    const mask: [7]u8 = .{
        0b00111100,
        0b01000010,
        0b10000001,
        0b11111111,
        0b10000001,
        0b10000001,
        0b10000001,
    };

    framebuffer_log.draw_masked_rect(
        framebuffer.address,
        framebuffer.pitch,
        100,
        100,
        8,
        7,
        &mask,
        framebuffer_log.blue,
    );

    main_log.info("done\n", .{});
    done();
}
