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
const pcie = @import("pcie.zig");
const msr = @import("x64/msr.zig");

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
    .logFn = framebuffer_log.framebuffer_log,
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
        framebuffer_log.init(framebuffer.address, framebuffer.pitch, framebuffer.width, framebuffer.height);
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

fn main(hhdm_offset: u64, memory_map_entries: []*limine.MemoryMapEntry, _: *acpi.Xsdp, _: *limine.Framebuffer) noreturn {
    var frame_allocator = pmm.FrameAllocator{
        .hhdm_offset = hhdm_offset,
    };

    for (memory_map_entries) |e| {
        if (e.kind != limine.MemoryMapEntryType.usable) {
            continue;
        }
        frame_allocator.free_frames(e.base, e.length / 0x1000);
    }

    var current_gdtr: gdt.GdtDescriptor = std.mem.zeroes(gdt.GdtDescriptor);
    gdt.sgdt(&current_gdtr);

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

    // enable system call extensions, we will use syscall/sysret to handle system calls and will also enter user mode using sysret
    var efer: msr.Efer = msr.read_efer();
    efer.system_call_extensions = true;
    msr.write_efer(efer);

    main_log.info("done\n", .{});
    done();
}

pub extern fn jump_to_user_mode(entry_point: u64, rflags: u64) callconv(.C) void;
comptime {
    asm (
        \\.globl jump_to_user_mode
        \\.type jump_to_user_mode @function
        \\jump_to_user_mode:
        \\  movq %rdi, %rcx
        \\  movq %rsi, %r11
        \\  sysretq
    );
}
