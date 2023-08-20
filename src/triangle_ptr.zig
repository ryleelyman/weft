const std = @import("std");
const Unit = @import("Unit.zig");

const State = struct {
    phase: f32 = 0,
    sync: f32 = 0,
    phase_in: f32 = 0,
};

pub fn TrianglePTR() Unit {
    return Unit.from_definition(4, 2, init, deinit);
}

fn init(super: *Unit, allocator: std.mem.Allocator) *anyopaque {
    var internal = allocator.create(State) catch @panic("OOM!");
    internal.* = .{};
    super.set_calc_fn(next(super));
    return internal;
}

fn deinit(super: *Unit, self: *anyopaque, allocator: std.mem.Allocator) void {
    _ = super;
    var internal: *State = @ptrCast(@alignCast(self));
    allocator.destroy(internal);
}

fn next(super: *Unit) (*const fn (super: *Unit, self: *anyopaque) void) {
    switch (super.output_speed(0)) {
        .Fast => {
            switch (super.input_speed(0)) {
                .Fast => {
                    switch (super.input_speed(1)) {
                        .Fast => {
                            switch (super.input_speed(2)) {
                                .Fast => {
                                    switch (super.input_speed(3)) {
                                        .Fast => return algorithm(.{ .Fast, .Fast, .Fast, .Fast }),
                                        .Slow => return algorithm(.{ .Fast, .Fast, .Fast, .Slow }),
                                    }
                                },
                                .Slow => {
                                    switch (super.input_speed(3)) {
                                        .Fast => return algorithm(.{ .Fast, .Fast, .Slow, .Fast }),
                                        .Slow => return algorithm(.{ .Fast, .Fast, .Slow, .Slow }),
                                    }
                                },
                            }
                        },
                        .Slow => {
                            switch (super.input_speed(2)) {
                                .Fast => {
                                    switch (super.input_speed(3)) {
                                        .Fast => return algorithm(.{ .Fast, .Slow, .Fast, .Fast }),
                                        .Slow => return algorithm(.{ .Fast, .Slow, .Fast, .Slow }),
                                    }
                                },
                                .Slow => {
                                    switch (super.input_speed(3)) {
                                        .Fast => return algorithm(.{ .Fast, .Slow, .Slow, .Fast }),
                                        .Slow => return algorithm(.{ .Fast, .Slow, .Slow, .Slow }),
                                    }
                                },
                            }
                        },
                    }
                },
                .Slow => {
                    switch (super.input_speed(1)) {
                        .Fast => {
                            switch (super.input_speed(2)) {
                                .Fast => {
                                    switch (super.input_speed(3)) {
                                        .Fast => return algorithm(.{ .Slow, .Fast, .Fast, .Fast }),
                                        .Slow => return algorithm(.{ .Slow, .Fast, .Fast, .Slow }),
                                    }
                                },
                                .Slow => {
                                    switch (super.input_speed(3)) {
                                        .Fast => return algorithm(.{ .Slow, .Fast, .Slow, .Fast }),
                                        .Slow => return algorithm(.{ .Slow, .Fast, .Slow, .Slow }),
                                    }
                                },
                            }
                        },
                        .Slow => {
                            switch (super.input_speed(2)) {
                                .Fast => {
                                    switch (super.input_speed(3)) {
                                        .Fast => return algorithm(.{ .Slow, .Slow, .Fast, .Fast }),
                                        .Slow => return algorithm(.{ .Slow, .Slow, .Fast, .Slow }),
                                    }
                                },
                                .Slow => {
                                    switch (super.input_speed(3)) {
                                        .Fast => return algorithm(.{ .Slow, .Slow, .Slow, .Fast }),
                                        .Slow => return algorithm(.{ .Slow, .Slow, .Slow, .Slow }),
                                    }
                                },
                            }
                        },
                    }
                },
            }
        },
        .Slow => return algorithm(null),
    }
}

fn get_vec(
    comptime speed: Unit.Speed,
    data: if (speed == .Fast) [Unit.BLOCK_SIZE]f32 else f32,
) @Vector(Unit.BLOCK_SIZE, f32) {
    switch (comptime speed) {
        .Fast => return data,
        .Slow => return @splat(data),
    }
}

