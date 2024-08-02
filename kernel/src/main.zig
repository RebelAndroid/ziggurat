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
const elf = @import("elf.zig");

// The Limine requests can be placed anywhere, but it is important that
// the compiler does not optimise them away, so, usually, they should
// be made volatile or equivalent. In Zig, `export var` is what we use.
pub export var framebuffer_request: limine.FramebufferRequest = .{};
pub export var hhdm_request: limine.HhdmRequest = .{};
pub export var memory_map_request: limine.MemoryMapRequest = .{};
pub export var rsdp_request: limine.RsdpRequest = .{};
pub export var stack_size_request: limine.StackSizeRequest = .{ .stack_size = 4096 * 16 };

pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };

const init_file align(8) = @embedFile("init").*;

pub const std_options = .{
    .log_level = .info,
    .logFn = serial_log.serial_log,
};

const log = std.log.scoped(.main);

inline fn done() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

inline fn breakpoint() void {
    asm volatile ("int $3");
}

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    log.err("panic: {s}\n", .{message});
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
            log.err("frame buffer response had no framebuffers", .{});
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

    gdt.loadGdt();

    idt.loadIdt();

    // enable system call extensions, we will use syscall/sysret to handle system calls and will also enter user mode using sysret
    var efer: msr.Efer = msr.readEfer();
    efer.system_call_extensions = true;
    msr.writeEfer(efer);

    msr.writeStar(msr.Star{
        .kernel_cs_selector = gdt.kernel_code_segment_selector,
        .user_cs_selector = gdt.user_code_segment_selector,
    });

    const cr3 = reg.get_cr3();
    const new_cr3 = cr3.copy(hhdm_offset, &frame_allocator);
    log.info("new cr3: {}\n", .{new_cr3});
    reg.set_cr3(@bitCast(new_cr3));

    new_cr3.map(paging.Page{ .four_kb = @bitCast(@as(u64, 0x100000)) }, frame_allocator.allocate_frame(), hhdm_offset, &frame_allocator, reg.PageFlags{ .user = false, .execute = true, .write = true }) catch unreachable;
    const p = new_cr3.translate(@bitCast(@as(u64, 0x100000)), hhdm_offset);
    log.info("p: {}\n", .{p});
    // const test_ptr: *const u8 = @ptrFromInt(0x100000);
    // log.info("ptr: {}", .{test_ptr.*});

    // elf.loadElf(&init_file, new_cr3, hhdm_offset, &frame_allocator);

    log.info("done\n", .{});
    acpi.apica_test();
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

pub fn user_mode() noreturn {
    // asm volatile ("int $3");
    while (true) {
        asm volatile ("hlt");
    }
}
