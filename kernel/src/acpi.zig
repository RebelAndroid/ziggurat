pub const std = @import("std");
const acpica = @cImport(@cInclude("acpi.h"));

const log = std.log.scoped(.acpi);

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
    pub fn valid_checksum(self: *Xsdp) bool {
        return checksum_table(@ptrCast(self), self.length);
    }
    pub fn get_xsdt(self: Xsdp, hhdm_offset: u64) *Xsdt {
        return @ptrFromInt(self.xsdt_address + hhdm_offset);
    }
};

pub const SDTHeader = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oemid: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,
    pub fn valid_checksum(self: *SDTHeader) bool {
        return checksum_table(@ptrCast(self), self.length);
    }
};

pub const Xsdt = extern struct {
    header: SDTHeader,
    pub fn get_pointers(self: *Xsdt) align(4) []align(4) u64 {
        const start: [*]align(4) u64 = @ptrFromInt(@intFromPtr(self) + @sizeOf(SDTHeader));
        const length = @divExact(self.header.length - 36, 8);
        return start[0..length];
    }
    pub fn get_mcfg(self: *Xsdt, hhdm_offset: u64) ?*Mcfg {
        const pointers = self.get_pointers();
        for (pointers) |p| {
            const ptr: *SDTHeader = @ptrFromInt(p + hhdm_offset);
            if (ptr.signature[0] == 'M' and ptr.signature[1] == 'C' and ptr.signature[2] == 'F' and ptr.signature[3] == 'G') {
                return @ptrCast(ptr);
            }
        }
        return null;
    }
};

pub const Mcfg = extern struct {
    header: SDTHeader,
    _: u64 align(4),
    pub fn get_entries(self: *Mcfg) []McfgEntry {
        const start: [*]McfgEntry = @ptrFromInt(@intFromPtr(self) + @sizeOf(SDTHeader) + 8);
        const length = @divExact(self.header.length - 44, 8);
        return start[0..length];
    }
};

pub const McfgEntry = extern struct {
    base_address: u64 align(4),
    segment_group_number: u16,
    start_pci_bus_number: u8,
    end_pci_bus_number: u8,
    _: u32,
};

fn checksum_table(table: [*]u8, length: u64) bool {
    var i: u64 = 0;
    var sum: u64 = 0;
    while (i < length) : (i += 1) {
        sum += table[i];
    }
    return (sum & 0xFF) == 0;
}

pub fn apica_test() void {
    log.info("ACPICA version: {x}\n", .{acpica.ACPI_CA_VERSION});
}

test "acpi struct sizing" {
    try std.testing.expectEqual(36, @sizeOf(Xsdp));
    try std.testing.expectEqual(36, @sizeOf(SDTHeader));

    try std.testing.expectEqual(16, @sizeOf(McfgEntry));
    try std.testing.expectEqual(4, @alignOf(McfgEntry));
}