fn algorithm(comptime speeds: ?[4]Unit.Speed) (*const fn (super: *Unit, self: *anyopaque) void) {
    const inner = struct {
        fn next(super: *Unit, self: *anyopaque) void {
            var state: *State = @ptrCast(@alignCast(self));
            if (comptime speeds) |s| {
                const freq = get_vec(s[0], super.input(s[0], 0));
                const phase = super.input(s[1], 1);
                const min_width: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.001);
                const max_width: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.999);
                const width = @min(@max(get_vec(s[2], super.input(s[2], 2)), min_width), max_width);
                const sync = super.input(s[3], 3);
                var out_buf = super.output(.Fast, 0);
                var sync_out = super.output(.Fast, 1);
                var pos_vec: @Vector(Unit.BLOCK_SIZE, f32) = @splat(state.phase);
                const step = freq * @as(@Vector(Unit.BLOCK_SIZE, f32), @splat(Unit.RATE_INV));
                if (comptime s[1] == .Slow) {
                    if (comptime s[3] == .Slow) {
                        if (sync > 0 and state.sync <= 0) {
                            pos_vec[0] = 0;
                        } else {
                            pos_vec[0] = @mod(pos_vec[0] + phase - state.phase_in + step[0], 1);
                        }
                        for (1..Unit.BLOCK_SIZE) |i| {
                            pos_vec[i] = @mod(pos_vec[i - 1] + step[i], 1);
                        }
                        state.phase = pos_vec[Unit.BLOCK_SIZE - 1];
                        state.phase_in = phase;
                        state.sync = sync;
                    } else {
                        pos_vec[0] = @mod(pos_vec[0] + phase - state.phase_in + step[0], 1);
                        if (sync[0] > 0 and state.sync <= 0) pos_vec[0] = @mod(pos_vec[0], @max(step[0], 0.001));
                        for (1..Unit.BLOCK_SIZE) |i| {
                            pos_vec[i] = @mod(pos_vec[i - 1] + step[i], 1);
                            if (sync[i] > 0 and sync[i - 1] <= 0) pos_vec[i] = @mod(pos_vec[i], step[i]);
                        }
                        state.phase = pos_vec[Unit.BLOCK_SIZE - 1];
                        state.phase_in = phase;
                        state.sync = sync[Unit.BLOCK_SIZE - 1];
                    }
                } else {
                    if (comptime s[3] == .Slow) {
                        if (sync > 0 and state.sync <= 0) {
                            pos_vec[0] = 0;
                        } else {
                            pos_vec[0] = @mod(pos_vec[0] + phase[0] - state.phase_in + step[0], 1);
                        }
                        for (1..Unit.BLOCK_SIZE) |i| {
                            pos_vec[i] = @mod(pos_vec[i - 1] + phase[i] - phase[i - 1] + step[i], 1);
                        }
                        state.phase = pos_vec[Unit.BLOCK_SIZE - 1];
                        state.phase_in = phase[Unit.BLOCK_SIZE - 1];
                        state.sync = sync;
                    } else {
                        pos_vec[0] = @mod(pos_vec[0] + phase[0] - state.phase_in + step[0], 1);
                        if (sync[0] > 0 and state.sync <= 0) pos_vec[0] = @mod(pos_vec[0], @max(step[0], 0.001));
                        for (1..Unit.BLOCK_SIZE) |i| {
                            pos_vec[i] = @mod(pos_vec[i - 1] + phase[i] - phase[i - 1] + step[i], 1);
                            if (sync[i] > 0 and sync[i - 1] <= 0) pos_vec[i] = @mod(pos_vec[i], step[i]);
                        }
                        state.phase = pos_vec[Unit.BLOCK_SIZE - 1];
                        state.phase_in = phase[Unit.BLOCK_SIZE - 1];
                        state.sync = phase[Unit.BLOCK_SIZE - 1];
                    }
                }
                const a = @as(@Vector(Unit.BLOCK_SIZE, f32), @splat(2)) / width;
                const ones: @Vector(Unit.BLOCK_SIZE, f32) = @splat(1);
                const half: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.5);
                const b = @as(@Vector(Unit.BLOCK_SIZE, f32), @splat(2)) / (width - ones);
                const c = half * a * b;
                const twelve: @Vector(Unit.BLOCK_SIZE, f32) = @splat(12);
                out_buf.* = algorithm3(
                    pos_vec,
                    step,
                    step + step,
                    step + step + step,
                    width,
                    a,
                    b,
                    c,
                    step + half * step,
                    c / step,
                    c / (step * step),
                    c / (step * step * step * twelve),
                );
                sync_out.* = @select(
                    f32,
                    pos_vec < step,
                    @as(@Vector(Unit.BLOCK_SIZE, f32), @splat(1)),
                    @as(@Vector(Unit.BLOCK_SIZE, f32), @splat(0)),
                );
            } else {
                const freq = super.input(.Slow, 0);
                const phase = super.input(.Slow, 1);
                const width = @max(@min(super.input(.Slow, 2), 0.999), 0.001);
                const sync = super.input(.Slow, 3);
                var out_buf = super.output(.Slow, 0);
                var sync_out = super.output(.Slow, 1);

                const step = freq * Unit.RATE_INV;
                if (sync > 0 and state.sync <= 0) {
                    state.phase = 0;
                } else {
                    state.phase += (phase - state.phase_in) + step;
                    state.phase = @mod(state.phase, 1);
                }
                state.sync = sync;
                state.phase_in = phase;
                if (state.phase < step) sync_out.* = 1;
                const a = 2 / width;
                const b = 2 / (width - 1);
                const c = 0.5 * a * b;
                out_buf.* = algorithm2(
                    state.phase,
                    step,
                    2 * step,
                    3 * step,
                    width,
                    a,
                    b,
                    c,
                    1.5 * step,
                    c / step,
                    c / (step * step),
                    c / (step * step * step * 12),
                );
            }
        }
    };
    return inner.next;
}

