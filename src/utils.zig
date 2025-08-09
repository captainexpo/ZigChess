const std = @import("std");

pub fn printBitboard(bitboard: u64, empty: u8, filled: u8) !void {
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
        std.debug.print("{d}\n", .{row + 1});
    }
    std.debug.print("a b c d e f g h\n", .{});
}

pub fn u8lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
