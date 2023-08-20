const std = @import("std");

pub const BLOCK_SIZE = 64;
pub const SAMPLE_RATE = 48 * 1000;
pub const RATE_INV = 1 / SAMPLE_RATE;

pub const Speed = enum { Fast, Slow };

const Unit = @This();

impl: Impl,
vtable: Vtable,

pub fn from_definition(
    comptime num_inputs: usize,
    comptime num_outputs: usize,
    comptime init_fn: *const fn (super: *Unit, allocator: std.mem.Allocator) *anyopaque,
    comptime deinit_fn: *const fn (super: *Unit, self: *anyopaque, allocator: std.mem.Allocator) void,
) Unit {
    comptime check_positive(num_outputs, "num_outputs");
    return .{
        .impl = .{
            .child = undefined,
            .input_speeds = &[_]Speed{.Fast} ** num_inputs,
            .output_speeds = &[_]Speed{.Fast} ** num_outputs,
            .data = data(num_inputs, num_outputs),
            .allocator = undefined,
        },
        .vtable = .{
            .init = init_fn,
            .deinit = deinit_fn,
            .next = none,
        },
    };
}

test "from_definition" {
    const Test = struct {
        const T = @This();
        fn init(super: *Unit, allocator: std.mem.Allocator) *anyopaque {
            var byte = allocator.create(u8) catch unreachable;
            switch (super.input_speed(0)) {
                .Fast => {
                    byte.* = 88;
                    super.set_calc_fn(T.next(.Fast));
                },
                .Slow => {
                    byte.* = 8;
                    super.set_calc_fn(T.next(.Slow));
                },
            }
            return byte;
        }
        fn deinit(super: *Unit, self: *anyopaque, allocator: std.mem.Allocator) void {
            var byte: *u8 = @ptrCast(@alignCast(self));
            switch (super.input_speed(1)) {
                .Fast => std.testing.expect(byte.* == 44) catch unreachable,
                .Slow => std.testing.expect(byte.* == 4) catch unreachable,
            }
            allocator.destroy(byte);
        }
        fn next(comptime speed: Speed) *const (fn (super: *Unit, self: *anyopaque) void) {
            const inner = struct {
                fn next(super: *Unit, self: *anyopaque) void {
                    var byte: *u8 = @ptrCast(@alignCast(self));
                    switch (speed) {
                        .Fast => {
                            _ = super.input(.Fast, 2);
                            std.testing.expect(byte.* == 88) catch unreachable;
                        },
                        .Slow => {
                            _ = super.input(.Slow, 2);
                            std.testing.expect(byte.* == 8) catch unreachable;
                        },
                    }
                    switch (super.input_speed(1)) {
                        .Fast => byte.* = 44,
                        .Slow => byte.* = 4,
                    }
                }
            };
            return inner.next;
        }
    };
    var test_unit = from_definition(
        3,
        2,
        Test.init,
        Test.deinit,
    );
    const input_speeds = [_]Speed{ .Fast, .Slow, .Fast };
    const output_speeds = [_]Speed{ .Fast, .Slow };
    test_unit.init(
        std.testing.allocator,
        &input_speeds,
        &output_speeds,
    );
    defer test_unit.deinit();
    test_unit.next();
}

pub fn init(
    self: *Unit,
    allocator: std.mem.Allocator,
    input_speeds: []const Speed,
    output_speeds: []const Speed,
) void {
    std.debug.assert(input_speeds.len == self.impl.input_speeds.len);
    std.debug.assert(output_speeds.len == self.impl.output_speeds.len);
    self.impl.allocator = allocator;
    self.impl.data.init(allocator);
    self.impl.input_speeds = input_speeds;
    self.impl.output_speeds = output_speeds;
    self.impl.child = self.vtable.init(self, allocator);
}

pub fn deinit(self: *Unit) void {
    self.vtable.deinit(self, self.impl.child, self.impl.allocator);
    self.impl.data.deinit();
}

pub fn next(self: *Unit) void {
    self.vtable.next(self, self.impl.child);
}

pub fn set_calc_fn(
    self: *Unit,
    next_fn: *const fn (super: *Unit, self: *anyopaque) void,
) void {
    self.vtable.next = next_fn;
}

pub fn input(self: *Unit, comptime speed: Speed, comptime n: usize) Input(speed) {
    return self.impl.data.input(speed, n);
}

pub fn output(self: *Unit, comptime speed: Speed, comptime n: usize) Output(speed) {
    return self.impl.data.output(speed, n);
}

pub fn input_speed(self: *Unit, comptime n: usize) Speed {
    std.debug.assert(n < self.impl.input_speeds.len);
    return self.impl.input_speeds[n];
}

pub fn output_speed(self: *Unit, comptime n: usize) Speed {
    std.debug.assert(n < self.impl.output_speeds.len);
    return self.impl.output_speeds[n];
}

const Vtable = struct {
    init: *const fn (super: *Unit, allocator: std.mem.Allocator) *anyopaque,
    deinit: *const fn (super: *Unit, self: *anyopaque, allocator: std.mem.Allocator) void,
    next: *const fn (super: *Unit, self: *anyopaque) void,
};

