const std = @import("std");

const Board = @import("../board.zig").Board;
const Move = @import("../move.zig").Move;
const MoveType = @import("../move.zig").MoveType;
const MoveGen = @import("../movegen.zig").MoveGen;
const PieceType = @import("../piece.zig").PieceType;
const Color = @import("../piece.zig").Color;

const STARTPOS = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

// MoveGen's attack tables are ~2.5MB, so keep it off the stack.
fn initMoveGen() !*MoveGen {
    const mg = try std.testing.allocator.create(MoveGen);
    mg.* = MoveGen.initMoveGeneration();
    return mg;
}

fn play(board: *Board, uci: []const u8) !Board.MoveUndo {
    const move = try board.classifyMove(try Move.fromUCIStr(uci));
    return board.makeMove(move);
}

fn perft(mg: *MoveGen, board: *Board, depth: u32) !u64 {
    if (depth == 0) return 1;

    // Use a local buffer so child generations can't clobber this node's moves.
    var buf: [1 << 14]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const result = try mg.generateMoves(fba.allocator(), board, board.turn, .{});
    if (depth == 1) return result.moves.len;

    var nodes: u64 = 0;
    for (result.moves) |move| {
        const hash_before = board.getZobristHash();
        const undo = try board.makeMove(move);
        nodes += try perft(mg, board, depth - 1);
        try board.undoMove(undo);
        try std.testing.expectEqual(hash_before, board.getZobristHash());
    }
    return nodes;
}

fn expectPerft(fen: []const u8, depth: u32, expected: u64) !void {
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);
    var board = try Board.emptyBoard(std.testing.allocator, mg);
    defer board.deinit();
    try board.loadFEN(fen);

    try std.testing.expectEqual(expected, try perft(mg, &board, depth));
}

// Perft (reference counts from chessprogramming.org/Perft_Results)

test "perft startpos" {
    try expectPerft(STARTPOS, 4, 197_281);
}

test "perft kiwipete" {
    try expectPerft("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 3, 97_862);
}

test "perft position 3 (en passant pins)" {
    try expectPerft("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 5, 674_624);
}

test "perft position 4 (promotions)" {
    try expectPerft("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3, 9_467);
}

test "perft position 5" {
    try expectPerft("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 3, 62_379);
}

test "perft position 6" {
    try expectPerft("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 3, 89_890);
}

// En passant legality

test "en passant that exposes king along the rank is illegal" {
    // exd3 e.p. removes both pawns from rank 4, exposing a4 to the queen on h4.
    try expectPerft("8/8/8/8/k2Pp2Q/8/8/3K4 b - d3 0 1", 1, 6);
}

// Repetition
test "threefold repetition is detected" {
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);
    var board = try Board.emptyBoard(std.testing.allocator, mg);
    defer board.deinit();
    try board.loadFEN(STARTPOS);

    const shuffle = [_][]const u8{ "g1f3", "g8f6", "f3g1", "f6g8" };
    for (shuffle) |uci| _ = try play(&board, uci);
    try std.testing.expect(!try board.isInStalemate()); // startpos seen twice

    for (shuffle) |uci| _ = try play(&board, uci);
    try std.testing.expect(try board.isInStalemate()); // startpos seen three times
}

test "make/undo leaves the repetition table unchanged" {
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);
    var board = try Board.emptyBoard(std.testing.allocator, mg);
    defer board.deinit();
    try board.loadFEN(STARTPOS);

    const hash = board.getZobristHash();
    const count_before = board.repetitionTable.count();

    for (0..3) |_| {
        const undo = try play(&board, "e2e4");
        try board.undoMove(undo);
    }

    try std.testing.expectEqual(count_before, board.repetitionTable.count());
    try std.testing.expectEqual(@as(?i32, 1), board.repetitionTable.get(hash));
}

test "loadFEN resets the repetition table" {
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);
    var board = try Board.emptyBoard(std.testing.allocator, mg);
    defer board.deinit();

    try board.loadFEN(STARTPOS);
    try board.loadFEN(STARTPOS);
    try board.loadFEN(STARTPOS);

    try std.testing.expect(!try board.isInStalemate());
}

// Castling rights
test "capturing a rook on its home square removes that castling right" {
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);
    var board = try Board.emptyBoard(std.testing.allocator, mg);
    defer board.deinit();
    try board.loadFEN("4k2r/r7/8/8/8/8/1B6/4K3 w k - 0 1");

    _ = try play(&board, "b2h8"); // Bxh8
    try std.testing.expectEqual(@as(u4, 0), board.castlingRights);

    // Bring a different rook back to h8; castling must still be unavailable.
    for ([_][]const u8{ "a7h7", "h8c3", "h7h8", "c3d4" }) |uci| _ = try play(&board, uci);
    const moves = try board.getPossibleMovesAlloc(std.testing.allocator);
    defer std.testing.allocator.free(moves);
    for (moves) |move| {
        try std.testing.expect(move.move_type != MoveType.Castle);
    }
}

// API behaviour
test "move slice from getPossibleMoves survives make/undo" {
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);
    var board = try Board.emptyBoard(std.testing.allocator, mg);
    defer board.deinit();
    try board.loadFEN(STARTPOS);

    const moves = try board.getPossibleMovesAlloc(std.testing.allocator);
    defer std.testing.allocator.free(moves);

    const first = moves[0];

    const undo = try board.makeMove(moves[0]);
    const moves2 = try board.getPossibleMovesAlloc(std.testing.allocator);
    defer std.testing.allocator.free(moves2);

    try board.undoMove(undo);

    try std.testing.expectEqual(first, moves[0]);
}

