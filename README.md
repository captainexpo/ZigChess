# ZigChess

A chess move generation library written in Zig. It provides a bitboard-based
board representation, magic-bitboard sliding piece attacks, full legal move
generation (checks, pins, castling, en passant, promotions), FEN loading, and
Zobrist hashing for repetition detection.

Requires Zig `0.16.0` or newer (see `minimum_zig_version` in `build.zig.zon`).

## Installation

Add ZigChess as a dependency with `zig fetch`:

```sh
zig fetch --save git+https://github.com/captainexpo/ZigChess
```

Then wire it up in your `build.zig`:

```zig
const zchess_dep = b.dependency("zig_chess", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zchess", zchess_dep.module("zchess"));
```

## Quick start

```zig
const std = @import("std");
const zchess = @import("zchess");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // MoveGen builds attack tables once; reuse it across boards.
    var move_gen = zchess.MoveGen.initMoveGeneration();

    var board = try zchess.Board.emptyBoard(allocator, &move_gen);
    defer board.deinit();

    try board.loadFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    // All legal moves for the side to move.
    const moves = try board.getPossibleMoves();
    std.debug.print("{d} legal moves\n", .{moves.len});

    // Play the first move and undo it.
    const undo = try board.makeMove(moves[0]);
    try board.undoMove(undo);
}
```

## Core concepts

### `Board`

`Board` owns the position: piece placement, side to move, castling rights, en
passant state, halfmove/fullmove counters, and a repetition table for
threefold-repetition detection.

- `Board.emptyBoard(allocator, *MoveGen) !Board` — create an empty board bound
  to a `MoveGen` instance. Call `board.deinit()` when done.
- `board.loadFEN(fen: []const u8) !void` — set up a position from FEN.
- `board.getPossibleMoves() ![]Move` — legal moves for the side to move
  (cached until the position changes).
- `board.getCaptureMoves(allocator) ![]Move` — just the capture/en-passant
  moves.
- `board.getPieceMoves(piece_type, allocator) ![]Move` — legal moves for one
  piece type.
- `board.makeMove(move: Move) !MoveUndo` — apply a move, returns state needed
  to undo it.
- `board.undoMove(undo: MoveUndo) !void` — reverse a previously made move.
- `board.isInCheck() !bool`, `board.isInCheckmate() !bool`,
  `board.isInStalemate() !bool` — game-state queries (stalemate also covers
  the fifty-move rule and threefold repetition).
- `board.getZobristHash() u64` — Zobrist hash of the current position.
- `board.toString(allocator) ![]const u8` — ASCII board diagram, useful for
  debugging.
- `board.printDebugInfo()` — dumps turn, bitboards, castling rights, and game
  state to stderr.

### `MoveGen`

`MoveGen` holds the precomputed knight/king attack masks and magic-bitboard
attack tables for sliding pieces. Build one with
`MoveGen.initMoveGeneration()` and share it across boards — it's the
expensive one-time setup step.

Most of the time you'll drive move generation through `Board`, but `MoveGen`
also exposes lower-level helpers directly:

- `move_gen.generateMoves(allocator, *Board, color, options: MoveGenOptions) !MoveGenResult`
- `move_gen.getPossibleAttacksBitboard(allocator, *Board, color) !Bitboard`
- `move_gen.inCheck(*Board, color) !bool`
- `move_gen.getMovesInPosition(allocator, fen, color, piece: ?PieceType) ![]Move`
  — one-shot helper that builds a temporary board from a FEN string.

### `Move`

A `Move` is `from_square`, `to_square`, a `MoveType`
(`Normal`, `DoublePush`, `NoCapture`, `Capture`, `EnPassant`, `Castle`,
`Unknown`), and an optional `promotion_piecetype`.

- `Move.fromUCIStr("e2e4")` / `Move.fromUCIStr("e7e8q")` — parse UCI notation.
- `move.toString(allocator) ![]const u8` — back to UCI notation.
- `move.isCapture() bool` — true for `Capture` and `EnPassant`.
- `board.classifyMove(move) !Move` — infer a move's `MoveType` from the
  current board state, given only `from_square`/`to_square`/promotion.

### `Square`

`Square{ .rank: u3, .file: u3 }` is the 0-indexed (rank, file) coordinate
type used throughout the API (`a1` = rank 0, file 0).

- `Square.new(rank, file)`
- `Square.fromFlat(index: u6)` / `square.toFlat() u6` — convert to/from a
  0..63 board index (`rank * 8 + file`).
- `Square.sq(.e4)` — build a square from the `SquareName` enum.
- `sqidx("e4")` — comptime helper that returns the flat `u6` index for an
  algebraic square name.

### `Piece`, `PieceType`, `Color`

`Piece{ piece_type: PieceType, color: Color }` where `PieceType` is one of
`Pawn`, `Knight`, `Bishop`, `Rook`, `Queen`, `King` and `Color` is `White` or
`Black`.

- `Piece.new(piece_type, color)`
- `Piece.fromChar('N')` / `piece.toString() u8` — FEN-style piece characters
  (uppercase = white, lowercase = black).
- `color.opposite()`

## Building and testing

```sh
zig build test       # run the unit test suite
zig build bench       # build the benchmark executable
zig build bench-run    # build and run the move-generation benchmark
```
## Status

This library is under *very* inactive development; the public API may still change (though unlikely).
