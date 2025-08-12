const std = @import("std");

const Bitboards = @import("bitboards.zig");
const Bitboard = Bitboards.Bitboard;
const Move = @import("move.zig").Move;
const MoveGen = @import("movegen.zig").MoveGen;
const MoveType = @import("move.zig").MoveType;
const pieces = @import("piece.zig");

// Bottom left corner is a1, flat index = 0
// Top right corner is h8, flat index = 63
// Top left corner is a8, flat index = 56
// Bottom right corner is h1, flat index = 7

pub const SquareName = enum(u6) { a1, a2, a3, a4, a5, a6, a7, a8, b1, b2, b3, b4, b5, b6, b7, b8, c1, c2, c3, c4, c5, c6, c7, c8, d1, d2, d3, d4, d5, d6, d7, d8, e1, e2, e3, e4, e5, e6, e7, e8, f1, f2, f3, f4, f5, f6, f7, f8, g1, g2, g3, g4, g5, g6, g7, g8, h1, h2, h3, h4, h5, h6, h7, h8 };

pub const Square = struct {
    rank: u3, // 0-7 (y)
    file: u3, // 0-7 (x)

    pub fn new(rank: u3, file: u3) Square {
        return Square{ .rank = rank, .file = file };
    }

    pub fn toFlat(self: Square) u6 {
        return @as(u6, @intCast(self.rank)) * 8 + @as(u6, @intCast(self.file));
    }

    pub fn fromFlat(flat: u6) Square {
        std.debug.assert(flat < 64);
        return Square.new(@truncate(flat / 8), @truncate(flat % 8));
    }

    pub fn sq(name: SquareName) Square {
        return Square.fromFlat(@intCast(@intFromEnum(name)));
    }
};

pub fn idxFromSquare(comptime square: []const u8) u6 {
    if (square.len != 2) return error.InvalidSquareName;
    if (square[0] > 'h' or square[0] < 'a') return error.InvalidSquareName;
    if (square[1] > '8' or square[0] < '1') return error.InvalidSquareName;

    const file = square[0] - 'a';
    const rank = square[1] - '0' - 1;

    return file + rank * 8;
}

