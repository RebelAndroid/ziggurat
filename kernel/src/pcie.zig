pub const std = @import("std");
pub const acpi = @import("acpi.zig");

const log = std.log.scoped(.acpi);

const CommonHeader = extern struct {
    vendor_id: u16,
    device_id: u16,
    command: u16,
    status: u16,
    revision_id: u8,
    prog_if: u8,
    subclass: u8,
    classcode: ClassCode,
    cache_line_size: u8,
    latency_timer: u8,
    header_type: HeaderType,
    bist: u8,
};

const HeaderType = packed struct {
    header_type: u7,
    multi_function: bool,
};

const ClassCode = enum(u8) {
    unclassified,
    mass_storage_controller,
    network_controller,
    display_controller,
    multimedia_controller,
    memory_controller,
    bridge,
    simple_communication_controller,
    base_system_peripheral,
    input_device_controller,
    docking_station,
    processor,
    serial_bus_controller,
    wireless_controller,
    intelligent_controller,
    satellite_communication_controller,
    encryption_controller,
    signal_processing_controller,
    processing_accelerator,
    non_essential_instrumentation,
};

pub fn calc_physical_address(base: u64, bus: u8, device: u8, function: u8) u64 {
    return base + (@as(u64, bus) << 20) + (@as(u64, device) << 15) + (@as(u64, function) << 12);
}

pub fn get_devices(bus_segment_group: acpi.McfgEntry, hhdm_offset: u64) void {
    var bus: u8 = bus_segment_group.start_pci_bus_number;
    while (bus < bus_segment_group.end_pci_bus_number) : (bus += 1) {
        var device: u8 = 0;
        while (device < 32) : (device += 1) {
            const phyiscal_address = calc_physical_address(bus_segment_group.base_address, bus, device, 0);
            const ptr: *CommonHeader = @ptrFromInt(phyiscal_address + hhdm_offset);
            if (ptr.vendor_id != 0xFFFF) {
                log.info("bus: {}, dev: {}, func: {}: common header: {}\n", .{ bus, device, 0, ptr });
            }
            if (ptr.header_type.multi_function) {
                var function: u8 = 1;
                while (function < 8) : (function += 1) {
                    const phys_addr = calc_physical_address(bus_segment_group.base_address, bus, device, function);
                    const ptr2: *CommonHeader = @ptrFromInt(phys_addr + hhdm_offset);
                    if (ptr2.vendor_id != 0xFFFF) {
                        log.info("bus: {}, dev: {}, func: {}: common header: {}\n", .{ bus, device, function, ptr2 });
                    }
                }
            }
        }
    }
}