fn algorithm2(
    p: f32,
    t0: f32,
    t2: f32,
    t3: f32,
    w: f32,
    a: f32,
    b: f32,
    c: f32,
    dc: f32,
    p1: f32,
    p2: f32,
    p3: f32,
) f32 {
    if (p < w) {
        if (p < t0) {
            return b * p - b * dc - 1 - 0.5 * p3 * p * p * p * p;
        } else if (p < t2) {
            return b * p - b * dc + p3 * p * p * p * p - 0.5 * p2 * p * p * p + 0.75 * p1 * p * p - 0.5 * c * p + 0.125 * c * t0;
        } else if (p < t3) {
            return b * p - b * dc - 1 - 0.5 * p3 * p * p * p * p + 0.5 * p2 * p * p * p - 2.25 * p1 * p * p + 3.5 * c * p - 1.875 * c * t0;
        } else {
            return a * p - a * dc - 1;
        }
    } else {
        const pw = p - w;
        if (pw < t0) {
            return a * pw - a * dc + 1 + 0.5 * p3 * pw * pw * pw * pw;
        } else if (pw < t2) {
            return a * pw - a * dc + 1 - p3 * pw * pw * pw * pw + 0.5 * p2 * pw * pw * pw - 0.75 * p1 * pw * pw + 0.5 * c * pw - 0.125 * c * t0;
        } else if (pw < t3) {
            return a * pw - a * dc + 1 + 0.5 * p3 * pw * pw * pw * pw - 0.5 * p2 * pw * pw * pw + 2.25 * p1 * pw * pw - 3.5 * c * pw + 1.875 * c * t0;
        } else {
            return b * pw - b * dc + 1;
        }
    }
}