test "movesToString handles promotions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);

    const moves = try mg.getMovesInPosition(allocator, "8/P7/8/8/8/8/8/k6K w - - 0 1", Color.White, PieceType.Pawn);
    const actual = try MoveGen.movesToString(allocator, moves);

    try std.testing.expectEqualSlices(u8, "a7a8b a7a8n a7a8q a7a8r", actual);
}

test "specific-piece generation respects pins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);

    const moves = try mg.getMovesInPosition(allocator, "4r3/8/8/8/8/8/4R3/4K3 w - - 0 1", Color.White, PieceType.Rook);
    const actual = try MoveGen.movesToString(allocator, moves);

    try std.testing.expectEqualSlices(u8, "e2e3 e2e4 e2e5 e2e6 e2e7 e2e8", actual);
}

test "getCaptureMoves excludes king captures of defended pieces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);

    var board = try Board.emptyBoard(std.testing.allocator, mg);
    defer board.deinit();
    try board.loadFEN("4k3/8/8/8/8/2b5/3p4/4K3 w - - 0 1"); // d2 defended by Bc3

    const captures = try mg.getCaptureMoves(allocator, &board, Color.White);
    try std.testing.expectEqual(@as(usize, 0), captures.len);
}

test "Board.getPieceMoves uses the side to move and respects pins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const mg = try initMoveGen();
    defer std.testing.allocator.destroy(mg);

    var board = try Board.emptyBoard(std.testing.allocator, mg);
    defer board.deinit();

    // White to move: the e2 rook is pinned to the king by the e8 rook.
    try board.loadFEN("4r3/8/8/8/8/8/4R3/4K3 w - - 0 1");
    const white_moves = try board.getPieceMoves(PieceType.Rook, allocator);
    const actual = try MoveGen.movesToString(allocator, white_moves);
    try std.testing.expectEqualSlices(u8, "e2e3 e2e4 e2e5 e2e6 e2e7 e2e8", actual);

    // Black to move: only the black rook on e8 should move.
    try board.loadFEN("4r3/8/8/8/8/8/4R3/4K3 b - - 0 1");
    const black_moves = try board.getPieceMoves(PieceType.Rook, allocator);
    try std.testing.expect(black_moves.len > 0);
    for (black_moves) |m| try std.testing.expectEqual(@as(u6, 60), m.from_square.toFlat());
}
