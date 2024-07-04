const std = @import("std");

const GlyphBuilder = struct {
    xoffset: ?i8 = null,
    yoffset: ?i8 = null,
    width: ?u8 = null,
    height: ?u8 = null,
    encoding: ?u64 = null,
    xstride: ?u8 = null,
    ystride: ?u8 = null,
    bitmap: std.ArrayList(u8),
    pub fn add_line(self: *GlyphBuilder, line: []const u8) void {
        if (is_prefix(line, "ENCODING")) {
            if (self.encoding) |_| {
                std.debug.panic("character encoding defined twice!", .{});
            }
            const parse = parse_first_int(line);
            if (parse.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.encoding = parse.value;
        } else if (is_prefix(line, "DWIDTH")) {
            const parse = parse_first_int(line);
            if (parse.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.xstride = @intCast(parse.value);
            const parse2 = parse_first_int(line[parse.end..]);
            if (parse2.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.ystride = @intCast(parse2.value);
        } else if (is_prefix(line, "BBX")) {
            const parse = parse_first_int(line);
            if (parse.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.width = @intCast(parse.value);

            const parse2 = parse_first_int(line[parse.end..]);
            if (parse2.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.height = @intCast(parse2.value);

            const parse3 = parse_first_uint(line[(parse.end + parse2.end)..]);
            if (parse3.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.xoffset = @intCast(parse3.value);

            const parse4 = parse_first_uint(line[(parse.end + parse2.end + parse3.end)..]);
            if (parse4.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.yoffset = @intCast(parse4.value);
        } else if (is_prefix(line, "BITMAP")) {
            // TODO: ensure input is well formed
        } else if (is_prefix(line, "SWIDTH")) {
            // do nothing
        } else {
            // we are in the bitmap
            var i: u64 = 0;
            while (i < line.len - 1) : (i += 2) {
                self.bitmap.append(std.fmt.parseInt(u8, line[i..(i + 2)], 16) catch std.debug.panic("unable to parse bitmap {s}", .{line})) catch std.debug.panic("Allocator error!", .{});
            }
        }
    }

    pub fn build(self: *GlyphBuilder) Glyph {
        if (self.xoffset) |xoffset| {
            if (self.yoffset) |yoffset| {
                if (self.width) |width| {
                    if (self.height) |height| {
                        if (self.encoding) |encoding| {
                            if (self.xstride) |xstride| {
                                if (self.ystride) |ystride| {
                                    return .{
                                        .xoffset = xoffset,
                                        .yoffset = yoffset,
                                        .width = width,
                                        .height = height,
                                        .encoding = encoding,
                                        .xstride = xstride,
                                        .ystride = ystride,
                                        .bitmap = self.bitmap,
                                    };
                                }
                            }
                        }
                    }
                }
            }
        }
        std.debug.panic("attempted to create incomplete glyph", .{});
    }
};

const Glyph = struct {
    xoffset: i8,
    yoffset: i8,
    width: u8,
    height: u8,
    encoding: u64,
    xstride: u8,
    ystride: u8,
    bitmap: std.ArrayList(u8),
};

const FontBuilder = struct {
    ascent: ?u64 = null,
    descent: ?u64 = null,
    glyph_builder: ?GlyphBuilder = null,
    glyphs: std.ArrayList(Glyph),
    allocator: std.mem.Allocator,
    pub fn add_line(self: *FontBuilder, line: []const u8) void {
        if (is_prefix(line, "FONT_ASCENT")) {
            if (self.ascent) |_| {
                std.debug.panic("font ascent defined twice!", .{});
            }
            const parse = parse_first_int(line);
            if (parse.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.ascent = parse.value;
        } else if (is_prefix(line, "FONT_DESCENT")) {
            if (self.descent) |_| {
                std.debug.panic("font descent defined twice!", .{});
            }
            const parse = parse_first_int(line);
            if (parse.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.descent = parse.value;
        } else if (is_prefix(line, "STARTCHAR")) {
            if (self.glyph_builder) |_| {
                std.debug.panic("unmatched STARTCHAR", .{});
            } else {
                self.glyph_builder = .{ .bitmap = std.ArrayList(u8).init(self.allocator) };
            }
        } else if (is_prefix(line, "ENDCHAR")) {
            if (self.glyph_builder) |*glyph_builder| {
                self.glyphs.append(glyph_builder.*.build()) catch std.debug.panic("allocator error", .{});
                self.glyph_builder = null;
            } else {
                std.debug.panic("unmatched ENDCHAR", .{});
            }
        } else {
            if (self.glyph_builder) |*glyph_builder| {
                glyph_builder.*.add_line(line);
            }
        }
    }
    pub fn build(self: *FontBuilder) Font {
        if (self.ascent) |ascent| {
            if (self.descent) |descent| {
                return .{
                    .ascent = ascent,
                    .descent = descent,
                    .glyphs = self.glyphs,
                };
            }
        }
        std.debug.panic("font missing attributes", .{});
    }
};

const Font = struct {
    ascent: u64,
    descent: u64,
    glyphs: std.ArrayList(Glyph),
};

pub fn build_font(file: std.fs.File, allocator: std.mem.Allocator) ![]u8 {
    const file_reader = file.reader();

    var fontBuilder: FontBuilder = .{
        .glyphs = std.ArrayList(Glyph).init(allocator),
        .allocator = allocator,
    };

    while (file_reader.readUntilDelimiterAlloc(allocator, '\n', 1024)) |line| {
        fontBuilder.add_line(line);
    } else |e| {
        if (e != error.EndOfStream) {
            std.debug.print("error: {}", .{e});
        }
    }
    const font = fontBuilder.build();
    return serialize_font(font, allocator);
}

const PackedGlyph = extern struct {
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

pub fn serialize_font(font: Font, allocator: std.mem.Allocator) ![]u8 {
    var glyphs = std.ArrayList(PackedGlyph).init(allocator);
    var bitmaps = std.ArrayList(u8).init(allocator);
    for (font.glyphs.items) |glyph| {
        try glyphs.append(.{
            .bitmap_index = bitmaps.items.len,
            .width = glyph.width,
            .height = glyph.height,
            .xoffset = glyph.xoffset,
            .yoffset = glyph.yoffset,
            .xstride = glyph.xstride,
            .ystride = glyph.ystride,
        });
        try bitmaps.appendSlice(try pack_bitmap(glyph.bitmap.items, glyph.width, glyph.height, allocator));
    }
    var header = std.ArrayList(u8).init(allocator);
    try header.appendSlice(@as([*]const u8, @ptrCast(&font.ascent))[0..8]);
    try header.appendSlice(@as([*]const u8, @ptrCast(&font.descent))[0..8]);

    try header.appendSlice(@as([*]const u8, @ptrCast(&glyphs.items.len))[0..8]);
    try header.appendSlice(@as([*]const u8, @ptrCast(&bitmaps.items.len))[0..8]);

    std.debug.print("glyphs: {} bitmap size: {}\n", .{ glyphs.items.len, bitmaps.items.len });

    var data = std.ArrayList(u8).init(allocator);
    try data.appendSlice(header.items);
    std.debug.print("glyph offset: {} ", .{data.items.len});
    try data.appendSlice(std.mem.sliceAsBytes(glyphs.items));
    std.debug.print("bitmaps offset: {}\n", .{data.items.len});
    try data.appendSlice(bitmaps.items);

    return data.items;
}

pub fn pack_bitmap(bitmap: []u8, width: u8, height: u8, allocator: std.mem.Allocator) ![]u8 {
    var bitset = try std.bit_set.DynamicBitSet.initEmpty(allocator, width * height);
    var y: u64 = 0;
    var x: u64 = 0;
    var i: u64 = 0;
    while (y < height) : (y += 1) {
        x = 0;
        while (x < width) : (x += 1) {
            const bytes_per_line = std.math.divCeil(u64, width, 8) catch unreachable;
            const byte = bitmap[y * bytes_per_line + (x / 8)];
            const bit = ((byte >> @truncate(7 - @rem(x, 8))) & 0x1) == 1;
            if (bit) {
                bitset.set(i);
            }
            i += 1;
        }
    }
    const byte_size = std.math.divCeil(u64, width * height, 8) catch unreachable;
    var packed_bitmap = std.ArrayList(u8).init(allocator);
    try packed_bitmap.appendNTimes(0, byte_size);
    var j: u64 = 0;
    while (j < bitset.capacity()) : (j += 1) {
        var bit: u8 = 0;
        if (bitset.isSet(j)) {
            bit = 1;
        }
        packed_bitmap.items[j / 8] |= (bit << @truncate(@rem(j, 8)));
    }

    return packed_bitmap.items;
}

pub fn is_prefix(str: []const u8, prefix: []const u8) bool {
    if (prefix.len > str.len) {
        return false;
    }
    var i: usize = 0;
    while (i < prefix.len) : ({
        i += 1;
    }) {
        if (str[i] != prefix[i]) {
            return false;
        }
    }
    return true;
}

const FirstInt = struct {
    value: u64,
    end: u64,
};

pub fn parse_first_int(str: []const u8) FirstInt {
    var i: usize = 0;
    var start: ?usize = null;
    while (i < str.len) : (i += 1) {
        if (start) |s| {
            if (!std.ascii.isDigit(str[i])) {
                const result: u64 = std.fmt.parseInt(u64, str[s..i], 10) catch return .{ .value = 0, .end = 0 };
                return .{ .value = result, .end = i };
            }
        } else if (std.ascii.isDigit(str[i])) {
            start = i;
        }
    }
    if (start) |s| {
        const result: u64 = std.fmt.parseInt(u64, str[s..i], 10) catch return .{ .value = 0, .end = 0 };
        return .{ .value = result, .end = i };
    }
    return .{ .value = 0, .end = 0 };
}

const FirstUint = struct {
    value: i64,
    end: u64,
};

pub fn parse_first_uint(str: []const u8) FirstUint {
    var i: usize = 0;
    var start: ?usize = null;
    while (i < str.len) : (i += 1) {
        if (start) |s| {
            if (!std.ascii.isDigit(str[i]) and str[i] != '-') {
                const result: i64 = std.fmt.parseInt(i64, str[s..i], 10) catch return .{ .value = 0, .end = 0 };
                return .{ .value = result, .end = i };
            }
        } else if (std.ascii.isDigit(str[i]) or str[i] == '-') {
            start = i;
        }
    }
    if (start) |s| {
        const result: i64 = std.fmt.parseInt(i64, str[s..i], 10) catch return .{ .value = 0, .end = 0 };
        return .{ .value = result, .end = i };
    }
    return .{ .value = 0, .end = 0 };
}