fn algorithm3(
    p: @Vector(Unit.BLOCK_SIZE, f32),
    t0: @Vector(Unit.BLOCK_SIZE, f32),
    t2: @Vector(Unit.BLOCK_SIZE, f32),
    t3: @Vector(Unit.BLOCK_SIZE, f32),
    w: @Vector(Unit.BLOCK_SIZE, f32),
    a: @Vector(Unit.BLOCK_SIZE, f32),
    b: @Vector(Unit.BLOCK_SIZE, f32),
    c: @Vector(Unit.BLOCK_SIZE, f32),
    dc: @Vector(Unit.BLOCK_SIZE, f32),
    p1: @Vector(Unit.BLOCK_SIZE, f32),
    p2: @Vector(Unit.BLOCK_SIZE, f32),
    p3: @Vector(Unit.BLOCK_SIZE, f32),
) @Vector(Unit.BLOCK_SIZE, f32) {
    if (@reduce(.And, p < w) and @reduce(.And, p >= t3)) {
        const ones: @Vector(Unit.BLOCK_SIZE, f32) = @splat(@as(f32, 1));
        return a * p - a * dc - ones;
    } else if (@reduce(.And, p - w >= t3)) {
        const ones: @Vector(Unit.BLOCK_SIZE, f32) = @splat(@as(f32, 1));
        return b * (p - w) - b * dc + ones;
    }
    const pw = p - w;
    const ones: @Vector(Unit.BLOCK_SIZE, f32) = @splat(@as(f32, 1));
    return @select(
        f32,
        p < w,
        @select(
            f32,
            p >= t3,
            a * p - a * dc - ones,
            @select(
                f32,
                p < t0,
                blk: {
                    const half: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.5);
                    break :blk b * p - b * dc - ones - half * p3 * p * p * p * p;
                },
                @select(
                    f32,
                    p < t2,
                    blk: {
                        const half: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.5);
                        const three_quarters: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.75);
                        const eighth: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.125);
                        break :blk b * p - b * dc + p3 * p * p * p * p - half * p2 * p * p * p + three_quarters * p1 * p * p - half * c * p + eighth * c * t0;
                    },
                    blk: {
                        const half: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.5);
                        const three_pt_five: @Vector(Unit.BLOCK_SIZE, f32) = @splat(3.5);
                        const two_pt_two_five: @Vector(Unit.BLOCK_SIZE, f32) = @splat(2.25);
                        const fract: @Vector(Unit.BLOCK_SIZE, f32) = @splat(1.875);
                        break :blk b * p - b * dc - ones - half * p3 * p * p * p * p + half * p2 * p * p * p - two_pt_two_five * p1 * p * p + three_pt_five * c * p - fract * c * t0;
                    },
                ),
            ),
        ),
        @select(
            f32,
            pw >= t3,
            b * pw - b * dc + ones,
            @select(
                f32,
                p < t0,
                blk: {
                    const half: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.5);
                    break :blk a * pw - a * dc + ones + half * p3 * pw * pw * pw * pw;
                },
                @select(
                    f32,
                    p < t2,
                    blk: {
                        const half: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.5);
                        const three_quarters: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.75);
                        const eighth: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.125);
                        break :blk a * pw - a * dc + ones - p3 * pw * pw * pw * pw + half * p2 * pw * pw * pw - three_quarters * p1 * pw * pw + half * c * pw - eighth * c * t0;
                    },
                    blk: {
                        const half: @Vector(Unit.BLOCK_SIZE, f32) = @splat(0.5);
                        const three_pt_five: @Vector(Unit.BLOCK_SIZE, f32) = @splat(3.5);
                        const two_pt_two_five: @Vector(Unit.BLOCK_SIZE, f32) = @splat(2.25);
                        const fract: @Vector(Unit.BLOCK_SIZE, f32) = @splat(1.875);
                        break :blk a * pw - a * dc + ones + half * p3 * pw * pw * pw * pw - half * p2 * pw * pw * pw + two_pt_two_five * p1 * pw * pw - three_pt_five * c * pw + fract * c * t0;
                    },
                ),
            ),
        ),
    );
}

test "TrianglePTR" {
    var tri_ptr = TrianglePTR();
    var tri_ptr2 = TrianglePTR();
    tri_ptr.init(std.testing.allocator, &.{ .Fast, .Fast, .Fast, .Fast }, &.{ .Slow, .Slow });
    defer tri_ptr.deinit();
    tri_ptr2.init(std.testing.allocator, &.{ .Fast, .Fast, .Fast, .Fast }, &.{ .Fast, .Fast });
    defer tri_ptr2.deinit();
    tri_ptr.next();
    tri_ptr2.next();
}
