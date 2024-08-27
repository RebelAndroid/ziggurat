const msr = @import("msr.zig");
const std = @import("std");

const log = std.log.scoped(.apic);

// Local APIC registers, see Intel SDM Table 11-6 Vol. 3A 11-39

fn read_local_apic_id() u32 {
    return @truncate(msr.readMsr(0x802));
}

fn read_local_apic_version() u32 {
    return @truncate(msr.readMsr(0x803));
}

const TASK_PRIORITY_INDEX: u32 = 0x80A;

fn read_task_priority() u32 {
    return @truncate(msr.readMsr(TASK_PRIORITY_INDEX));
}

fn write_task_priority(task_priority: u32) void {
    msr.writeMsr(TASK_PRIORITY_INDEX, task_priority);
}

fn write_eoi(eoi: u32) void {
    msr.writeMsr(0x80B, eoi);
}

fn read_logical_destination() u32 {
    return @truncate(msr.readMsr(0x80D));
}

const SPURIOUS_INTERRUPT_INDEX: u32 = 0x80F;
fn read_spurious_interrupt() u32 {
    return @truncate(msr.readMsr(SPURIOUS_INTERRUPT_INDEX));
}

fn write_spurious_interrupt(spurious_interrupt: u32) void {
    msr.writeMsr(SPURIOUS_INTERRUPT_INDEX, spurious_interrupt);
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
fn read_interrupt_command() u32 {
    return @truncate(msr.readMsr(INTERRUPT_COMMAND_INDEX));
}

fn write_interrupt_command(interrupt_command: u32) void {
    msr.writeMsr(INTERRUPT_COMMAND_INDEX, interrupt_command);
}

const LVT_TIMER_INDEX: u32 = 0x832;
fn read_lvt_timer() u32 {
    return @truncate(msr.readMsr(LVT_TIMER_INDEX));
}

fn write_lvt_timer(lvt_timer: u32) void {
    msr.writeMsr(LVT_TIMER_INDEX, lvt_timer);
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

const INITIAL_COUNT_INDEX: u32 = 0x838;
fn read_initial_count() u32 {
    return @truncate(msr.readMsr(INITIAL_COUNT_INDEX));
}

fn write_initial_count(initial_count: u32) void {
    msr.writeMsr(INITIAL_COUNT_INDEX, initial_count);
}

const CURRENT_COUNT_INDEX: u32 = 0x839;
fn read_current_count() u32 {
    return @truncate(msr.readMsr(CURRENT_COUNT_INDEX));
}

fn write_current_count(current_count: u32) void {
    msr.writeMsr(CURRENT_COUNT_INDEX, current_count);
}

const DIVIDE_CONFIGURATION_INDEX: u32 = 0x83E;
fn read_divide_configuration() u32 {
    return @truncate(msr.readMsr(DIVIDE_CONFIGURATION_INDEX));
}

fn write_divide_configuration(divide_configuration: u32) void {
    msr.writeMsr(DIVIDE_CONFIGURATION_INDEX, divide_configuration);
}

fn write_self_ipi(self_ipi: u32) void {
    msr.writeMsr(0x83F, self_ipi);
}
