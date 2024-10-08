const std = @import("std");
const lock = @import("lock.zig");

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
    xoffset: i8,
    yoffset: i8,
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
    width: u64 = 0,
    height: u64 = 0,
    lock: lock.Lock = .{},
};

pub const WriteError = error{};
pub var framebuffer_writer: std.io.GenericWriter(*Context, WriteError, framebuffer_print) = .{
    .context = &global_context,
};

pub const Color = struct { b: u8, g: u8, r: u8 };
pub const white: Color = .{ .r = 255, .g = 255, .b = 255 };
pub const red: Color = .{ .r = 255, .g = 0, .b = 0 };
pub const blue: Color = .{ .r = 0, .g = 0, .b = 255 };
pub const green: Color = .{ .r = 0, .g = 255, .b = 0 };
pub const black: Color = .{ .r = 0, .g = 0, .b = 0 };

var global_context: Context = .{};

pub fn framebuffer_log(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const scope_name = @tagName(scope);
    const level_name = level.asText();
    global_context.lock.lock();
    try framebuffer_writer.print("[{s}] ({s}): ", .{ level_name, scope_name });
    try framebuffer_writer.print(format, args);
    global_context.lock.unlock();
}

pub fn init(framebuffer: [*]u8, stride: u64, width: u64, height: u64) void {
    const header: *const FontHeader = @alignCast(@ptrCast(&font_file));
    const glyph_front: [*]PackedGlyph = @ptrFromInt(@intFromPtr(&font_file) + @sizeOf(FontHeader));
    const glyphs: []PackedGlyph = glyph_front[0..header.glyph_count];
    const bitmaps_front: [*]u8 = @ptrFromInt(@intFromPtr(glyph_front) + @sizeOf(PackedGlyph) * header.glyph_count);
    const bitmaps: []u8 = bitmaps_front[0..header.bitmaps_size];
    global_context = .{
        .glyphs = glyphs,
        .bitmaps = bitmaps,
        .header = header.*,
        .x = 4,
        .y = header.ascent + 4,
        .framebuffer = framebuffer,
        .stride = stride,
        .width = width,
        .height = height,
    };
    // global_context.lock.lock();
}

pub fn framebuffer_print(context: *Context, text: []const u8) WriteError!usize {
    // context.lock.lock();
    // defer context.lock.unlock();
    for (text) |char| {
        if (char == '\n') {
            context.x = 4;
            context.y = context.y + context.header.ascent + context.header.descent + 4;
            continue;
        }
        const glyph = context.glyphs[char];
        const bitmap_size = std.math.divCeil(u64, @as(u64, glyph.width) * @as(u64, glyph.height), 8) catch unreachable;
        const bitmap = context.bitmaps[glyph.bitmap_index..(glyph.bitmap_index + bitmap_size)];

        var x: i64 = @as(i64, @intCast(context.x)) + @as(i64, glyph.xoffset);
        var y: i64 = @as(i64, @intCast(context.y)) - @as(i64, glyph.yoffset);
        if (x + glyph.width > context.height) {
            context.x = 4;
            context.y = context.y + context.header.ascent + context.header.descent + 4;
            x = @as(i64, @intCast(context.x)) + @as(i64, glyph.xoffset);
            y = @as(i64, @intCast(context.y)) - @as(i64, glyph.yoffset);
        }
        if (@as(u64, @intCast(y)) + context.header.descent + 4 > context.height) {
            context.x = 4;
            context.y = context.header.ascent + context.header.descent + 4;
            x = @as(i64, @intCast(context.x)) + @as(i64, glyph.xoffset);
            y = @as(i64, @intCast(context.y)) - @as(i64, glyph.yoffset);
            draw_rect(context.framebuffer, context.stride, 0, 0, context.width, context.height, black);
        }
        draw_masked_rect(
            context.framebuffer,
            context.stride,
            @intCast(x),
            @intCast(y - glyph.height),
            glyph.width,
            glyph.height,
            bitmap,
            white,
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
            }
            i += 4;
            maski += 1;
        }
        i += (stride - 4 * width);
    }
}
