const std = @import("std");

pub const Bitboard = u64;

pub fn new() Bitboard {
    return 0;
}

pub fn set(board: Bitboard, square: u8) void {
    board |= (1 << square);
}

pub fn clear(board: *Bitboard, square: u8) void {
    board &= ~(1 << square);
}

pub fn isSet(board: Bitboard, square: u8) bool {
    return (board & (1 << square)) != 0;
}

pub fn toString(allocator: std.mem.Allocator, board: Bitboard) []const u8 {
    return std.fmt.allocPrint(allocator, "{x}\n{x}\n{x}\n{x}\n{x}\n{x}\n{x}\n{x}", .{
        board & 0xFF,
        (board >> 8) & 0xFF,
        (board >> 16) & 0xFF,
        (board >> 24) & 0xFF,
        (board >> 32) & 0xFF,
        (board >> 40) & 0xFF,
        (board >> 48) & 0xFF,
        (board >> 56) & 0xFF,
    }) catch "error";
}
