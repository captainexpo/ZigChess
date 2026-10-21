# ZigChess

A chess move generation library written in Zig. For an example of a project that utilizes this, see [ChessEngine](https://www.github.com/captainexpo/ChessEngine)

Requires Zig `0.16.0` or newer.

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

## Building and testing

```sh
zig build test       # run the unit/regression test suite
zig build bench       # build the benchmark executable
zig build bench-run    # build and run the move-generation benchmark
```
## Status

This library is under *very* inactive development; the public API may still change.
