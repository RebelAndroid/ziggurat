const std = @import("std");

const GlyphBuilder = struct {
    xoffset: ?u64 = null,
    yoffset: ?u64 = null,
    width: ?u64 = null,
    height: ?u64 = null,
    encoding: ?u64 = null,
    xstride: ?u64 = null,
    ystride: ?u64 = null,
    bitmap: std.ArrayList(u64),
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
            self.xstride = parse.value;
            const parse2 = parse_first_int(line[parse.end..]);
            if (parse2.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.ystride = parse2.value;
        } else if (is_prefix(line, "BBX")) {
            const parse = parse_first_int(line);
            if (parse.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.width = parse.value;

            const parse2 = parse_first_int(line[parse.end..]);
            if (parse2.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.height = parse2.value;

            const parse3 = parse_first_int(line[(parse.end + parse2.end)..]);
            if (parse3.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.xoffset = parse3.value;

            const parse4 = parse_first_int(line[(parse.end + parse2.end + parse3.end)..]);
            if (parse4.end == 0) {
                std.debug.panic("unable to parse int on line: {s}", .{line});
            }
            self.yoffset = parse4.value;
        } else if (is_prefix(line, "BITMAP")) {
            // TODO: ensure input is well formed
        } else if (is_prefix(line, "SWIDTH")) {
            // do nothing
        } else {
            // we are in the bitmap
            self.bitmap.append(std.fmt.parseInt(u64, line, 16) catch std.debug.panic("unable to parse bitmap", .{})) catch std.debug.panic("Allocator error!", .{});
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
                                    if (self.bitmap.items.len != height) {
                                        std.debug.panic("incomplete bitmap", .{});
                                    }
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
    xoffset: u64,
    yoffset: u64,
    width: u64,
    height: u64,
    encoding: u64,
    xstride: u64,
    ystride: u64,
    bitmap: std.ArrayList(u64),
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
                self.glyph_builder = .{ .bitmap = std.ArrayList(u64).init(self.allocator) };
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

pub fn build_font() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const file_handle = std.fs.cwd().openFile("../cozette.bdf", .{}) catch std.debug.panic("oof", .{});
    const file_reader = file_handle.reader();

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
    std.debug.print("font chars: {}\n", .{font.glyphs.items.len});
    std.debug.print("A: {}\n", .{font.glyphs.items[65]});
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
