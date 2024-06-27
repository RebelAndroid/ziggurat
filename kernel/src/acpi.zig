pub const std = @import("std");

pub const Xsdp = extern struct {
    signature: [8]u8,
    checksum: u8,
    oemid: [6]u8,
    revision: u8,
    _1: u32,
    length: u32,
    xsdt_address: u64 align(4),
    extended_checksum: u8,
    _2: [3]u8,
};

test "acpi struct sizing" {
    try std.testing.expectEqual(36, @sizeOf(Xsdp));
}
