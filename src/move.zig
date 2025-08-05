const std = @import("std");

const Piece = @import("piece.zig").Piece;
const Square = @import("board.zig").Square;

pub const MoveType = enum {
    Normal,
    DoublePush,
    NoCapture,
    Capture,
    Promotion,
    EnPassant,
    Castle,
    Unknown,
};

pub const Move = struct {
    from_square: Square,
    to_square: Square,
    move_type: MoveType,
    promotion_piece: ?Piece = null, // Only used for promotions
    captured_piece: ?Piece = null, // Only used for captures

    pub fn init(
        from_square: Square,
        to_square: Square,
        move_type: MoveType,
        promotion_piece: ?Piece,
        captured_piece: ?Piece,
    ) Move {
        return Move{
            .from_square = from_square,
            .to_square = to_square,
            .move_type = move_type,
            .promotion_piece = promotion_piece,
            .captured_piece = captured_piece,
        };
    }

    pub fn toString(self: Move, allocator: std.mem.Allocator) ![]const u8 {
        if (self.promotion_piece) |p| {
            return std.fmt.allocPrint(
                allocator,
                "{c}{d}{c}{d}{c}",
                .{
                    'a' + self.from_square.file,
                    self.from_square.rank + 1,
                    'a' + self.to_square.file,
                    self.to_square.rank + 1,
                    p.toString(),
                },
            ) catch unreachable;
        }
        return std.fmt.allocPrint(
            allocator,
            "{c}{d}{c}{d}",
            .{
                'a' + self.from_square.file,
                self.from_square.rank + 1,
                'a' + self.to_square.file,
                self.to_square.rank + 1,
            },
        ) catch unreachable;
    }

    pub fn fromUCIStr(str: []const u8) !Move {
        if (str.len < 4) return error.InvalidMove;
        var move = Move{
            .from_square = Square{
                .file = str[0] - 'a',
                .rank = str[1] - '0' - 1,
            },
            .to_square = Square{
                .file = str[2] - 'a',
                .rank = str[3] - '0' - 1,
            },
            .move_type = .Unknown,
        };

        if (str.len >= 5) {
            // is promotion
            move.promotion_piece = try Piece.fromChar(str[4]);
            move.move_type = .Promotion;
        }
        return move;
    }
};
