const std = @import("std");

pub fn RingBuffer(length: comptime_int, consume_function: fn ([]u8) void) type {
    return extern struct {
        // memory is readable in the interval (consume_head, produce_tail)
        // memory is writable in the interval [produce_head, consume_tail)
        consume_head: std.atomic.Value(u64) = length - 1,
        consume_tail: std.atomic.Value(u64) = length - 1,
        produce_head: std.atomic.Value(u64) = 0,
        produce_tail: std.atomic.Value(u64) = 0,
        buffer: [length]u8,
        const Self = @This();
        const sc = std.builtin.AtomicOrder.seq_cst;

        pub fn produce(self: Self, input: []u8) void {
            const head = while (true) {
                const head = self.produce_head.load(sc);
                const new_head = (head + input.len) % length;
                if (new_head >= self.consume_tail.load(sc)) {
                    // the buffer is getting full, we need to consume some data.
                    consume();
                    continue;
                }
                const r = self.produce_head.cmpxchgWeak(head, new_head, sc, sc);
                if (r == null) {
                    break head;
                }
                std.atomic.spinLoopHint();
            };
            if (head + input.len >= length) {
                // wrap around the end

                // write to the end of the buffer
                const dst = self.buffer[head..];
                @memcpy(dst, input[0..dst.len]);

                // write the remainder of the input to the front of the buffer
                const src = input[dst.len..];
                @memcpy(self.buffer[0..src.len], src);
            } else {
                // one contiguous block
                @memcpy(self.buffer[head..(head + input.len)], input);
            }

            // wait for other producers to finish (setting the tail to where we started, head), before setting produce tail
            while (true) {
                const r = self.produce_tail.cmpxchgWeak(head, (head + input.len) % length, sc, sc);
                if (r == null) {
                    break head;
                }
                std.atomic.spinLoopHint();
            }
        }

        pub fn consume(self: Self) void {
            const head = self.consume_head.load(sc);
            const pt = self.produce_tail.load(sc);
            const target_head = 0;
            if (pt == 0) {
                target_head = length - 1;
            } else {
                target_head = pt - 1;
            }
            while (true) {
                if (head == target_head) {
                    // nothing to consume
                    return;
                }
                const res = self.consume_head.cmpxchgWeak(head, target_head, sc, sc);
                if (res == null) {
                    break;
                }
                head = self.consume_head.load(sc);
                pt = self.produce_tail.load(sc);
                if (pt == 0) {
                    target_head = length - 1;
                } else {
                    target_head = pt - 1;
                }
            }

            if (head > target_head) {
                // consume wraps buffer
                consume_function(self.buffer[head..]);
                consume_function(self.buffer[0..(target_head + 1)]);
            } else {
                consume_function(self.buffer[head..target_head]);
            }
        }
    };
}
