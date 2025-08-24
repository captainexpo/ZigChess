const std = @import("std");

const Bitboard = @import("../bitboards.zig").Bitboard;
const Board = @import("../board.zig").Board;
const Square = @import("../board.zig").Square;
const SName = @import("../board.zig").SquareName;
const Move = @import("../move.zig").Move;
const MoveGen = @import("../movegen.zig").MoveGen;
const Piece = @import("../piece.zig").Piece;
const PieceType = @import("../piece.zig").PieceType;
const Color = @import("../piece.zig").Color;
const Utils = @import("../utils.zig");

test "rook movement mask" {
    var movegen = MoveGen.initMoveGeneration();
    const mask = movegen.createRookMovementMask(0); // A1
    const expected: Bitboard = 0x1010101010101fe; // All squares in A file and 1st rank

    std.testing.expectEqual(expected, mask) catch |err| {
        std.log.err("Rook movement mask test failed: {!}\n", .{err});
        return err;
    };
}

test "king move generation" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var movegen = MoveGen.initMoveGeneration();

    const moves = try movegen.getMovesInPosition(allocator, "8/8/8/8/8/8/8/1K6 w - - 0 1", Color.White, PieceType.King);

    const ex = "b1a1 b1a2 b1b2 b1c1 b1c2";
    const actual = try MoveGen.movesToString(allocator, moves);

    std.testing.expectEqualSlices(u8, ex, actual) catch |err| {
        std.log.err("\\e[0;31m[TEST FAIL]\\e[0m: King movegen failed!\n", .{});
        arena.deinit();
        return err;
    };
}

test "knight move generation" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var movegen = MoveGen.initMoveGeneration();

    const moves = try movegen.getMovesInPosition(allocator, "8/8/8/N7/8/8/8/8 w - - 0 1", Color.White, PieceType.Knight);
    const ex = "a5b3 a5b7 a5c4 a5c6";
    const actual = try MoveGen.movesToString(allocator, moves);

    std.testing.expectEqualSlices(u8, ex, actual) catch |err| {
        std.log.err("\\e[0;31m[TEST FAIL]\\e[0m: Knight movegen failed!\n", .{});
        return err;
    };
}

test "pawn move generation" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var movegen = MoveGen.initMoveGeneration();

    const moves = try movegen.getMovesInPosition(allocator, "8/8/8/4r3/2r1P3/3P4/5P2/8 w - - 0 1", Color.White, PieceType.Pawn);
    const ex = "d3c4 d3d4 f2f3 f2f4";
    const actual = try MoveGen.movesToString(allocator, moves);

    std.testing.expectEqualSlices(u8, ex, actual) catch |err| {
        std.log.err("\\e[0;31m[TEST FAIL]\\e[0m: Pawn movegen failed!\n", .{});
        return err;
    };
}

test "rook move generation" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var movegen = MoveGen.initMoveGeneration();

    const moves = try movegen.getMovesInPosition(allocator, "4n3/8/8/3qR1B1/8/8/8/8 w - - 0 1", Color.White, PieceType.Rook);
    const ex = "e5d5 e5e1 e5e2 e5e3 e5e4 e5e6 e5e7 e5e8 e5f5";
    const actual = try MoveGen.movesToString(allocator, moves);

    std.testing.expectEqualSlices(u8, ex, actual) catch |err| {
        std.log.err("\\e[0;31m[TEST FAIL]\\e[0m: Rook movegen failed!\n", .{});
        return err;
    };
}

test "bishop move generation" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var movegen = MoveGen.initMoveGeneration();

    const moves = try movegen.getMovesInPosition(allocator, "8/8/5r2/2Q5/3B4/8/8/8 w - - 0 1", Color.White, PieceType.Bishop);
    const ex = "d4a1 d4b2 d4c3 d4e3 d4e5 d4f2 d4f6 d4g1";
    const actual = try MoveGen.movesToString(allocator, moves);

    std.testing.expectEqualSlices(u8, ex, actual) catch |err| {
        std.log.err("\\e[0;31m[TEST FAIL]\\e[0m: Bishop movegen failed!\n", .{});
        return err;
    };
}

test "queen move generation" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var movegen = MoveGen.initMoveGeneration();

    const moves = try movegen.getMovesInPosition(allocator, "8/2b5/8/2Q4r/3B4/8/8/8 w - - 0 1", Color.White, PieceType.Queen);
    const ex = "c5a3 c5a5 c5a7 c5b4 c5b5 c5b6 c5c1 c5c2 c5c3 c5c4 c5c6 c5c7 c5d5 c5d6 c5e5 c5e7 c5f5 c5f8 c5g5 c5h5";
    const actual = try MoveGen.movesToString(allocator, moves);

    std.testing.expectEqualSlices(u8, ex, actual) catch |err| {
        std.log.err("\\e[0;31m[TEST FAIL]\\e[0m: Queen movegen failed!\n", .{});
        return err;
    };
}

test "comprehensive move generation" {}
