const std = @import("std");

const log = std.log.scoped(.lock);

pub const Lock = struct {
    const unlocked: u8 = 0;
    const locked: u8 = 1;
    x: u8 = unlocked,

    pub fn lock(self: *Lock) void {
        while (true) {
            const old = @cmpxchgWeak(u8, &self.x, unlocked, locked, std.builtin.AtomicOrder.seq_cst, std.builtin.AtomicOrder.seq_cst);
            if (old == null and locked == @atomicLoad(u8, &self.x, std.builtin.AtomicOrder.seq_cst)) {
                break;
            }
        }
    }

    pub fn tryLock(self: Lock) bool {
        const old = @cmpxchgStrong(u8, &self.x, unlocked, locked, std.builtin.AtomicOrder.seq_cst, std.builtin.AtomicOrder.seq_cst);
        return old == null;
    }

    pub fn unlock(self: *Lock) void {
        const old = @cmpxchgStrong(u8, &self.x, locked, unlocked, std.builtin.AtomicOrder.seq_cst, std.builtin.AtomicOrder.seq_cst);

        if (old != null) {
            @panic("Attempted to unlock Lock that is not locked!");
        }
    }
};

pub fn Mutex(T: type) type {
    return struct {
        const Self = @This();
        t: T,
        lock: Lock,

        pub fn new(t: T) Self {
            return .{
                .t = t,
                .lock = .{},
            };
        }

        pub fn get(self: *Self) *T {
            self.lock.lock();
            return &self.t;
        }

        pub fn release(self: *Self) void {
            self.lock.unlock();
        }
    };
}
