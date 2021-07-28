const std = @import("std");
const ThreadPool = @import("lib.zig").ThreadPool;

const allocator = std.testing.allocator;

const TestStruct = struct {
    sum: usize = 0,

    fn addOne(self: *@This(), num: usize) void {
        _ = @atomicRmw(usize, &self.sum, .Add, num, std.builtin.AtomicOrder.SeqCst);
    }
};

var testFreeVar: usize = 1;
fn testFreeFunc() void {
    testFreeVar = 0;
}

pub fn main() !void {
    // create pool and defer its shutdown
    var pool = try ThreadPool(TestStruct.addOne, testFreeFunc).init(allocator, 4);

    // create dummy test struct
    var obj: TestStruct = .{};

    // add all numbers from 1 to 100 on different threads
    var i: usize = 1;
    while (i <= 100) : (i += 1) {
        try pool.submitTask(.{ &obj, i });
    }

    // wait for all tasks to complete
    try pool.awaitTermination();
    pool.shutdown();

    std.debug.assert(testFreeVar == 0);
    std.debug.assert(obj.sum == 5050);
    std.debug.print("Test passed.\n", .{});
}
