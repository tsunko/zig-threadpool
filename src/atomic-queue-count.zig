const std = @import("std");
const AtomicOrder = std.builtin.AtomicOrder.SeqCst;

const Self = @This();

waiter: std.Thread.Semaphore,
internal: u32,
stopped: bool,

pub fn init() Self {
    return Self{
        .waiter = .{},
        .internal = 0,
        .stopped = false,
    };
}

pub fn inc(self: *Self) void {
    _ = @atomicRmw(u32, &self.internal, .Add, 1, AtomicOrder);
    self.waiter.post();
}

pub fn dec(self: *Self) void {
    _ = @atomicRmw(u32, &self.internal, .Sub, 1, AtomicOrder);
    self.waiter.post();
}

pub fn forceWake(self: *Self) void {
    // force all threads to wake up and return immediately
    self.stopped = true;
    self.waiter.permits = 0;
    self.waiter.post();
}

pub fn waitUntil(self: *Self, expect: u32) !void {
    while (true) {
        if (self.stopped) return error.Forced;

        const current = @atomicLoad(u32, &self.internal, AtomicOrder);
        if (current == expect) return;
        self.waiter.wait();
    }
}
