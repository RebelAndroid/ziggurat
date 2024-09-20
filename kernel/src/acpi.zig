pub const std = @import("std");
const acpica = @cImport(@cInclude("acpi.h"));

const log = std.log.scoped(.acpi);

pub export fn AcpiOsInitialize() acpica.ACPI_STATUS {
    log.debug("AcpiOsInitialize\n", .{});
    return 1;
}

pub export fn AcpiOsTerminate() acpica.ACPI_STATUS {
    log.debug("AcpiOsTerminate\n", .{});
    return 1;
}

pub export fn AcpiOsGetRootPointer() acpica.ACPI_PHYSICAL_ADDRESS {
    log.debug("AcpiOsGetRootPointer\n", .{});
    return 1;
}

pub export fn AcpiOsPredefinedOverride(predefined_object: *const acpica.acpi_predefined_names, new_value: *acpica.ACPI_STRING) acpica.ACPI_STATUS {
    log.debug("AcpiOsPredefinedOverride: {}, {}\n", .{ predefined_object, new_value });
    return 1;
}

pub export fn AcpiOsTableOverride(existing_table: *acpica.ACPI_TABLE_HEADER, new_table: **acpica.ACPI_TABLE_HEADER) acpica.ACPI_STATUS {
    log.debug("AcpiOsTableOverride: {}, {}\n", .{ existing_table, new_table });
    return 1;
}

pub export fn AcpiOsMapMemory(physical_address: acpica.ACPI_PHYSICAL_ADDRESS, length: acpica.ACPI_SIZE) ?*anyopaque {
    log.debug("AcpiOsMapMemory: {}, {}\n", .{ physical_address, length });
    return null;
}

pub export fn AcpiOsUnmapMemory(where: ?*anyopaque, length: acpica.ACPI_SIZE) void {
    log.debug("AcpiOsUnmapMemory: {}, {}\n", .{ where, length });
}

pub export fn AcpiOsGetPhysicalAddress(logical_address: ?*anyopaque, physical_address: *acpica.ACPI_PHYSICAL_ADDRESS) acpica.ACPI_STATUS {
    log.debug("AcpiOsGetPhysicalAddress: {}, {}\n", .{ logical_address, physical_address });
    return 1;
}

pub export fn AcpiOsAllocate(size: acpica.ACPI_SIZE) ?*anyopaque {
    log.debug("AcpiOsAllocate: {}\n", .{size});
    return null;
}

pub export fn AcpiOsFree(memory: ?*anyopaque) void {
    log.debug("AcpiOsAllocate: {}\n", .{memory});
}

pub export fn AcpiOsReadable(memory: ?*anyopaque, length: acpica.ACPI_SIZE) bool {
    log.debug("AcpiOsReadable: {}, {}\n", .{ memory, length });
    return false;
}

pub export fn AcpiOsWritable(memory: ?*anyopaque, length: acpica.ACPI_SIZE) bool {
    log.debug("AcpiOsWritable: {}, {}\n", .{ memory, length });
    return false;
}

pub export fn AcpiOsGetThreadId() acpica.ACPI_THREAD_ID {
    log.debug("AcpiOsGetThreadId\n", .{});
    return 0;
}

pub export fn AcpiOsExecute(typ: acpica.ACPI_EXECUTE_TYPE, function: acpica.ACPI_OSD_EXEC_CALLBACK, context: ?*anyopaque) acpica.ACPI_STATUS {
    log.debug("AcpiOsExecute: {}, {}, {}\n", .{ typ, function, context });
    return 1;
}

pub export fn AcpiOsSleep(milliseconds: u64) void {
    log.debug("AcpiOsSleep: {}\n", .{milliseconds});
}

pub export fn AcpiOsStall(microseconds: u32) void {
    log.debug("AcpiOsStall: {}\n", .{microseconds});
}

pub export fn AcpiOsCreateMutex(out_handle: *acpica.ACPI_MUTEX) acpica.ACPI_STATUS {
    log.debug("AcpiOsCreateMutex: {}\n", .{out_handle});
    return 1;
}

pub export fn AcpiOsDeleteMutex(handle: acpica.ACPI_MUTEX) void {
    log.debug("AcpiOsDelteMutex: {}\n", .{handle});
}

pub export fn AcpiOsAcquireMutex(handle: acpica.ACPI_MUTEX, timeout: u16) acpica.ACPI_STATUS {
    log.debug("AcpiOsAcquireMutex: {}\n", .{ handle, timeout });
    return 1;
}

pub export fn AcpiOsReleaseMutex(handle: acpica.ACPI_MUTEX) void {
    log.debug("AcpiOsReleaseMutex: {}\n", .{handle});
}

pub export fn AcpiOsCreateSemaphore(max_uints: u32, initial_units: u32, out_handle: *acpica.ACPI_SEMAPHORE) acpica.ACPI_STATUS {
    log.debug("AcpiOsCreateSemaphore: {}, {}, {}\n", .{ max_uints, initial_units, out_handle });
    return 1;
}

pub export fn AcpiOsDeleteSemaphore(handle: acpica.ACPI_SEMAPHORE) acpica.ACPI_STATUS {
    log.debug("AcpiOsDeleteSemaphore: {}\n", .{handle});
    return 1;
}

pub export fn AcpiOsWaitSemaphore(handle: acpica.ACPI_SEMAPHORE, units: u32, timeout: u16) acpica.ACPI_STATUS {
    log.debug("AcpiOsWaitSemaphore: {}, {}, {}\n", .{ handle, units, timeout });
    return 1;
}

pub export fn AcpiOsSignalSemaphore(handle: acpica.ACPI_SEMAPHORE, units: u32) acpica.ACPI_STATUS {
    log.debug("AcpiOsSignalSemaphore: {}\n", .{ handle, units });
    return 1;
}

pub export fn AcpiOsCreateLock(out_handle: acpica.ACPI_SPINLOCK) acpica.ACPI_STATUS {
    log.debug("AcpiOsCreateLock: {}\n", .{out_handle});
    return 1;
}

pub export fn AcpiOsDeleteLock(handle: acpica.ACPI_HANDLE) void {
    log.debug("AcpiOsDeleteLock: {}\n", .{handle});
}

pub export fn AcpiOsAcquireLock(handle: acpica.ACPI_SPINLOCK) acpica.ACPI_STATUS {
    log.debug("AcpiOsAcquireLock: {}\n", .{handle});
    return 1;
}

pub export fn AcpiOsReleaseLock(handle: acpica.ACPI_SPINLOCK, flags: acpica.ACPI_CPU_FLAGS) void {
    log.debug("AcpiOsReleaseLock: {}, {}\n", .{ handle, flags });
}

pub export fn AcpiOsInstallInterruptHandler(interrupt_level: u32, handler: acpica.ACPI_OSD_HANDLER, context: ?*anyopaque) acpica.ACPI_STATUS {
    log.debug("AcpiOsInstallInterruptHandler: {}, {}, {}\n", .{ interrupt_level, handler, context });
    return 1;
}

pub export fn AcpiOsRemoveInterruptHandler(interrupt_level: u32, handler: acpica.ACPI_OSD_HANDLER) acpica.ACPI_STATUS {
    log.debug("AcpiOsRemoveInterruptHandler: {}, {}, {}\n", .{ interrupt_level, handler });
    return 1;
}

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
