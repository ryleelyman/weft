const std = @import("std");

const VERSION = .{ .major = 0, .minor = 0, .patch = 1 };

pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = log;
};

var timer: std.time.Timer = undefined;

var logfile: std.fs.File = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn main() !void {
    timer = try std.time.Timer.start();
    logfile = try std.fs.createFileAbsolute("/tmp/weft.log", .{});
    defer logfile.close();
    var general_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = general_allocator.allocator();
    defer _ = general_allocator.deinit();

    try print_version();

    try print_goodbye();
}

fn print_goodbye() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("WEFT: goodbye\n", .{});
    try bw.flush();
}

fn print_version() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("WEFT\n", .{});
    try stdout.print("weft version: {d}.{d}.{d}\n", VERSION);
    try bw.flush();
}

fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    log_args: anytype,
) void {
    const scope_prefix = "(" ++ @tagName(scope) ++ ") ";
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;
    const writer = logfile.writer();
    const timestamp = @divTrunc(timer.read(), std.time.ns_per_us);
    writer.print(prefix ++ "+{d}: " ++ format ++ "\n", .{timestamp} ++ log_args) catch return;
}
