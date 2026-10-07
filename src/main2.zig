const std = @import("std");
const print = std.debug.print;

const FILENAME = "data/measurements.txt";

pub const Values = struct {
    min: i32,
    sum: i32,
    max: i32,
    counts: i32,
};

pub const SortCtx = struct {
    keys: []const []const u8,

    pub fn lessThan(self: @This(), a_index: usize, b_index: usize) bool {
        return std.mem.lessThan(u8, self.keys[a_index], self.keys[b_index]);
    }
};

pub fn main() !void {
    @setRuntimeSafety(false);
    @setFloatMode(.optimized);

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    const io: std.Io = threaded.io();

    const file = try std.Io.Dir.cwd().openFile(io, FILENAME, .{});
    defer file.close(io);

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const reader: *std.Io.Reader = &file_reader.interface;

    var keys = try std.ArrayList([]const u8).initCapacity(allocator, 10000);
    defer keys.deinit(allocator);

    var map: std.StringHashMapUnmanaged(Values) = .empty;
    defer map.deinit(allocator);
    try map.ensureTotalCapacity(allocator, 10000);

    while (try reader.takeDelimiter('\n')) |line| {
        const semi_idx = std.mem.findScalar(u8, line, ';').?;
        const name = line[0..semi_idx];
        const val = line[semi_idx + 1 ..];
        const val_int = parseNumber(val);

        const gop = map.getOrPutAssumeCapacity(name);

        if (gop.found_existing) {
            gop.value_ptr.min = @min(gop.value_ptr.min, val_int);
            gop.value_ptr.max = @max(gop.value_ptr.max, val_int);
            gop.value_ptr.sum += val_int;
            gop.value_ptr.counts += 1;
        } else {
            const alloc_name = try allocator.dupe(u8, name);
            keys.appendAssumeCapacity(alloc_name);
            gop.key_ptr.* = alloc_name;
            gop.value_ptr.* = .{ .min = val_int, .sum = val_int, .max = val_int, .counts = 1 };
        }
    }

    const n_len = keys.items.len;
    var order: [10_000]usize = undefined;
    for (order[0..n_len], 0..) |*o, i| o.* = i;

    std.mem.sortUnstable(usize, order[0..n_len], SortCtx{ .keys = keys.items }, SortCtx.lessThan);

    const stdout = std.Io.File.stdout();
    var stdout_writer = stdout.writer(io, &read_buffer);
    const writer: *std.Io.Writer = &stdout_writer.interface;

    try writer.writeByte('{');
    for (order[0..n_len], 0..) |i, pos| {
        const k = keys.items[i];
        const val = map.get(k).?;
        const denum: f64 = @floatFromInt(val.counts);
        const sum_f64: f64 = @floatFromInt(val.sum);
        const mean: f64 = sum_f64 / denum;
        const mean_round: f64 = @round(mean) / 10.0;
        const min_f64: f64 = @as(f64, @floatFromInt(val.min)) / 10.0;
        const max_f64: f64 = @as(f64, @floatFromInt(val.max)) / 10.0;
        if (pos < n_len - 1) {
            try writer.print("{s}={:.1}/{:.1}/{:.1}, ", .{ k, min_f64, mean_round, max_f64 });
        } else {
            try writer.print("{s}={:.1}/{:.1}/{:.1}}}", .{ k, max_f64, mean_round, max_f64 });
        }
    }
    try writer.flush();
    std.process.exit(0);
}

pub fn parseNumber(bytes: []const u8) i32 {
    var idx = bytes.len - 1;
    const decimal: i32 = bytes[idx] - '0';

    idx -= 2;

    const first_digit: i32 = bytes[idx] - '0';

    if (idx != 0) {
        idx -= 1;
        if (bytes[idx] == '-') {
            return -(first_digit * 10 + decimal);
        }

        const second_digit: i32 = bytes[idx] - '0';
        if (idx != 0) {
            return -(second_digit * 100 + first_digit * 10 + decimal);
        }
        return second_digit * 100 + first_digit * 10 + decimal;
    }
    return first_digit * 10 + decimal;
}

pub fn parseFloat(bytes: []const u8) f32 {
    @setFloatMode(.optimized);
    @setRuntimeSafety(false);
    //const idx_end = bytes.len - 1;
    var idx = bytes.len - 1;
    const decimal: f32 = @as(f32, @floatFromInt(bytes[idx] - '0')) / 10.0;

    idx -= 2;

    const first_digit: f32 = @floatFromInt(bytes[idx] - '0');
    if (idx != 0) {
        idx -= 1;
        if (bytes[idx] == '-') {
            return -(first_digit + decimal);
        }
        const second_digit: f32 = @floatFromInt(bytes[idx] - '0');
        if (idx != 0) {
            return -(second_digit * 10 + first_digit + decimal);
        }
        return second_digit * 10 + first_digit + decimal;
    }
    return first_digit + decimal;
}
