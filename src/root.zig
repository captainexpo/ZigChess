const std = @import("std");

const MoveGen = @import("tests/movegen.zig");
const Board = @import("tests/board.zig");
const Move = @import("tests/move.zig");

pub const log_level: std.log.Level = .debug;

test {
    _ = MoveGen;
    _ = Board;
    _ = Move;
}
