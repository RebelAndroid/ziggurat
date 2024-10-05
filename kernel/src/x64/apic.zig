const msr = @import("msr.zig");
const std = @import("std");
const cpuid = @import("cpuid.zig");
const reg = @import("registers.zig");
const paging = @import("page_table.zig");
const pmm = @import("../pmm.zig");

const log = std.log.scoped(.apic);

const apic_register = extern struct {
    contents: u32,
    _1: u32,
    _2: u32,
    _3: u32,
};

var x2apic = false;
var apic_registers: [*]volatile apic_register = @ptrFromInt(0x10);

pub fn init(hhdm_offset: u64, cr3: *reg.CR3, frame_allocator: *pmm.FrameAllocator) void {
    x2apic = cpuid.get_feature_information().x2apic;
    // x2apic = false;
    var apic_base = msr.readApicBase();
    if (x2apic) {
        log.debug("running in x2apic mode\n", .{});
        apic_base.enable_x2apic = true;
    } else {
        log.debug("running in xapic mode\n", .{});
        const apic_virtaddr = paging.VirtualAddress{
            .sign_extension = 0xFFFF,
            .pml4 = 0x1FF,
            .directory_pointer = 0,
            .directory = 0,
            .table = 0,
            .page_offset = 0,
        };
        log.debug("mapping apic to: 0x{x}\n", .{@as(u64, @bitCast(apic_virtaddr))});
        cr3.map(paging.Page{
            .four_kb = apic_virtaddr,
        }, @as(u64, apic_base.apic_base) << 12, hhdm_offset, frame_allocator, .{
            .execute = false,
            .write = true,
            .user = false,
        }) catch unreachable;

        // set our newly mapped page to PAT3 (strong uncacheable)
        const r = cr3.setPat(paging.Page{
            .four_kb = apic_virtaddr,
        }, hhdm_offset, 3);
        if (!r) {
            log.err("unable to set PAT on newly mapped APIC\n", .{});
            unreachable;
        }

        apic_registers = @ptrFromInt(@as(u64, @bitCast(apic_virtaddr)));
    }
    apic_base.enable_xapic = true;
    msr.writeApicBase(apic_base);
}

// Local APIC registers, see Intel SDM Table 11-6 Vol. 3A 11-39
pub fn read_local_apic_id() u32 {
    if (x2apic) {
        return @truncate(msr.readMsr(0x802));
    } else {
        return apic_registers[2].contents;
    }
}

fn read_local_apic_version() u32 {
    return @truncate(msr.readMsr(0x803));
}

const TASK_PRIORITY_MSR: u32 = 0x80A;
const TASK_PRIORITY_INDEX: usize = 8;

pub fn read_task_priority() u32 {
    if (x2apic) {
        return @truncate(msr.readMsr(TASK_PRIORITY_MSR));
    } else {
        return apic_registers[TASK_PRIORITY_INDEX].contents;
    }
}

pub fn write_task_priority(task_priority: u32) void {
    if (x2apic) {
        msr.writeMsr(TASK_PRIORITY_MSR, task_priority);
    } else {
        apic_registers[TASK_PRIORITY_INDEX].contents = task_priority;
    }
}

pub fn write_eoi(eoi: u32) void {
    if (x2apic) {
        msr.writeMsr(0x80B, eoi);
    } else {
        apic_registers[0xB].contents = eoi;
    }
}

fn read_logical_destination() u32 {
    return @truncate(msr.readMsr(0x80D));
}

const SPURIOUS_INTERRUPT_MSR: u32 = 0x80F;
const SPURIOUS_INTERRUPT_INDEX: usize = 0xF;

pub const SpuriousInterruptVectorRegister = packed struct {
    vector: u8,
    apic_software_enable: bool,
    focus_processor_checking: bool,
    _1: u2 = 0,
    eoi_broadcast_supression: bool,
    _2: u19 = 0,
};

