const std = @import("std");

const Piece = @import("piece.zig").Piece;
const Square = @import("board.zig").Square;
const PieceType = @import("piece.zig").PieceType;
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
    promotion_piecetype: ?PieceType = null, // Only used for promotions

    pub fn init(
        from_square: Square,
        to_square: Square,
        move_type: MoveType,
        promotion_piecetype: ?PieceType,
    ) Move {
        if (move_type == .Promotion and promotion_piecetype == null) {
            return error.InvalidMove;
        }
        return Move{
            .from_square = from_square,
            .to_square = to_square,
            .move_type = move_type,
            .promotion_piecetype = promotion_piecetype,
        };
    }

    pub fn toString(self: Move, allocator: std.mem.Allocator) ![]const u8 {
        if (self.promotion_piecetype) |p| {
            return std.fmt.allocPrint(
                allocator,
                "{c}{d}{c}{d}{c}",
                .{
                    'a' + @as(u8, @intCast(self.from_square.file)),
                    @as(u8, self.from_square.rank) + 1,
                    'a' + @as(u8, @intCast(self.to_square.file)),
                    @as(u8, self.to_square.rank) + 1,
                    p.toChar(),
                },
            ) catch unreachable;
        }
        return std.fmt.allocPrint(
            allocator,
            "{c}{d}{c}{d}",
            .{
                'a' + @as(u8, @intCast(self.from_square.file)),
                @as(u8, self.from_square.rank) + 1,
                'a' + @as(u8, @intCast(self.to_square.file)),
                @as(u8, self.to_square.rank) + 1,
            },
        ) catch unreachable;
    }

    pub fn fromUCIStr(str: []const u8) !Move {
        if (str.len < 4) return error.InvalidMove;
        var move = Move{
            .from_square = Square{
                .file = @intCast(str[0] - 'a'),
                .rank = @intCast(str[1] - '0' - 1),
            },
            .to_square = Square{
                .file = @intCast(str[2] - 'a'),
                .rank = @intCast(str[3] - '0' - 1),
            },
            .move_type = .Unknown,
        };

        if (str.len >= 5) {
            // is promotion
            move.promotion_piecetype = try PieceType.fromChar(str[4]);
            move.move_type = .Promotion;
        }
        return move;
    }
};
