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
const process = @import("process.zig");

// The Limine requests can be placed anywhere, but it is important that
// the compiler does not optimise them away, so, usually, they should
// be made volatile or equivalent. In Zig, `export var` is what we use.
export var framebuffer_request: limine.FramebufferRequest = .{};
export var hhdm_request: limine.HhdmRequest = .{};
export var memory_map_request: limine.MemoryMapRequest = .{};
export var rsdp_request: limine.RsdpRequest = .{};
export var stack_size_request: limine.StackSizeRequest = .{ .stack_size = 4096 * 16 };

export var base_revision: limine.BaseRevision = .{ .revision = 2 };

const init_file align(8) = @embedFile("init").*;

pub const std_options = .{
    .log_level = .debug,
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

    log.info("loading gdt\n", .{});
    gdt.loadGdt();
    log.info("loading idt\n", .{});
    idt.loadIdt();

    log.info("setting efer\n", .{});
    // enable system call extensions, we will use syscall/sysret to handle system calls and will also enter user mode using sysret
    var efer: msr.Efer = msr.readEfer();
    efer.system_call_extensions = true;
    efer.no_execute_enable = true;
    msr.writeEfer(efer);

    log.info("setting star\n", .{});
    msr.writeStar(msr.Star{
        .kernel_cs_selector = gdt.kernel_code_segment_selector,
        .user_cs_selector = gdt.user_code_segment_selector,
    });

    log.info("loading syscall handler at: 0x{x}\n", .{@intFromPtr(&syscall_wrapper)});
    msr.writeLstar(@intFromPtr(&syscall_wrapper));

    msr.writeKernelGsBase(@intFromPtr(&kernel_rsp));
    log.info("loading gs base: 0x{x}\n", .{@intFromPtr(&kernel_rsp)});

    log.info("deep copying page tables\n", .{});
    // make a deep copy of the page tables, this is necessary to free bootloader reclaimable memory
    const cr3 = reg.get_cr3();
    const new_cr3 = cr3.copy(hhdm_offset, &frame_allocator);
    reg.set_cr3(@bitCast(new_cr3));

    log.info("loading elf\n", .{});
    const entry_point = elf.loadElf(&init_file, new_cr3, hhdm_offset, &frame_allocator);

    log.info("entry point: 0x{x}\n", .{entry_point});

    log.info("creating user mode stack\n", .{});
    const user_stack = frame_allocator.allocate_frame();
    new_cr3.map(.{ .four_kb = @bitCast(@as(u64, 0x4000000)) }, user_stack, hhdm_offset, &frame_allocator, .{
        .execute = false,
        .write = true,
        .user = true,
    }) catch unreachable;

    const new_stack = frame_allocator.allocate_frame();
    kernel_rsp = new_stack + hhdm_offset;

    var init_process: process.Process = .{};
    init_process.rsp = 0x4000FF0;
    init_process.rflags = @bitCast(@as(u64, 0x202));
    init_process.rip = entry_point;
    init_process.cr3 = new_cr3;

    log.info("jumping to user mode\n", .{});
    jump_to_user_mode(&init_process);

    // acpi.apica_test();
    log.info("done\n", .{});
    done();
}

pub extern fn jump_to_user_mode(process: *const process.Process) callconv(.C) void;
comptime {
    asm (
        \\.globl jump_to_user_mode
        \\.type jump_to_user_mode @function
        \\jump_to_user_mode:
        \\  movq 144(%rdi), %rax # use rax as a temp register to load cr3
        \\  movq %rax, %cr3
        \\  movq (%rdi), %rax
        \\  movq 8(%rdi), %rbx
        \\  # can't set rcx
        \\  movq 24(%rdi), %rdx
        \\  movq 32(%rdi), %rsi
        \\  # can't set rdi yet
        \\  movq 48(%rdi), %rsp
        \\  movq 56(%rdi), %rbp
        \\  movq 64(%rdi), %r8
        \\  movq 72(%rdi), %r9
        \\  movq 80(%rdi), %r10
        \\  # can't set r11
        \\  movq 96(%rdi), %r12
        \\  movq 104(%rdi), %r13
        \\  movq 112(%rdi), %r14
        \\  movq 120(%rdi), %r15
        \\  movq 128(%rdi), %rcx
        \\  movq 136(%rdi), %r11
        \\  movq 40(%rdi), %rdi # we need to load rdi last because it is our pointer to the process struct
        \\  sysretq
    );
}

pub var kernel_rsp: u64 align(4096) = 0;

// when syscall is executed, the return address is saved into rcx and rflags is saved into r11
pub extern fn syscall_wrapper() callconv(.Naked) void;
comptime {
    asm (
        \\
        \\.globl syscall_wrapper
        \\.type syscall_wrapper @function
        \\syscall_wrapper:
        \\  cli # disable interrupts
        \\  movq %rsp, %rax # move the user stack pointer to a clobber register
        \\  swapgs # swap in the kernel's gs register (kernel thread local storage)
        \\  movq %gs:0, %rsp # load the kernel stack
        \\  pushq %rax # save the user stack
        \\  pushq %r11 # save r11 (flags)
        \\  pushq %rcx # save rcx (return address)
        \\  pushq $0 # align the stack to a 16 byte boundary
        \\  movq %r10, %rcx # move parameter 4 (r10) into rcx to satisfy C abi
        \\  call syscall_handler
        \\  popq %rcx # remove the alignment 0
        \\  popq %rcx # restore rcx (return address)
        \\  popq %r11 # restore r11 (flags)
        \\  popq %rsp # restore the user stack
        \\  movq $0, %rdi # clear clobber registers, we don't clear rax because it is the return value
        \\  movq $0, %rsi
        \\  movq $0, %rdx
        \\  movq $0, %r8
        \\  movq $0, %r9
        \\  movq $0, %r10
        \\  swapgs
        \\  sti # enable interrupts
        \\  sysretq
    );
}

pub export fn syscall_handler(rdi: u64, rsi: u64, rdx: u64, rcx: u64, r8: u64, r9: u64) callconv(.C) u64 {
    log.info("Syscall!\n rdi: {}, rsi: {}, rdx: {}, rcx: {}, r8: {}, r9: {}\n", .{ rdi, rsi, rdx, rcx, r8, r9 });
    return 0;
}
