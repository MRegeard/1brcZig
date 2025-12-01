const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try std.fs.cwd().openFile("data/measurements.txt", .{});
    defer file.close();

    var buf: [1000]u8 = undefined;
    var file_reader = file.reader(&buf);
    const reader: *std.Io.Reader = &file_reader.interface;

    const Values = struct { min: f32, sum: f32, max: f32, counts: u32};

    var map = std.StringArrayHashMap(Values).init(allocator);
    defer map.deinit();

    while (try reader.takeDelimiter('\n')) |line| {
        var iter = std.mem.splitAny(u8, line, ";");
        const key = try allocator.dupe(u8, iter.next().?);
        const val = iter.next().?;
        if (map.contains(key) == false) {
            const val_float = try std.fmt.parseFloat(f32, val);
            try map.put(key, .{ .min = val_float, .sum = val_float, .max = val_float, .counts = 1 });
        }
        else {
            const val_float = try std.fmt.parseFloat(f32, val);
            const value_ptr: *Values = map.getPtr(key).?;
            value_ptr.*.min = @min(value_ptr.*.min, val_float);
            value_ptr.*.max = @max(value_ptr.*.max, val_float);
            value_ptr.*.sum += val_float;
            value_ptr.*.counts += 1;
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
        if (i < map.count()) {
            std.debug.print("{s}={}/{}/{}, ", .{ k, val.min, mean, val.max});
        }
        else {
            std.debug.print("{s}={}/{d:.1}/{}", .{ k, val.min, mean, val.max});
            std.debug.print("}}", .{});
        }
    }

}

