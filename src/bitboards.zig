const std = @import("std");

pub const Bitboard = u64;

pub var zobristPieces: [64][12]u64 = undefined;
pub var zobristCastling: [16]u64 = undefined;
pub var zobristEnPassant: [64]u64 = undefined;
pub var zobristTurn: u64 = undefined;
pub fn zobristInit() void {
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));

    for (0..64) |sq| {
        for (0..12) |p| {
            zobristPieces[sq][p] = rng.random().int(u64);
        }
    }
    for (0..16) |cr| {
        zobristCastling[cr] = rng.random().int(u64);
    }
    for (0..64) |sq| {
        zobristEnPassant[sq] = rng.random().int(u64);
    }
    zobristTurn = rng.random().int(u64);
}
