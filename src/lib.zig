const std = @import("std");

const AtomicQueueCount = @import("atomic-queue-count.zig");
const Allocator = std.mem.Allocator;

/// A simple thread pool that supports only calling one specific function.
pub fn ThreadPool(comptime func: anytype) type {
    return struct {
        const Self = @This();
        // derive arg and queue type from func
        const Args = std.meta.ArgsTuple(@TypeOf(func));
        const QueueType = std.atomic.Queue(?Args);

        queue: QueueType,
        queueSema: std.Thread.Semaphore,

        threads: []std.Thread,

        // other threads waiting for us to complete
        waiting: AtomicQueueCount,
        allocator: *Allocator,

        /// Initializes a thread pool using the given allocator and with the specified amount of threads.
        pub fn init(allocator: *Allocator, threadCount: usize) !*Self {
            // try alloc self
            var pool = try allocator.create(Self);
            errdefer allocator.destroy(pool);

            pool.queue = QueueType.init();
            pool.queueSema = .{};

            // try alloc threads array
            pool.threads = try allocator.alloc(std.Thread, threadCount);
            errdefer allocator.free(pool.threads);

            pool.waiting = AtomicQueueCount.init();
            pool.allocator = allocator;

            // spawn our threads
            for (pool.threads) |*thread| {
                thread.* = try std.Thread.spawn(.{}, takeTask, .{pool});
            }

            return pool;
        }

        /// Internal method for worker threads
        fn takeTask(self: *Self) void {
            while (true) {
                self.queueSema.wait();

                // node should not be null here - if it is, then just continue
                // the only reason we wake up here is there's a race condition
                // i'm not seeing or there was a spurious wake up
                const node = self.queue.get() orelse continue;
                defer self.allocator.destroy(node);

                // check if node has actual data - if it does, then process it
                // otherwise, we want to terminate the thread.
                if (node.data) |data| {
                    // call function and decrement how many tasks are waiting
                    _ = @call(.{}, func, data);
                    self.waiting.dec();
                } else return;
            }
        }

        /// Pauses the current thread and waits until the amount of waiting tasks is 0.
        pub fn awaitTermination(self: *Self) !void {
            try self.waiting.waitUntil(0);
        }

        /// Joins and waits for all threads to terminate, then frees the thread array and the pool itself.
        pub fn shutdown(self: *Self) void {
            for (self.threads) |_| {
                self.submitTaskAllowNull(null) catch @panic("failed to shutdown pool - task submission failed");
            }

            for (self.threads) |thread| {
                thread.join();
            }

            self.allocator.free(self.threads);
            self.allocator.destroy(self);
        }

        /// Internal method to submit tasks that allow for a null args value - only used for termination.
        fn submitTaskAllowNull(self: *Self, args: ?Args) !void {
            var node = try self.allocator.create(QueueType.Node);
            node.data = args;

            self.queue.put(node);
            self.waiting.inc();
            self.queueSema.post();
        }

        /// Submits the arguments as a new task to the thread pool.
        pub fn submitTask(self: *Self, args: Args) !void {
            try self.submitTaskAllowNull(args);
        }
    };
}

test "basic test" {
    const TestStruct = struct {
        value: usize = 0,

        fn addOne(self: *@This()) void {
            self.value += 1;
        }
    };

    const allocator = std.testing.allocator;
    var obj: TestStruct = .{};
    var pool = try ThreadPool(TestStruct.addOne).init(allocator, 2);

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try pool.submitTask(.{&obj});
    }
    try pool.awaitTermination();

    // after shutdown, pool is invalid since we call destroy() on self
    pool.shutdown();

    std.debug.assert(obj.value == 1000);
}