const Impl = struct {
    child: *anyopaque,
    input_speeds: []const Speed,
    output_speeds: []const Speed,
    data: Data,
    allocator: std.mem.Allocator,
};

fn none(super: *Unit, self: *anyopaque) void {
    _ = self;
    _ = super;
}

fn data(comptime num_inputs: usize, comptime num_outputs: usize) Data {
    comptime check_positive(num_outputs, "num_outputs");
    const Inner = struct {
        const T = @This();
        ins: [num_inputs]*[BLOCK_SIZE]f32 = undefined,
        outs: [num_outputs]*[BLOCK_SIZE]f32 = undefined,
        allocator: std.mem.Allocator = undefined,

        fn init(allocator: std.mem.Allocator) *anyopaque {
            var self = allocator.create(T) catch @panic("OOM!");
            self.allocator = allocator;
            inline for (0..num_inputs) |i| {
                self.ins[i] = allocator.create([BLOCK_SIZE]f32) catch @panic("OOM!");
                self.ins[i].* = .{0} ** BLOCK_SIZE;
            }
            inline for (0..num_outputs) |i| {
                self.outs[i] = allocator.create([BLOCK_SIZE]f32) catch @panic("OOM!");
                self.outs[i].* = .{0} ** BLOCK_SIZE;
            }
            return self;
        }

        fn deinit(inner: *anyopaque) void {
            var self: *T = @ptrCast(@alignCast(inner));
            inline for (self.ins) |in| self.allocator.destroy(in);
            inline for (self.outs) |out| self.allocator.destroy(out);
            self.allocator.destroy(self);
        }

        fn input_fast(inner: *anyopaque, n: usize) Input(.Fast) {
            std.debug.assert(n < num_inputs);
            var self: *T = @ptrCast(@alignCast(inner));
            return self.ins[n].*;
        }

        fn input_slow(inner: *anyopaque, n: usize) Input(.Slow) {
            std.debug.assert(n < num_inputs);
            var self: *T = @ptrCast(@alignCast(inner));
            return self.ins[n][0];
        }

        fn output_fast(inner: *anyopaque, n: usize) Output(.Fast) {
            std.debug.assert(n < num_outputs);
            var self: *T = @ptrCast(@alignCast(inner));
            return self.outs[n];
        }

        fn output_slow(inner: *anyopaque, n: usize) Output(.Slow) {
            std.debug.assert(n < num_outputs);
            var self: *T = @ptrCast(@alignCast(inner));
            return &self.outs[n][0];
        }
    };
    var inner = Inner{};
    return .{
        .inner = &inner,
        .vtable = .{
            .init = Inner.init,
            .deinit = Inner.deinit,
            .input_fast = Inner.input_fast,
            .input_slow = Inner.input_slow,
            .output_fast = Inner.output_fast,
            .output_slow = Inner.output_slow,
        },
    };
}

test "Data" {
    var new_data = data(3, 2);
    new_data.init(std.testing.allocator);
    defer new_data.deinit();
    _ = new_data.input(.Slow, 2);
    _ = new_data.output(.Fast, 1);
}

const Data = struct {
    inner: *anyopaque = undefined,
    vtable: Data.Vtable,

    const Vtable = struct {
        init: *const fn (allocator: std.mem.Allocator) *anyopaque,
        deinit: *const fn (inner: *anyopaque) void,
        input_fast: *const fn (inner: *anyopaque, n: usize) Input(.Fast),
        input_slow: *const fn (inner: *anyopaque, n: usize) Input(.Slow),
        output_fast: *const fn (inner: *anyopaque, n: usize) Output(.Fast),
        output_slow: *const fn (inner: *anyopaque, n: usize) Output(.Slow),
    };

    fn init(self: *Data, allocator: std.mem.Allocator) void {
        self.inner = self.vtable.init(allocator);
    }

    fn deinit(self: *Data) void {
        self.vtable.deinit(self.inner);
    }

    fn input(self: *Data, comptime speed: Speed, comptime n: usize) Input(speed) {
        switch (speed) {
            .Fast => return self.vtable.input_fast(self.inner, n),
            .Slow => return self.vtable.input_slow(self.inner, n),
        }
    }

    fn output(self: *Data, comptime speed: Speed, comptime n: usize) Output(speed) {
        switch (speed) {
            .Fast => return self.vtable.output_fast(self.inner, n),
            .Slow => return self.vtable.output_slow(self.inner, n),
        }
    }
};

fn Input(comptime speed: Speed) type {
    switch (speed) {
        .Fast => return [BLOCK_SIZE]f32,
        .Slow => return f32,
    }
}

fn Output(comptime speed: Speed) type {
    switch (speed) {
        .Fast => return *[BLOCK_SIZE]f32,
        .Slow => return *f32,
    }
}

fn check_positive(comptime n: usize, comptime var_name: []const u8) void {
    comptime if (n == 0)
        @compileError(var_name ++ " must be positive!");
}
