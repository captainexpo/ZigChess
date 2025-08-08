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
    rank: u8, // 0-7 (y)
    file: u8, // 0-7 (x)

    pub fn new(rank: u8, file: u8) Square {
        std.debug.assert(rank < 8 and file < 8);
        return Square{ .rank = rank, .file = file };
    }

    pub fn toFlat(self: Square) u8 {
        return self.rank * 8 + self.file;
    }

    pub fn fromFlat(flat: u8) Square {
        std.debug.assert(flat < 64);
        return Square.new(flat / 8, flat % 8);
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

    possibleMoves: []Move = undefined,

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

    pub fn makeMove(self: *Board, move: Move) !void {
        self.enPassantMask = 0;

        const from_square = move.from_square.toFlat();
        const to_square = move.to_square.toFlat();

        const fromPeice = self.getPiece(from_square);
        if (fromPeice == null) {
            return error.NoPieceAtPosition;
        }
        _, const color = fromPeice.?.getValue();
        if (color != self.turn) {
            return error.NotYourTurn;
        }

        const piece = try self.removePiece(from_square);
        try self.setPiece(to_square, piece);

        if (fromPeice.?.getType() == pieces.PieceType.Pawn) {
            if (move.move_type == MoveType.DoublePush) {
                // Set en passant mask for the square behind the pawn
                self.enPassantMask = @as(Bitboard, 1) << @as(u6, @intCast(move.to_square.rank + 1 * 8 + move.to_square.file));
            }
        }

        if (move.move_type == MoveType.EnPassant) {
            const target_square = move.to_square.rank + 1 * 8 + move.to_square.file; // The square behind the pawn
            const target_piece = self.getPiece(target_square);
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

            const rook_piece = self.getPiece(rook_square + move.to_square.rank * 8);
            if (rook_piece) |r| {
                _ = try self.removePiece(rook_square + move.to_square.rank * 8);
                const new_rook_square = if (move.to_square.file == @as(u6, 2)) @as(u6, 3) else @as(u6, 5); // Move rook to the correct square
                try self.setPiece(new_rook_square + move.to_square.rank * 8, r);
            } else {
                return error.InvalidCastling;
            }
        }

        if (move.move_type == MoveType.Promotion) {
            const promoted_piecetype = move.promotion_piecetype orelse return error.NoPromotionPiece;
            try self.setPiece(to_square, pieces.Piece.new(promoted_piecetype, color));
        }

        try self.nextTurn();
    }

    pub fn undoMove(self: *Board, move: Move) void {
        // Revert the board state and piece bitboards based on the move
        _ = move; // Placeholder for actual undo logic
        _ = self;
    }

    pub fn initBitboards(self: *Board) void {
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
        var rank: u8 = 7;
        var file: u8 = 0;
        var i: usize = 0;
        self.castlingRights = 0;

        for (fen, 0..fen.len) |c, idx| {
            switch (c) {
                '1'...'8' => {
                    const emptySquares = c - '0';
                    for (0..emptySquares) |_| {
                        self.board_state[file + rank * 8] = null;
                        file += 1;
                    }
                    continue;
                },
                'p' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Pawn, pieces.Color.Black),
                'r' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Rook, pieces.Color.Black),
                'n' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Knight, pieces.Color.Black),
                'b' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Bishop, pieces.Color.Black),
                'q' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Queen, pieces.Color.Black),
                'k' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.King, pieces.Color.Black),
                'P' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Pawn, pieces.Color.White),
                'R' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Rook, pieces.Color.White),
                'N' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Knight, pieces.Color.White),
                'B' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Bishop, pieces.Color.White),
                'Q' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.Queen, pieces.Color.White),
                'K' => self.board_state[file + rank * 8] = pieces.Piece.new(pieces.PieceType.King, pieces.Color.White),
                '/' => {
                    file = 0;
                    rank -= 1;
                    continue;
                }, // Ignore slashes
                ' ' => {
                    i = idx + 1;
                    break;
                },
                else => return error.InvalidFEN,
            }
            file += 1;
        }
        self.initBitboards();

        if (i < fen.len) {
            const turn_char = fen[i];
            self.turn = if (turn_char == 'w') pieces.Color.White else pieces.Color.Black;
            i += 2;
            for (0..4) |_| {
                if (i < fen.len) {
                    const castling_char = fen[i];
                    switch (castling_char) {
                        'K' => self.castlingRights |= 1 << 3, // White King side
                        'Q' => self.castlingRights |= 1 << 2, // White Queen side
                        'k' => self.castlingRights |= 1 << 1, // Black King side
                        'q' => self.castlingRights |= 1 << 0, // Black Queen side
                        '-' => break, // No castling rights
                        ' ' => break, // End of castling rights
                        else => return error.InvalidFEN,
                    }
                }
                i += 1;
            }
        }
        self.possibleMoves = self.moveGen.generateMoves(self.allocator, self, self.turn, .{}) catch |err| {
            std.debug.print("Error generating moves: {!}\n", .{err});
            return err;
        };
    }

    pub fn nextTurn(self: *Board) !void {
        self.turn = if (self.turn == pieces.Color.White) pieces.Color.Black else pieces.Color.White;
        self.possibleMoves = self.moveGen.generateMoves(self.allocator, self, self.turn, .{}) catch |err| {
            std.debug.print("Error generating moves: {!}\n", .{err});
            return err;
        };
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

        if (to_square < 64 and self.getPiece(to_square) != null) {
            // Capture
            return Move.init(move.from_square, move.to_square, MoveType.Capture, null, self.getPiece(to_square));
        }

        if (from_piece.?.getType() == pieces.PieceType.Pawn) {
            if (move.to_square.rank == 0 or move.to_square.rank == 7) {
                // Promotion
                // Assume the promotion piece is already set in the move
                return Move.init(move.from_square, move.to_square, MoveType.Promotion, move.promotion_piece, null);
            } else if (to_square == from_square + 8 or to_square == from_square - 8) {
                // Single push
                return Move.init(move.from_square, move.to_square, MoveType.NoCapture, null, null);
            } else if (to_square == from_square + 16 or to_square == from_square - 16) {
                // Double push
                return Move.init(move.from_square, move.to_square, MoveType.DoublePush, null, null);
            } else if (move.from_square.file != move.to_square.file and self.getPiece(to_square) == null) {
                // En passant
                return Move.init(move.from_square, move.to_square, MoveType.EnPassant, null, null);
            }
        }

        if (from_piece.?.getType() == pieces.PieceType.King) {
            if ((from_square == 4 and to_square == 6) or (from_square == 60 and to_square == 62)) {
                // King side castling
                return Move.init(move.from_square, move.to_square, MoveType.Castle, null, null);
            } else if ((from_square == 4 and to_square == 2) or (from_square == 60 and to_square == 58)) {
                // Queen side castling
                return Move.init(move.from_square, move.to_square, MoveType.Castle, null, null);
            }
        }

        // Normal move
        return Move.init(move.from_square, move.to_square, MoveType.Normal, null, null);
    }
};
