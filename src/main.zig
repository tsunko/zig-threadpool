const std = @import("std");
const ThreadPool = @import("lib.zig").ThreadPool;

const allocator = std.testing.allocator;

const TestStruct = struct {
    sum: usize = 0,

    fn addOne(self: *@This(), num: usize) void {
        self.sum += num;
    }
};

pub fn main() !void {
    // create pool and defer its shutdown
    var pool = try ThreadPool(TestStruct.addOne, null).init(allocator, 4);
    defer pool.shutdown();

    // create dummy test struct
    var obj: TestStruct = .{};

    // add all numbers from 1 to 100 on different threads
    var i: usize = 1;
    while (i <= 100) : (i += 1) {
        try pool.submitTask(.{ &obj, i });
    }

    // wait for all tasks to complete
    try pool.awaitTermination();

    std.debug.assert(obj.sum == 5050);
    std.debug.print("Test passed.", .{});
}
