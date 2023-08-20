const c = @cImport(@cInclude("soundio/soundio.h"));
const std = @import("std");
const panic = std.debug.panic;

fn sio_err(err: c_int) !void {
    switch (err) {
        c.SoundIoErrorNone => {},
        c.SoundIoErrorNoMem => return error.NoMem,
        c.SoundIoErrorInitAudioBackend => return error.InitAudioBackend,
        c.SoundIoErrorSystemResources => return error.SystemResources,
        c.SoundIoErrorOpeningDevice => return error.OpeningDevice,
        c.SoundIoErrorNoSuchDevice => return error.NoSuchDevice,
        c.SoundIoErrorInvalid => return error.Invalid,
        c.SoundIoErrorBackendUnavailable => return error.BackendUnavailable,
        c.SoundIoErrorStreaming => return error.Streaming,
        c.SoundIoErrorIncompatibleDevice => return error.IncompatibleDevice,
        c.SoundIoErrorNoSuchClient => return error.NoSuchClient,
        c.SoundIoErrorIncompatibleBackend => return error.IncompatibleBackend,
        c.SoundIoErrorBackendDisconnected => return error.BackendDisconnected,
        c.SoundIoErrorInterrupted => return error.Interrupted,
        c.SoundIoErrorUnderflow => return error.Underflow,
        c.SoundIoErrorEncodingString => return error.EncodingString,
        else => panic("unknown error code {d}!", .{err}),
    }
}

var seconds_offset: f32 = 0;

fn write_callback(
    maybe_outstream: ?*c.SoundIoOutStream,
    frame_count_min: c_int,
    frame_count_max: c_int,
) callconv(.C) void {
    _ = frame_count_min;
    const out = maybe_outstream.?;
    const layout = &out.layout;
    const float_sample_rate = out.sample_rate;
    const seconds_per_frame = 1.0 / @as(f32, @floatFromInt(float_sample_rate));
    var frames_left = frame_count_max;

    while (frames_left > 0) {
        var frame_count = frames_left;

        var areas: [*c]c.SoundIoChannelArea = undefined;
        sio_err(c.soundio_outstream_begin_write(
            maybe_outstream,
            &areas,
            &frame_count,
        )) catch |err| panic("write failed: {s}", .{@errorName(err)});

        if (frame_count == 0) break;

        const pitch = 440.0;
        const radians_per_second = pitch * 2.0 * std.math.pi;
        {
            var frame: c_int = 0;
            while (frame < frame_count) : (frame += 1) {
                const sample = std.math.sin((seconds_offset + @as(f32, @floatFromInt(frame)) *
                    seconds_per_frame) * radians_per_second);
                {
                    var channel: usize = 0;
                    while (channel < @as(usize, @intCast(layout.channel_count))) : (channel += 1) {
                        const channel_ptr = areas[channel].ptr.?;
                        const sample_ptr = &channel_ptr[@as(usize, @intCast(areas[channel].step * frame))];
                        @as(*f32, @ptrCast(@alignCast(sample_ptr))).* = sample;
                    }
                }
            }
        }
        seconds_offset += seconds_per_frame * @as(f32, @floatFromInt(frame_count));

        sio_err(
            c.soundio_outstream_end_write(maybe_outstream),
        ) catch |err| panic("end write failed: {s}", .{@errorName(err)});

        frames_left -= frame_count;
    }
}

const logger = std.log.scoped(.soundio);
var soundio: *c.struct_SoundIo = undefined;
var device: *c.struct_SoundIoDevice = undefined;
var outstream: *c.struct_SoundIoOutStream = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn init(alloc_pointer: std.mem.Allocator) !void {
    allocator = alloc_pointer;
    soundio = c.soundio_create() orelse panic("OOM!", .{});
    soundio.app_name = "weft";

    sio_err(
        c.soundio_connect(soundio),
    ) catch |err| panic("unable to connect: {s}", .{@errorName(err)});

    c.soundio_flush_events(soundio);

    const default_output_idx = c.soundio_default_output_device_index(soundio);
    if (default_output_idx < 0) panic("no output device found", .{});

    device = c.soundio_get_output_device(soundio, default_output_idx) orelse panic("OOM!", .{});

    logger.info("Output device: {s}\n", .{device.name.?});

    outstream = c.soundio_outstream_create(device) orelse panic("OOM!", .{});

    outstream.format = c.SoundIoFormatFloat32NE;
    outstream.write_callback = write_callback;

    sio_err(
        c.soundio_outstream_open(outstream),
    ) catch |err| panic("unable to open stream: {s}", .{@errorName(err)});
    sio_err(
        c.soundio_outstream_start(outstream),
    ) catch |err| panic("unable to start stream: {s}", .{@errorName(err)});
}

pub fn run() void {
    while (true) c.soundio_wait_events(soundio);
}

pub fn deinit() void {
    defer c.soundio_destroy(soundio);
    defer c.soundio_device_unref(device);
    defer c.soundio_outstream_destroy(outstream);
}
