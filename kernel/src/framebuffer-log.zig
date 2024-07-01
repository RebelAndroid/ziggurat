const std = @import("std");

const log = std.log.scoped(.framebuffer);

// const Context = struct {};
// const WriteError = error{};

// const framebuffer_writer: std.io.GenericWriter(Context, WriteError, serial_print) = .{
//     .context = Context{},
// };

pub const Color = struct {
    b: u8,
    g: u8,
    r: u8,
};

pub const white: Color = .{
    .r = 255,
    .g = 255,
    .b = 255,
};

pub const red: Color = .{
    .r = 255,
    .g = 0,
    .b = 0,
};

pub const blue: Color = .{
    .r = 0,
    .g = 0,
    .b = 255,
};

pub const green: Color = .{
    .r = 0,
    .g = 255,
    .b = 0,
};

pub fn draw_rect(framebuffer: [*]u8, stride: u64, x: u64, y: u64, width: u64, height: u64, color: Color) void {
    var xi: u64 = 0;
    var yi: u64 = 0;
    var i: u64 = 4 * x + y * stride;
    while (yi < height) : (yi += 1) {
        xi = 0;
        while (xi < width) : (xi += 1) {
            framebuffer[i] = color.b;
            framebuffer[i + 1] = color.g;
            framebuffer[i + 2] = color.r;
            i += 4;
        }
        i += (stride - 4 * width);
    }
}
