const std = @import("std");

pub fn forEachSetBit(bitboard: u64, callback: fn (u6) void) void {
    var bb = bitboard;
    var index: u8 = 0;

    while (bb != 0) {
        if (bb & 1 != 0) {
            callback(index);
        }
        bb >>= 1;
        index += 1;
    }
}

pub fn pprintBitboard(bitboard: u64, empty: u8, filled: u8) !void {
    for (0..8) |r| { // from row 7 (top) to row 0 (bottom)
        const row = 7 - r;
        for (0..8) |col| {
            const i = row * 8 + col;
            if ((bitboard & (@as(u64, 1) << @truncate(i))) != 0) {
                std.debug.print("{c} ", .{filled});
            } else {
                std.debug.print("{c} ", .{empty});
            }
        }
        std.debug.print("\n", .{});
    }
}

pub fn u8lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
