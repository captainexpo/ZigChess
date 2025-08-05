const std = @import("std");

pub const PieceType = enum(u8) {
    Pawn = 0,
    Knight = 1,
    Bishop = 2,
    Rook = 3,
    Queen = 4,
    King = 5,
};

pub const Color = enum(u8) {
    White = 0b010000,
    Black = 0b100000,

    pub fn opposite(self: Color) Color {
        return if (self == .White) .Black else .White;
    }
};

pub const Piece = struct {
    piece_data: u8,

    pub fn new(piece: PieceType, color: Color) Piece {
        return Piece{ .piece_data = @intFromEnum(piece) | @intFromEnum(color) };
    }

    pub fn getValue(self: Piece) struct { PieceType, Color } {
        const piece_type = @as(PieceType, @enumFromInt(self.piece_data & 0x07));
        const raw_color = self.piece_data & 0b110000;
        const color = @as(Color, @enumFromInt(raw_color));
        return .{ piece_type, color };
    }

    pub fn isWhite(self: Piece) bool {
        return (self.piece_data & @intFromEnum(Color.White)) != 0;
    }

    pub fn toString(self: Piece) u8 {
        const piece_type, const color = self.getValue();

        var c = switch (piece_type) {
            PieceType.Pawn => @as(u8, 'P'),
            PieceType.Knight => @as(u8, 'N'),
            PieceType.Bishop => @as(u8, 'B'),
            PieceType.Rook => @as(u8, 'R'),
            PieceType.Queen => @as(u8, 'Q'),
            PieceType.King => @as(u8, 'K'),
        };
        if (color == Color.Black) {
            c -= 'a' - 'A'; // Convert to lowercase for black pieces
        }
        return c;
    }

    pub fn fromChar(char: u8) !Piece {
        var c = char;
        var color = Color.White;
        var ptype = PieceType.Pawn;
        if (char >= 'a' and char <= 'z') {
            color = Color.Black;
        } else {
            c = std.ascii.toLower(char); // Convert white pieces to lowercase
        }

        switch (c) {
            'p' => ptype = .Pawn,
            'n' => ptype = .Knight,
            'b' => ptype = .Bishop,
            'r' => ptype = .Rook,
            'k' => ptype = .King,
            'q' => ptype = .Queen,
            else => return error.InvalidPieceCharacter,
        }

        return Piece.new(ptype, color);
    }

    pub fn getColor(self: Piece) Color {
        return @as(Color, @enumFromInt(self.piece_data & 0b110000));
    }
    pub fn getType(self: Piece) PieceType {
        return @as(PieceType, @enumFromInt(self.piece_data & 0x07));
    }
};
