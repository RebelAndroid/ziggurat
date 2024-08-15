const std = @import("std");

const Context = struct {};
const WriteError = error{};

const serial_writer: std.io.GenericWriter(Context, WriteError, serial_print) = .{
    .context = Context{},
};

pub fn serial_log(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const scope_name = @tagName(scope);
    const level_name = level.asText();
    const b = switch (scope) {
        // remember that log levels are sorted backwards, ie the smallest int value is err
        .registers => @intFromEnum(level) <= @intFromEnum(std.log.Level.info),
        .main => @intFromEnum(level) <= @intFromEnum(std.log.Level.debug),
        .elf => @intFromEnum(level) <= @intFromEnum(std.log.Level.warn),
        else => true,
    };
    // const b = true;
    if (b) {
        try serial_writer.print("[{s}] ({s}): ", .{ level_name, scope_name });
        try serial_writer.print(format, args);
    }
}

fn serial_print(_: Context, text: []const u8) WriteError!usize {
    for (text) |b| {
        out_byte(0x03F8, b);
    }
    return text.len;
}

fn out_byte(port: u16, data: u8) void {
    _ = asm volatile ("outb %al, %dx"
        : [ret] "= {rax}" (-> usize),
        : [port] "{dx}" (port),
          [data] "{al}" (data),
    );
}

pub fn init() void {
    const port: u16 = 0x3f8; // base IO port for the serial port
    out_byte(port + 1, 0x00); // disable interrupts
    out_byte(port + 3, 0x80); // set DLAB
    out_byte(port + 0, 0x03); // set divisor (low byte)
    out_byte(port + 1, 0x00); // set divisor (high byte)
    out_byte(port + 3, 0x03); // clear DLAB, set character length to 8 bits, 1 stop bit, no parity bits
    out_byte(port + 2, 0xC7); // enable and clear FIFO's, set interrupt trigger to highest value (this is not used)
    out_byte(port + 4, 0x0F); // set DTR, RTS, OUT1, and OUT2
}
