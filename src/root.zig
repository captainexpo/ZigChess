const std = @import("std");

pub const Board = @import("board.zig").Board;
pub const MoveGen = @import("movegen.zig").MoveGen;
pub const Piece = @import("piece.zig").Piece;
pub const PieceType = @import("piece.zig").PieceType;
pub const Color = @import("piece.zig").Color;
pub const Move = @import("move.zig").Move;
pub const MoveType = @import("move.zig").MoveType;
pub const Square = @import("board.zig").Square;
pub const Utils = @import("utils.zig");

const test_MoveGen = @import("tests/movegen.zig");
const test_Board = @import("tests/board.zig");
const test_Move = @import("tests/move.zig");

test {
    _ = test_MoveGen;
    _ = test_Board;
    _ = test_Move;
}