pub const Board = struct {
    pub const MoveUndo = struct {
        // Move that was made
        captured_piece: ?pieces.Piece,
        moved_piece: pieces.Piece,
        is_en_passant: bool,
        from_square: u6,
        to_square: u6,
        castle_type: u4,

        // State to restore
        old_castling_rights: u4,
        old_en_passant_mask: Bitboard,
        old_halfmove_clock: u8,
    };
    board_state: []?pieces.Piece,
    allocator: std.mem.Allocator,

    moveGen: *MoveGen,

    whiteOccupied: Bitboard,
    blackOccupied: Bitboard,

    blackPieces: [6]Bitboard,
    whitePieces: [6]Bitboard,

    castlingRights: u4 = 0, // [0] = White King, [1] = White Queen, [2] = Black King, [3] = Black Queen

    turn: pieces.Color = pieces.Color.White,

    enPassantMask: Bitboard = 0,

    halfMoveClock: u8 = 0,
    fullMoveNumber: u64 = 1,

    isInCheckmate: bool = false,
    isInStalemate: bool = false,

    pub fn emptyBoard(allocator: std.mem.Allocator, moveGen: *MoveGen) !Board {
        const state: []?pieces.Piece = allocator.alloc(?pieces.Piece, 64 + 8) catch return error.OutOfMemory;
        @memset(state, null);

        const whiteOccupied: Bitboard = 0;
        const blackOccupied: Bitboard = 0;

        const whitePieces: [6]Bitboard = @splat(0);
        const blackPieces: [6]Bitboard = @splat(0);

        return Board{
            .board_state = state,
            .allocator = allocator,
            .whiteOccupied = whiteOccupied,
            .blackOccupied = blackOccupied,
            .whitePieces = whitePieces,
            .blackPieces = blackPieces,
            .moveGen = moveGen,
        };
    }

    pub fn getPieceBitboard(self: *Board, pieceType: pieces.PieceType, color: pieces.Color) Bitboard {
        const index = @intFromEnum(pieceType);
        if (color == pieces.Color.White) {
            return self.whitePieces[index];
        } else {
            return self.blackPieces[index];
        }
    }

    pub fn setPieceBitboard(self: *Board, pieceType: pieces.PieceType, color: pieces.Color, bitboard: Bitboard) void {
        const index = @intFromEnum(pieceType);
        if (color == pieces.Color.White) {
            self.whitePieces[index] = bitboard;
        } else {
            self.blackPieces[index] = bitboard;
        }
    }

    pub fn getOccupiedBitboard(self: *Board, color: pieces.Color) Bitboard {
        if (color == pieces.Color.White) {
            return self.whiteOccupied;
        } else {
            return self.blackOccupied;
        }
    }

    pub fn getPiece(self: *Board, position: u8) ?pieces.Piece {
        if (position >= 64) return null; // Ensure position is within bounds
        return self.board_state[position];
    }

    pub fn setPiece(self: *Board, position: u8, piece: pieces.Piece) !void {
        if (position >= 64) return error.InvalidPosition; // Ensure position is within bounds

        // Create a new piece at the specified position
        self.board_state[position] = piece;

        const bitboard: Bitboard = @as(Bitboard, 1) << @as(u6, @truncate(position));
        self.whiteOccupied |= bitboard;
        self.whitePieces[@intFromEnum(pieces.PieceType.Pawn)] |= bitboard; // Adjust for the actual piece type

        return;
    }

    pub fn removePiece(self: *Board, position: u8) !pieces.Piece {
        const piece = self.board_state[position];
        if (piece) |p| {
            const pieceType, const color = p.getValue();
            const bitboard: Bitboard = @as(Bitboard, 1) << @as(u6, @truncate(position));
            if (color == pieces.Color.White) {
                self.whiteOccupied &= ~bitboard;
                self.whitePieces[@intFromEnum(pieceType)] &= ~bitboard;
            } else {
                self.blackOccupied &= ~bitboard;
                self.blackPieces[@intFromEnum(pieceType)] &= ~bitboard;
            }
            self.board_state[position] = null;
            return p;
        } else {
            return error.NoPieceAtPosition;
        }
    }

    pub fn isSquareOccupied(self: *Board, square: Square) !bool {
        return self.getPiece(square) != null;
    }

    pub fn makeMove(self: *Board, move: Move) !MoveUndo {
        var undo = Board.MoveUndo{
            .captured_piece = self.getPiece(move.to_square.toFlat()),
            .moved_piece = self.getPiece(move.from_square.toFlat()) orelse return error.NoPieceAtPosition,
            .from_square = move.from_square.toFlat(),
            .to_square = move.to_square.toFlat(),
            .old_castling_rights = self.castlingRights,
            .old_halfmove_clock = self.halfMoveClock,
            .old_en_passant_mask = self.enPassantMask,
            .castle_type = 0,
            .is_en_passant = move.move_type == MoveType.EnPassant,
        };

        self.enPassantMask = 0;

        const from_square = move.from_square.toFlat();
        const to_square = move.to_square.toFlat();

        const fromPeice = self.getPiece(from_square);
        if (fromPeice == null) {
            return error.NoPieceAtPosition;
        }
        const color = fromPeice.?.getColor();
        if (color != self.turn) {
            std.debug.print("Tried to move piece of color {s} when it was {s}'s turn\n", .{ @tagName(color), @tagName(self.turn) });
            return error.NotYourTurn;
        }

        const piece = try self.removePiece(from_square);
        try self.setPiece(to_square, piece);

        if (fromPeice.?.getType() == pieces.PieceType.Pawn) {
            if (move.move_type == MoveType.DoublePush) {
                // Set en passant mask for the square behind the pawn
                self.enPassantMask = @as(Bitboard, 1) << @intCast((@as(u6, @intCast(move.to_square.rank)) + (if (self.turn == .White) @as(i32, -1) else @as(i32, 1))) * 8 + @as(u6, @intCast(move.to_square.file)));
            }
            if (move.to_square.rank == 0 or move.to_square.rank == 7 and move.promotion_piecetype != null) {
                const promoted_piecetype = move.promotion_piecetype orelse return error.NoPromotionPiece;
                try self.setPiece(to_square, pieces.Piece.new(promoted_piecetype, color));
            }
        }

        if (move.move_type == MoveType.EnPassant) {
            const target_square: u8 = @intCast((@as(u6, @intCast(move.to_square.rank)) + (if (self.turn == .White) @as(i32, -1) else @as(i32, 1))) * 8 + @as(u6, @intCast(move.to_square.file)));
            const target_piece = self.getPiece(target_square);
            undo.captured_piece = target_piece;
            if (target_piece) |p| {
                _, const tcolor = p.getValue();
                if (tcolor != self.turn.opposite()) {
                    return error.InvalidEnPassant;
                }
                _ = try self.removePiece(target_square);
            } else {
                return error.InvalidEnPassant;
            }
        }

        if (move.move_type == MoveType.Castle) {
            const rook_square: u6 = if (move.to_square.file == @as(u6, 2)) @as(u6, 0) else @as(u6, 7); // Queen side or King side castling

            const rook_piece = self.getPiece(rook_square + @as(u6, @intCast(move.to_square.rank)) * 8);
            if (rook_piece) |r| {
                _ = try self.removePiece(rook_square + @as(u6, @intCast(move.to_square.rank)) * 8);
                const new_rook_square = if (move.to_square.file == @as(u6, 2)) @as(u6, 3) else @as(u6, 5); // Move rook to the correct square
                try self.setPiece(new_rook_square + @as(u6, move.to_square.rank) * 8, r);

                undo.castle_type = if (move.to_square.file == @as(u6, 2)) 1 else 2; //1  = Queen side, 2 = King side
                undo.castle_type |= undo.castle_type << 2;
                // Update castling rights
                if (self.turn == pieces.Color.White) {
                    self.castlingRights &= 0b0011; // Remove white castling rights
                    undo.castle_type &= 0b1100;
                } else {
                    self.castlingRights &= 0b1100; // Remove black castling rights
                    undo.castle_type &= 0b0011;
                }
            } else {
                std.debug.print("Tried to castle but no rook found at square {d}\n", .{rook_square + @as(u6, @intCast(move.to_square.rank)) * 8});
                return error.InvalidCastling;
            }
        }

        if (piece.getType() == .Rook) {
            // Update castling rights if a rook was moved
            if (self.turn == .White) {
                if (from_square == 0) self.castlingRights &= 0b0111; // Remove White Queen side castling right
                if (from_square == 7) self.castlingRights &= 0b1011; // Remove White King side castling right
            } else {
                if (from_square == 56 + 0) self.castlingRights &= 0b1110; // Remove Black Queen side castling right
                if (from_square == 56 + 7) self.castlingRights &= 0b1101; // Remove Black King side castling right
            }
        }

        self.updateBitboards();
        try self.nextTurn();
        return undo;
    }

    fn movePiece(self: *Board, from_square: Square, to_square: Square) !void {
        const from_flat = from_square.toFlat();
        const to_flat = to_square.toFlat();

        const piece = self.getPiece(from_flat);
        if (piece) |p| {
            _ = try self.removePiece(from_flat);
            try self.setPiece(to_flat, p);
        } else return error.NoPieceAtPosition;
    }

    pub fn undoMove(self: *Board, undo: Board.MoveUndo) !void {
        const to_square = undo.to_square;
        const from_square = undo.from_square;

        if (undo.is_en_passant) {
            const target_square: u8 = @intCast((@as(u6, @intCast(undo.to_square / 8)) + (if (self.turn == .White) @as(i32, 1) else @as(i32, -1))) * 8 + @as(u6, @intCast(undo.to_square % 8)));
            if (undo.captured_piece) |captured| {
                try self.setPiece(target_square, captured);
            } else {
                return error.NoPieceAtPosition;
            }
        }

        _ = self.removePiece(to_square) catch {};

        try self.setPiece(from_square, undo.moved_piece);

        if (!undo.is_en_passant) if (undo.captured_piece) |captured| {
            try self.setPiece(to_square, captured);
        };
        // Restore rooks if castling rights changed
        switch (undo.castle_type) {
            0b1000 => try self.movePiece(Square.fromFlat(5), Square.fromFlat(7)), // White King side
            0b0100 => try self.movePiece(Square.fromFlat(3), Square.fromFlat(0)), // White Queen side
            0b0010 => try self.movePiece(Square.fromFlat(56 + 5), Square.fromFlat(56 + 7)), // Black King side
            0b0001 => try self.movePiece(Square.fromFlat(56 + 3), Square.fromFlat(56 + 0)), // Black Queen side
            else => {}, // No change needed
        }
        self.castlingRights = undo.old_castling_rights;
        self.enPassantMask = undo.old_en_passant_mask;

        self.halfMoveClock = undo.old_halfmove_clock;

        self.updateBitboards();

        self.turn = if (self.turn == pieces.Color.White) pieces.Color.Black else pieces.Color.White;
    }

    pub fn updateBitboards(self: *Board) void {
        self.whiteOccupied = 0;
        self.blackOccupied = 0;
        for (0..self.whitePieces.len) |i| {
            self.whitePieces[i] = 0;
            self.blackPieces[i] = 0;
        }
        for (0..64) |i| {
            const piece = self.board_state[i];
            if (piece) |p| {
                const pieceType, const color = p.getValue();
                const bitboard: Bitboard = @as(Bitboard, 1) << @as(u6, @truncate(i));
                if (color == pieces.Color.White) {
                    self.whiteOccupied |= bitboard;
                    self.whitePieces[@intFromEnum(pieceType)] |= bitboard;
                } else {
                    self.blackOccupied |= bitboard;
                    self.blackPieces[@intFromEnum(pieceType)] |= bitboard;
                }
            }
        }
    }

    pub fn loadFEN(self: *Board, fen: []const u8) !void {
        self.castlingRights = 0;
        self.enPassantMask = 0;
        var tokens = std.mem.tokenizeAny(u8, fen, " ");

        const position = tokens.next() orelse return error.InvalidFEN;
        {
            var rank: u8 = 7;
            var file: u8 = 0;
            for (position) |c| {
                switch (c) {
                    '1'...'8' => {
                        const emptySquares = c - '0';
                        for (0..emptySquares) |_| {
                            self.board_state[file + rank * 8] = null;
                            file += 1;
                        }
                        continue;
                    },
                    'p' => self.board_state[file + rank * 8] = pieces.Piece.new(.Pawn, .Black),
                    'r' => self.board_state[file + rank * 8] = pieces.Piece.new(.Rook, .Black),
                    'n' => self.board_state[file + rank * 8] = pieces.Piece.new(.Knight, .Black),
                    'b' => self.board_state[file + rank * 8] = pieces.Piece.new(.Bishop, .Black),
                    'q' => self.board_state[file + rank * 8] = pieces.Piece.new(.Queen, .Black),
                    'k' => self.board_state[file + rank * 8] = pieces.Piece.new(.King, .Black),
                    'P' => self.board_state[file + rank * 8] = pieces.Piece.new(.Pawn, .White),
                    'R' => self.board_state[file + rank * 8] = pieces.Piece.new(.Rook, .White),
                    'N' => self.board_state[file + rank * 8] = pieces.Piece.new(.Knight, .White),
                    'B' => self.board_state[file + rank * 8] = pieces.Piece.new(.Bishop, .White),
                    'Q' => self.board_state[file + rank * 8] = pieces.Piece.new(.Queen, .White),
                    'K' => self.board_state[file + rank * 8] = pieces.Piece.new(.King, .White),
                    '/' => {
                        file = 0;
                        rank -= 1;
                        continue;
                    }, // Ignore slashes
                    else => return error.InvalidFEN,
                }
                file += 1;
            }
        }
        self.updateBitboards();

        const turn_char = (tokens.next() orelse return error.InvalidFEN)[0];
        self.turn = if (turn_char == 'w') pieces.Color.White else pieces.Color.Black;
        const castling_str = tokens.next() orelse return error.InvalidFEN;
        for (castling_str) |c| {
            switch (c) {
                'K' => self.castlingRights |= 1 << 3, // White King side
                'Q' => self.castlingRights |= 1 << 2, // White Queen side
                'k' => self.castlingRights |= 1 << 1, // Black King side
                'q' => self.castlingRights |= 1 << 0, // Black Queen side
                '-' => break, // No castling rights
                ' ' => break, // End of castling rights
                else => return error.InvalidFEN,
            }
        }

        const enpassant_str = tokens.next() orelse return error.InvalidFEN;
        if (enpassant_str[0] != '-') {
            const file = enpassant_str[0] - 'a';
            const rank = enpassant_str[1] - '1';

            if (file > 7 or rank > 7) return error.InvalidFEN;

            self.enPassantMask = @as(Bitboard, 1) << @intCast(@as(i32, @intCast(rank)) * 8 + file);
        }
    }

    pub fn getPossibleMoves(self: *Board, allocator: std.mem.Allocator) ![]Move {
        const result = try self.moveGen.generateMoves(allocator, self, self.turn, .{});
        self.isInCheckmate = result.is_checkmate;
        self.isInStalemate = result.is_stalemate;
        return result.moves;
    }

    pub fn nextTurn(self: *Board) !void {
        self.turn = self.turn.opposite();
    }

    pub fn toString(self: *Board, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);

        // Print from rank 8 (row 7) down to rank 1 (row 0)
        for (0..8) |r| {
            const row = 7 - r; // top row first
            for (0..8) |col| {
                const i = row * 8 + col; // compute correct index
                const piece = self.board_state[i];
                if (piece) |p| {
                    const pieceType, _ = p.getValue();
                    const piece_char = switch (pieceType) {
                        .Pawn => if (p.isWhite()) @as(u8, 'P') else @as(u8, 'p'),
                        .Knight => if (p.isWhite()) @as(u8, 'N') else @as(u8, 'n'),
                        .Bishop => if (p.isWhite()) @as(u8, 'B') else @as(u8, 'b'),
                        .Rook => if (p.isWhite()) @as(u8, 'R') else @as(u8, 'r'),
                        .Queen => if (p.isWhite()) @as(u8, 'Q') else @as(u8, 'q'),
                        .King => if (p.isWhite()) @as(u8, 'K') else @as(u8, 'k'),
                    };
                    try result.append(piece_char);
                } else {
                    try result.append('.');
                }
                try result.append(' ');
            }
            try result.append('\n');
        }

        return result.toOwnedSlice();
    }

    pub fn deinit(self: *Board) void {
        self.allocator.free(self.board_state);
    }

    pub fn classifyMove(self: *Board, move: Move) !Move {
        // Classify the move type based on the current board state
        const from_square = move.from_square.toFlat();
        const to_square = move.to_square.toFlat();

        const from_piece = self.getPiece(from_square);
        if (from_piece == null) {
            return error.NoPieceAtPosition;
        }

        const ppiece = if ((move.to_square.rank == 0 or move.to_square.rank == 7) and from_piece.?.getType() == .Pawn) move.promotion_piecetype else null;

        if (to_square < 64 and self.getPiece(to_square) != null) {
            // Capture
            return Move.init(move.from_square, move.to_square, MoveType.Capture, ppiece);
        }

        if (from_piece.?.getType() == pieces.PieceType.Pawn) {
            if (to_square == from_square + 8 or to_square == from_square - 8) {
                // Single push
                return Move.init(move.from_square, move.to_square, MoveType.NoCapture, ppiece);
            } else if (to_square == @as(i16, from_square) + 16 or to_square == @as(i16, from_square) - 16) {
                // Double push
                return Move.init(move.from_square, move.to_square, MoveType.DoublePush, null);
            } else if (move.from_square.file != move.to_square.file and self.getPiece(to_square) == null) {
                // En passant
                return Move.init(move.from_square, move.to_square, MoveType.EnPassant, null);
            }
        }

        if (from_piece.?.getType() == pieces.PieceType.King) {
            if ((from_square == 4 and to_square == 6) or (from_square == 60 and to_square == 62)) {
                // King side castling
                return Move.init(move.from_square, move.to_square, MoveType.Castle, null);
            } else if ((from_square == 4 and to_square == 2) or (from_square == 60 and to_square == 58)) {
                // Queen side castling
                return Move.init(move.from_square, move.to_square, MoveType.Castle, null);
            }
        }

        // Normal move
        return Move.init(move.from_square, move.to_square, MoveType.Normal, ppiece);
    }

    pub fn printDebugInfo(self: *Board) void {
        std.debug.print("Turn: {s}\n", .{@tagName(self.turn)});
        std.debug.print("White Occupied: {b}\n", .{self.whiteOccupied});
        std.debug.print("Black Occupied: {b}\n", .{self.blackOccupied});
        std.debug.print("Castling Rights: {b}\n", .{self.castlingRights});
        std.debug.print("En Passant Mask: {b}\n", .{self.enPassantMask});
    }
};
