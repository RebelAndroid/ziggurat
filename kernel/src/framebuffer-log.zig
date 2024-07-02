const std = @import("std");

const log = std.log.scoped(.framebuffer);

const font_file align(8) = @embedFile("cozette-packed.bin").*;
pub const FontHeader = extern struct {
    ascent: u64,
    descent: u64,
    glyph_count: u64,
    bitmaps_size: u64,
};

pub const PackedGlyph = extern struct {
    bitmap_index: u64,
    width: u8,
    height: u8,
    xoffset: u8,
    yoffset: u8,
    xstride: u8,
    ystride: u8,
    /// reserved for future use
    _1: u16 = 0,
};

pub const Context = struct {
    glyphs: []PackedGlyph = &[_]PackedGlyph{},
    bitmaps: []u8 = &[_]u8{},
    header: FontHeader = .{
        .ascent = 0,
        .bitmaps_size = 0,
        .descent = 0,
        .glyph_count = 0,
    },
    x: u64 = 0,
    y: u64 = 0,
    framebuffer: [*]u8 = &[_]u8{},
    stride: u64 = 0,
};
pub const WriteError = error{};
pub var framebuffer_writer: std.io.GenericWriter(Context, WriteError, framebuffer_print) = .{
    .context = Context{},
};

pub const Color = struct { b: u8, g: u8, r: u8 };
pub const white: Color = .{ .r = 255, .g = 255, .b = 255 };
pub const red: Color = .{ .r = 255, .g = 0, .b = 0 };
pub const blue: Color = .{ .r = 0, .g = 0, .b = 255 };
pub const green: Color = .{ .r = 0, .g = 255, .b = 0 };

pub var context: Context = .{};

pub fn init(framebuffer: [*]u8, stride: u64) void {
    const header: *const FontHeader = @alignCast(@ptrCast(&font_file));
    const glyph_front: [*]PackedGlyph = @ptrFromInt(@intFromPtr(&font_file) + @sizeOf(FontHeader));
    const glyphs: []PackedGlyph = glyph_front[0..header.glyph_count];
    const bitmaps_front: [*]u8 = @ptrFromInt(@intFromPtr(glyph_front) + @sizeOf(PackedGlyph) * header.glyph_count);
    // log.info("glyph front: {*}, bitmaps front: {*}\n", .{ glyph_front, bitmaps_front });
    const bitmaps: []u8 = bitmaps_front[0..header.bitmaps_size];
    context = .{
        .glyphs = glyphs,
        .bitmaps = bitmaps,
        .header = header.*,
        .x = 4,
        .y = header.ascent + 4,
        .framebuffer = framebuffer,
        .stride = stride,
    };
}

pub fn framebuffer_print(_: Context, text: []const u8) WriteError!usize {
    for (text) |char| {
        const glyph = context.glyphs[char];
        const bitmap_size = std.math.divCeil(u64, @as(u64, glyph.width) * @as(u64, glyph.height), 8) catch unreachable;
        const bitmap = context.bitmaps[glyph.bitmap_index..(glyph.bitmap_index + bitmap_size)];

        const x: u64 = context.x + glyph.xoffset;
        const y: u64 = context.y + glyph.yoffset;
        draw_masked_rect(
            context.framebuffer,
            context.stride,
            x,
            y,
            glyph.width,
            glyph.height,
            bitmap,
            blue,
        );
        context.x += glyph.xstride;
        context.y += glyph.ystride;
    }
    return text.len;
}

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

pub fn draw_masked_rect(framebuffer: [*]u8, stride: u64, x: u64, y: u64, width: u64, height: u64, mask: []const u8, color: Color) void {
    var xi: u64 = 0;
    var yi: u64 = 0;
    var i: u64 = 4 * x + y * stride;
    var maski: u64 = 0;
    while (yi < height) : (yi += 1) {
        xi = 0;
        while (xi < width) : (xi += 1) {
            if ((mask[maski / 8] >> @intCast(maski % 8) & 0x1) != 0) {
                framebuffer[i + 0] = color.b;
                framebuffer[i + 1] = color.g;
                framebuffer[i + 2] = color.r;
            } else {}
            i += 4;
            maski += 1;
        }
        i += (stride - 4 * width);
    }
}