pub fn read_spurious_interrupt() SpuriousInterruptVectorRegister {
    // log.info("WHAT\n", .{});
    if (x2apic) {
        return @truncate(msr.readMsr(SPURIOUS_INTERRUPT_MSR));
    } else {
        return apic_registers[SPURIOUS_INTERRUPT_INDEX].contents;
    }
}

pub fn write_spurious_interrupt(spurious_interrupt: SpuriousInterruptVectorRegister) void {
    if (x2apic) {
        msr.writeMsr(SPURIOUS_INTERRUPT_MSR, @as(u32, @bitCast(spurious_interrupt)));
    } else {
        log.info("writing spurious interrupt at: 0x{x}\n", .{@as(u64, @intFromPtr(&apic_registers[SPURIOUS_INTERRUPT_INDEX]))});
        apic_registers[SPURIOUS_INTERRUPT_INDEX].contents = @bitCast(spurious_interrupt);
    }
}

fn read_in_service(index: u32) u32 {
    if (index > 6) {
        std.debug.panic("APIC ISR index out of range: 0x{}", .{index});
    }
    return @truncate(msr.readMsr(0x811 + index));
}

fn read_trigger_mode(index: u32) u32 {
    if (index > 6) {
        std.debug.panic("APIC TMR index out of range: 0x{}", .{index});
    }
    return @truncate(msr.readMsr(0x818 + index));
}

fn read_interrupt_request(index: u32) u32 {
    if (index > 6) {
        std.debug.panic("APIC IRR index out of range: 0x{}", .{index});
    }
    return @truncate(msr.readMsr(0x820 + index));
}

const ERROR_STATUS_INDEX: u32 = 0x828;
fn read_error_status() u32 {
    return @truncate(msr.readMsr(ERROR_STATUS_INDEX));
}

fn write_error_status(error_status: u32) void {
    msr.writeMsr(ERROR_STATUS_INDEX, error_status);
}

const LVT_CMCI_INDEX: u32 = 0x82F;
fn read_lvt_cmci() u32 {
    return @truncate(msr.readMsr(LVT_CMCI_INDEX));
}

fn write_lvt_cmci(lvt_cmci: u32) void {
    msr.writeMsr(LVT_CMCI_INDEX, lvt_cmci);
}

const INTERRUPT_COMMAND_INDEX: u32 = 0x830;

pub const InterruptCommandRegister = packed struct {
    vector: u8,
    delivery_mode: IcrDeliveryMode,
    /// Set for logical, clear for physical
    destination_mode: bool,
    _1: u2 = 0,
    level: bool,
    /// Set for level, clear for edge
    trigger_mode: bool,
    _2: u2 = 0,
    destination_shorthand: u2,
    _3: u12 = 0,
    destination: u32,
};

pub const IcrDeliveryMode = enum(u3) {
    fixed = 0,
    smi = 2,
    nmi = 4,
    init = 5,
    start_up = 6,
};

fn read_interrupt_command() u64 {
    return @truncate(msr.readMsr(INTERRUPT_COMMAND_INDEX));
}

fn write_interrupt_command(interrupt_command: u64) void {
    msr.writeMsr(INTERRUPT_COMMAND_INDEX, interrupt_command);
}

const LVT_TIMER_MSR: u32 = 0x832;
const LVT_TIMER_INDEX: usize = 0x32;

pub const Timer = packed struct {
    vector: u8,
    _1: u4 = 0,
    /// Set if send pending, clear if idle
    delivery_status: bool,
    _2: u3 = 0,
    mask: bool,
    mode: TimerMode,
    _3: u13 = 0,
};

pub const TimerMode = enum(u2) {
    one_shot = 0,
    periodic = 1,
    tsc_deadline = 2,
};

pub fn read_lvt_timer() Timer {
    if (x2apic) {
        return @truncate(msr.readMsr(LVT_TIMER_MSR));
    } else {
        return apic_registers[LVT_TIMER_INDEX].contents;
    }
}

pub fn write_lvt_timer(lvt_timer: Timer) void {
    if (x2apic) {
        msr.writeMsr(LVT_TIMER_MSR, @as(u32, @bitCast(lvt_timer)));
    } else {
        apic_registers[LVT_TIMER_INDEX].contents = @bitCast(lvt_timer);
    }
}

