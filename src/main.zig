const std = @import("std");
const posix = std.posix;

//const FILEPATH = "data/measurements_test.txt";
const FILEPATH = "data/measurements.txt";

const MMPROT = posix.PROT.READ;
const MMFLAGS = posix.MAP {
    .TYPE = .PRIVATE,
};

const Values = struct { min: f32, sum: f32, max: f32, counts: u32};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try std.fs.cwd().openFile(FILEPATH, .{});
    defer file.close();

    const stat = try file.stat();
    const size = std.math.cast(usize, stat.size) orelse return error.FileTooBig;

    const mapped = try posix.mmap(null, size, MMPROT, MMFLAGS, file.handle, 0);
    defer posix.munmap(mapped);

    const bytes: []const u8 = mapped[0..size];

    var map = std.StringArrayHashMap(Values).init(allocator);
    defer map.deinit();
    try map.ensureTotalCapacity(10000);

    var bytesIter = std.mem.tokenizeAny(u8, bytes, "\n");

    while (bytesIter.next()) |line| {
        var iter = std.mem.splitScalar(u8, line, ';');
        const raw_key = iter.next().?;
        const val = iter.next().?;
        const val_float = parseFloat(val);
        const gop = try map.getOrPut(raw_key);
        if (gop.found_existing) {
            gop.value_ptr.*.min = @min(gop.value_ptr.*.min, val_float);
            gop.value_ptr.*.max = @max(gop.value_ptr.*.max, val_float);
            gop.value_ptr.*.sum += val_float;
            gop.value_ptr.*.counts += 1;
        }
        else {
            const key = try allocator.dupe(u8, raw_key);
            gop.key_ptr.* = key;
            gop.value_ptr.* = .{ .min = val_float, .sum = val_float, .max = val_float, .counts = 1 };
        }
    }

    const sortContext = struct {
        keys: [][]const u8,

        pub fn lessThan(self: @This(), a_index: usize, b_index: usize) bool {
            return std.mem.order(u8, self.keys[a_index], self.keys[b_index]).compare(.lt);
        }
    };

    map.sort(sortContext{ .keys = map.keys() });

    std.debug.print("{{", .{});

    for (map.keys(), 0..map.count()) |k, i| {
        const val = map.get(k).?;
        const denum: f32 = @floatFromInt(val.counts);
        const trunc_frac: f32 = 10.0;
        const mean: f32 = @trunc(val.sum / denum * trunc_frac) / trunc_frac;
        if (i < map.count() - 1) {
            std.debug.print("{s}={:.1}/{:.1}/{:.1}, ", .{ k, val.min, mean, val.max});
        }
        else {
            std.debug.print("{s}={:.1}/{:.1}/{:.1}", .{ k, val.min, mean, val.max});
            std.debug.print("}}", .{});
        }
    }

}

fn parseFloat(bytes: []const u8) f32 {
    var res: f32 = 0;

    var i = bytes.len - 1;
    const decimal: f32 = @floatFromInt(bytes[i] - '0');
    res += decimal / 10;
    i -= 2;
    const firstDigit:f32 = @floatFromInt(bytes[i] - '0');
    res += firstDigit;
    if (i != 0) {
        i -= 1;
        if (bytes[i] == '-') {
            res *= -1;
            return res;
        }
        const tensDigit: f32 = @floatFromInt(bytes[i] - '0');
        res += tensDigit * 10.0;
    }
    if (i != 0) {
        res *= -1;
    }
    return res;
}

