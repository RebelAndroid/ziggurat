const limine = @import("limine");
const std = @import("std");

// The Limine requests can be placed anywhere, but it is important that
// the compiler does not optimise them away, so, usually, they should
// be made volatile or equivalent. In Zig, `export var` is what we use.
pub export var framebuffer_request: limine.FramebufferRequest = .{};

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

fn serial_println(text: []const u8) void {
    for (text) |b| {
        out_byte(0x03F8, b);
    }
    out_byte(0x03F8, '\n');
}

// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_revision.is_supported()) {
        done();
    }

    // Ensure we got a framebuffer.
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            done();
        }

        // Get the first framebuffer's information.
        const framebuffer = framebuffer_response.framebuffers()[0];

        serial_init();
        serial_println("Hello world!");

        const serial_writer = std.io.GenericWriter(Context, WriteError, serial_print);

        try std.fmt.format(serial_writer, "{}", .{9});

        for (0..100) |i| {
            // Calculate the pixel offset using the framebuffer information we obtained above.
            // We skip `i` scanlines (pitch is provided in bytes) and add `i * 4` to skip `i` pixels forward.
            const pixel_offset = i * framebuffer.pitch + i * 4;

            // Write 0xFFFFFFFF to the provided pixel offset to fill it white.
            @as(*u32, @ptrCast(@alignCast(framebuffer.address + pixel_offset))).* = 0xFFFFFFFF;
        }
    }

    // We're done, just hang...
    done();
}
