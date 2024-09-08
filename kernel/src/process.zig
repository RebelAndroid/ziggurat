const std = @import("std");
const registers = @import("x64/registers.zig");

pub const Process = extern struct {
    rax: u64 = 0,
    rbx: u64 = 0,
    // this cannot be set when a process is created because it is used by sysret
    rcx: u64 = 0,
    rdx: u64 = 0,
    rsi: u64 = 0,
    rdi: u64 = 0,
    rsp: u64 = 0,
    rbp: u64 = 0,
    r8: u64 = 0,
    r9: u64 = 0,
    r10: u64 = 0,
    // this cannot be set when a process is created because it is used by sysret
    r11: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
    rip: u64 = 0,
    rflags: registers.Rflags = @bitCast(@as(u64, 0)),
    cr3: registers.CR3 = @bitCast(@as(u64, 0)),
    cs: u64,
    ss: u64,
};

// these values must match the offsets used in jump_to_user_mode
test "jump to user mode offsets" {
    try std.testing.expectEqual(128, @offsetOf(Process, "rip"));
    try std.testing.expectEqual(136, @offsetOf(Process, "rflags"));
    try std.testing.expectEqual(48, @offsetOf(Process, "rsp"));
    try std.testing.expectEqual(144, @offsetOf(Process, "cr3"));
    try std.testing.expectEqual(120, @offsetOf(Process, "r15"));
    try std.testing.expectEqual(152, @offsetOf(Process, "cs"));
    try std.testing.expectEqual(160, @offsetOf(Process, "ss"));
}
