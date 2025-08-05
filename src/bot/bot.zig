const std = @import("std");
const ChessBoard = @import("../board.zig");
const Board = ChessBoard.Board;
const Pieces = @import("../piece.zig");
const Piece = Pieces.Piece;
const Color = Pieces.Color;
const PieceType = Pieces.PieceType;
const Move = @import("../move.zig").Move;
const MoveType = @import("../move.zig").MoveType;
pub const ChessBot = struct {
    allocator: std.mem.Allocator,

    pub fn init(self: *ChessBot, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
    }

    pub fn getMove(self: *ChessBot, board: *Board) !Move {
        _ = self;
        const possible_moves = board.possibleMoves;
        return possible_moves[0];
    }
};
