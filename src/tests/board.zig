const std = @import("std");
const Chess = @import("../board.zig");
const Board = Chess.Board;
const pieces = @import("../piece.zig");
const Move = @import("../move.zig").Move;
const MoveType = @import("../move.zig").MoveType;
const Movegen = @import("../movegen.zig").MoveGen;
test "fen loading" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var movegen = Movegen.initMoveGeneration();
    var board = try Board.emptyBoard(allocator, &movegen);
    defer board.deinit();

    try board.loadFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    const board_str = try board.toString(allocator);
    defer allocator.free(board_str);

    try std.testing.expectEqualSlices(u8,
        \\r n b q k b n r 
        \\p p p p p p p p 
        \\. . . . . . . . 
        \\. . . . . . . . 
        \\. . . . . . . . 
        \\. . . . . . . . 
        \\P P P P P P P P 
        \\R N B Q K B N R 
        \\
    , board_str);
    std.testing.expectEqual(board.turn, pieces.Color.White) catch |err| {
        std.log.err("Turn parsing failed, expected {s}, got {s}\n", .{ @tagName(pieces.Color.White), @tagName(board.turn) });
        return err;
    };
    std.testing.expectEqual(0b1111, board.castlingRights) catch |err| {
        std.log.err("Castling rights parsing failed, expected {b:0>4}, got {b:0>4}\n", .{ 0b1111, board.castlingRights });
        return err;
    };
}

test "index from square name" {
    const names = comptime [_][]const u8{ "a1", "b3", "g8", "h4" };

    const indexes = comptime [_]u6{ 0, 17, 62, 31 };

    inline for (names, indexes) |square, idx| {
        const i = Chess.sqidx(square);
        std.testing.expectEqual(idx, i) catch |err| {
            std.log.err("Expected index {d} from {s}, but instead got {d}\n", .{ idx, square, i });
            return err;
        };
    }
}
test "classify moves" {
    const board_position = "r3k3/8/8/3Q1Pp1/8/8/P1p5/4K2R w Kq - 0 1";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var movegen = Movegen.initMoveGeneration();
    var board = try Board.emptyBoard(allocator, &movegen);
    defer board.deinit();
    try board.loadFEN(board_position);
    const s = struct { Move, MoveType };
    const moves = comptime [_]s{
        .{ Move.fromUCIStr("c2c1Q") catch unreachable, MoveType.NoCapture },
        .{ Move.fromUCIStr("d5a8") catch unreachable, MoveType.Capture },
        .{ Move.fromUCIStr("e1e2") catch unreachable, MoveType.Normal },
        .{ Move.fromUCIStr("e1g1") catch unreachable, MoveType.Castle },
        .{ Move.fromUCIStr("e8c8") catch unreachable, MoveType.Castle },
        .{ Move.fromUCIStr("f5g6") catch unreachable, MoveType.EnPassant },
        .{ Move.fromUCIStr("a2a4") catch unreachable, MoveType.DoublePush },
        .{ Move.fromUCIStr("a2a3") catch unreachable, MoveType.NoCapture },
    };

    inline for (moves) |mt| {
        const move, const move_type = mt;

        const classified_move = board.classifyMove(move) catch |err| {
            std.log.err("Failed to classify move {s}: {!}\n", .{ move.toString(allocator) catch unreachable, err });
            return err;
        };
        std.log.info("Classifying move {s} as {s}\n", .{ move.toString() catch unreachable, @tagName(classified_move.move_type) });
        std.testing.expectEqual(move_type, classified_move.move_type) catch |err| {
            std.log.err("Expected move type {s}, but got {s}\n", .{ @tagName(move_type), @tagName(classified_move.move_type) });
            return err;
        };
    }
}
