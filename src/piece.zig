const std = @import("std");

pub const PieceType = enum(u8) {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,

    pub fn toChar(self: PieceType) u8 {
        return switch (self) {
            .Pawn => 'p',
            .Knight => 'n',
            .Bishop => 'b',
            .Rook => 'r',
            .Queen => 'q',
            .King => 'k',
        };
    }

    pub fn fromChar(c: u8) !PieceType {
        const lc = std.ascii.toLower(c);
        return switch (lc) {
            'p' => .Pawn,
            'n' => .Knight,
            'b' => .Bishop,
            'r' => .Rook,
            'q' => .Queen,
            'k' => .King,
            else => return error.InvalidPieceCharacter,
        };
    }
};

pub const Color = enum(u8) {
    White,
    Black,

    pub fn opposite(self: Color) Color {
        return if (self == .White) .Black else .White;
    }
};

pub const Piece = struct {
    piece_type: PieceType,
    color: Color,

    pub fn new(piece: PieceType, color: Color) Piece {
        if (@intFromEnum(piece) > 5) {
            std.debug.print("GOT STRANGE PIECE: {d}", .{@intFromEnum(piece)});
        }
        std.debug.assert(@intFromEnum(piece) <= 5);
        return Piece{ .piece_type = piece, .color = color };
    }

    pub fn getValue(self: Piece) struct { PieceType, Color } {
        const piece_type = self.piece_type;
        const color = self.color;
        return .{ piece_type, color };
    }

    pub fn isWhite(self: Piece) bool {
        return self.color == Color.White;
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
        return self.color;
    }

    pub fn getType(self: Piece) PieceType {
        return self.piece_type;
    }
};
