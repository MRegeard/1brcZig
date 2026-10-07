const std = @import("std");
const print = std.debug.print;

const FILENAME = "data/measurements.txt";

pub const Values = struct {
    min: f32,
    sum: f32,
    max: f32,
    counts: u32,
};

pub const SortCtx = struct {
    keys: [][]const u8,

    pub fn lessThan(self: @This(), a_index: usize, b_index: usize) bool {
        return std.mem.order(u8, self.keys[a_index], self.keys[b_index]).compare(.lt);
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
    var values = try std.ArrayList(Values).initCapacity(allocator, 10000);
    defer values.deinit(allocator);

    var map = try std.StringArrayHashMapUnmanaged(Values).init(allocator, keys.items, values.items);
    try map.ensureTotalCapacity(allocator, 10000);
    defer map.deinit(allocator);

    while (try reader.takeDelimiter('\n')) |line| {
        const semi_idx = std.mem.findScalar(u8, line, ';').?;
        const name = line[0..semi_idx];
        const val = line[semi_idx + 1 ..];
        //const val_float = try std.fmt.parseFloat(f32, val);
        const val_float = parseFloat(val);
        // print("BYTES: {s}, FLOAT: {}\n", .{val, val_float});

        const gop = map.getOrPutAssumeCapacity(name);

        if (gop.found_existing) {
            gop.value_ptr.min = @min(gop.value_ptr.min, val_float);
            gop.value_ptr.max = @max(gop.value_ptr.max, val_float);
            gop.value_ptr.sum += val_float;
            gop.value_ptr.counts += 1;
        } else {
            const alloc_name = try allocator.dupe(u8, name);
            gop.key_ptr.* = alloc_name;
            gop.value_ptr.* = .{ .min = val_float, .sum = val_float, .max = val_float, .counts = 1};
        }
    }

    map.sort(SortCtx{ .keys = map.keys()});
    const map_count = map.count();

    const stdout = std.Io.File.stdout();
    var stdout_writer = stdout.writer(io, &read_buffer);
    const writer: *std.Io.Writer = &stdout_writer.interface;

    try writer.writeByte('{');
    for (map.keys(), 0..map_count) |k, i| {
        const val = map.get(k).?;
        const denum: f32 = @floatFromInt(val.counts);
        const trunc_frac: f32 = 10.0;
        const mean: f32 = @trunc(val.sum / denum * trunc_frac) / trunc_frac;
        if (i < map_count - 1) {
            try writer.print("{s}={:.1}/{:.1}/{:.1}, ", .{k, val.min, mean, val.max});
        }
        else {
            try writer.print("{s}={:.1}/{:.1}/{:.1}}}", .{k, val.min, mean, val.max});
        }
    }
    try writer.flush();
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
            return - (second_digit * 10 + first_digit + decimal);
        }
        return second_digit * 10 + first_digit + decimal;
    }
    return first_digit + decimal;
//    if (idx == 2) {
//        const integer: f32 = @as(f32, @floatFromInt(bytes[1] - '0')) * 10.0 + @as(f32, @floatFromInt(bytes[2] - '0'));
//        return - (integer + decimal);
//    }
//    if (idx == 1) {
//        if (bytes[0] == '-') {
//            const integer: f32 = @as(f32, @floatFromInt(bytes[1] - '0'));
//            return - (integer + decimal);
//        }
//        const integer: f32 = @as(f32, @floatFromInt(bytes[0] - '0')) * 10.0 + @as(f32, @floatFromInt(bytes[1] - '0'));
//        return integer + decimal;
//    } if (idx == 0){
//        const integer: f32 = @as(f32, @floatFromInt(bytes[0] - '0'));
//        return integer + decimal;
//    }
//    unreachable;
}