const LVT_THERMAL_SENSOR: u32 = 0x833;
fn read_lvt_thermal_sensor() u32 {
    return @truncate(msr.readMsr(LVT_THERMAL_SENSOR));
}

fn write_lvt_thermal_sensor(lvt_thermal_sensor: u32) void {
    msr.writeMsr(LVT_THERMAL_SENSOR, lvt_thermal_sensor);
}

const LVT_PERFORMANCE_MONITORING: u32 = 0x834;
fn read_lvt_performance_monitoring() u32 {
    return @truncate(msr.readMsr(LVT_PERFORMANCE_MONITORING));
}

fn write_lvt_performance_monitoring(lvt_performance_monitoring: u32) void {
    msr.writeMsr(LVT_PERFORMANCE_MONITORING, lvt_performance_monitoring);
}

const LINT0_INDEX: u32 = 0x835;
fn read_lint0() u32 {
    return @truncate(msr.readMsr(LINT0_INDEX));
}

fn write_lint0(lint0: u32) void {
    msr.writeMsr(LINT0_INDEX, lint0);
}

const LINT1_INDEX: u32 = 0x836;
fn read_lint1() u32 {
    return @truncate(msr.readMsr(LINT1_INDEX));
}

fn write_lint1(lint1: u32) void {
    msr.writeMsr(LINT1_INDEX, lint1);
}

const LVT_ERROR_INDEX: u32 = 0x837;
fn read_lvt_error() u32 {
    return @truncate(msr.readMsr(LVT_ERROR_INDEX));
}

fn write_lvt_error(lvt_error: u32) void {
    msr.writeMsr(LVT_ERROR_INDEX, lvt_error);
}

const INITIAL_COUNT_MSR: u32 = 0x838;
const INITIAL_COUNT_INDEX: usize = 0x38;

pub fn read_initial_count() u32 {
    if (x2apic) {
        return @truncate(msr.readMsr(INITIAL_COUNT_MSR));
    } else {
        return apic_registers[INITIAL_COUNT_INDEX].contents;
    }
}

pub fn write_initial_count(initial_count: u32) void {
    if (x2apic) {
        msr.writeMsr(INITIAL_COUNT_MSR, initial_count);
    } else {
        apic_registers[INITIAL_COUNT_INDEX].contents = initial_count;
    }
}

const CURRENT_COUNT_INDEX: u32 = 0x839;
pub fn read_current_count() u32 {
    return @truncate(msr.readMsr(CURRENT_COUNT_INDEX));
}

fn write_current_count(current_count: u32) void {
    msr.writeMsr(CURRENT_COUNT_INDEX, current_count);
}

const DIVIDE_CONFIGURATION_MSR: u32 = 0x83E;
const DIVIDE_CONFIGURATION_INDEX: usize = 0x3E;

pub const DivideConfigurationRegister = packed struct {
    divide1: u2,
    _1: u1 = 0,
    divide2: u1,
    _2: u28 = 0,
};

pub fn read_divide_configuration() DivideConfigurationRegister {
    if (x2apic) {
        return @truncate(msr.readMsr(DIVIDE_CONFIGURATION_MSR));
    } else {
        return apic_registers[DIVIDE_CONFIGURATION_INDEX].contents;
    }
}

pub fn write_divide_configuration(divide_configuration: DivideConfigurationRegister) void {
    if (x2apic) {
        msr.writeMsr(DIVIDE_CONFIGURATION_MSR, @as(u32, @bitCast(divide_configuration)));
    } else {
        apic_registers[DIVIDE_CONFIGURATION_INDEX].contents = @bitCast(divide_configuration);
    }
}

fn write_self_ipi(self_ipi: u32) void {
    msr.writeMsr(0x83F, self_ipi);
}

test "APIC sizes" {
    try std.testing.expectEqual(64, @bitSizeOf(InterruptCommandRegister));
    try std.testing.expectEqual(32, @bitSizeOf(Timer));
}
