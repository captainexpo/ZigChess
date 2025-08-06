const std = @import("std");

const Bitboard = @import("bitboards.zig").Bitboard;
const BoardUtils = @import("board.zig");
const ChessBoard = @import("board.zig").Board;
const Color = @import("piece.zig").Color;
const Move = @import("move.zig").Move;
const MoveType = @import("move.zig").MoveType;
const Piece = @import("piece.zig").Piece;
const PieceType = @import("piece.zig").PieceType;
const Square = @import("board.zig").Square;
const Utils = @import("utils.zig");

const FILE_A: Bitboard = 0x0101010101010101;
const FILE_B: Bitboard = 0x0202020202020202;
const FILE_C: Bitboard = 0x0404040404040404;
const FILE_D: Bitboard = 0x0808080808080808;
const FILE_E: Bitboard = 0x1010101010101010;
const FILE_F: Bitboard = 0x2020202020202020;
const FILE_G: Bitboard = 0x4040404040404040;
const FILE_H: Bitboard = 0x8080808080808080;

const RANK_1: Bitboard = 0x00000000000000FF;
const RANK_2: Bitboard = 0x000000000000FF00;
const RANK_3: Bitboard = 0x0000000000FF0000;
const RANK_4: Bitboard = 0x00000000FF000000;
const RANK_5: Bitboard = 0x000000FF00000000;
const RANK_6: Bitboard = 0x0000FF0000000000;
const RANK_7: Bitboard = 0x00FF000000000000;
const RANK_8: Bitboard = 0xFF00000000000000;

var knightAttackMasks: [64]u64 = undefined;
var kingAttackMasks: [64]u64 = undefined;

fn generateKnightMasks() void {
    for (0..64) |i| {
        var mask: u64 = 0;
        const row = @divFloor(@as(i32, @intCast(i)), 8);
        const col = @rem(@as(i32, @intCast(i)), 8);

        const knightOffsets = [_][2]i32{
            .{ 2, 1 },   .{ 1, 2 },   .{ -1, 2 }, .{ -2, 1 },
            .{ -2, -1 }, .{ -1, -2 }, .{ 1, -2 }, .{ 2, -1 },
        };

        for (knightOffsets) |offset| {
            const newRow = row + offset[0];
            const newCol = col + offset[1];

            if (newRow >= 0 and newRow < 8 and newCol >= 0 and newCol < 8) {
                const target = @as(u64, @intCast(newRow * 8 + newCol));
                mask |= (@as(Bitboard, 1) << @truncate(target));
            }
        }

        knightAttackMasks[i] = mask;
    }
}

fn generateKingAttackMasks() void {
    for (0..64) |i| {
        var mask: u64 = 0;
        const row = i / 8;
        const col = i % 8;

        // King moves to adjacent squares
        const kingMoves = [_]i32{
            -9, -8, -7, -1, 1, 7, 8, 9,
        };

        for (kingMoves) |move| {
            const target = @as(i64, @intCast(i)) + move;
            if (target >= 0 and target < 64) {
                const targetRow = @divFloor(target, 8);
                const targetCol = @mod(target, 8);

                // Ensure the move stays within the board boundaries
                if ((row == targetRow or row + 1 == targetRow or (row > 0 and row - 1 == targetRow)) and
                    (col == targetCol or col + 1 == targetCol or (col > 0 and col - 1 == targetCol)))
                {
                    mask |= (@as(Bitboard, 1) << @intCast(target));
                }
            }
        }
        kingAttackMasks[i] = mask;
    }
}

fn generatePawnMoves(moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color) !void {
    const pawnBoard = board.getPieceBitboard(PieceType.Pawn, color);
    const friendlyPieces = board.getOccupiedBitboard(color);
    const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

    if (pawnBoard == 0) return; // no king found (invalid position)

    var pawns = pawnBoard;
    while (pawns != 0) {
        const pawnPosition = @ctz(pawns); // find next pawn
        const pawnFile = @rem(pawnPosition, 8);

        pawns &= pawns - 1; // clear that pawn's bit

        var pawnAttacksMask: Bitboard = 0;
        if (pawnFile < 7) pawnAttacksMask |= FILE_A << @truncate(pawnFile + 1);
        if (pawnFile > 0) pawnAttacksMask |= FILE_A << @truncate(pawnFile - 1);
        const pawnRank = @divFloor(pawnPosition, 8);
        pawnAttacksMask &= RANK_1 << @intCast(8 * (pawnRank + if (color == Color.White) @as(i64, 1) else @as(i64, -1)));

        var attacks = pawnAttacksMask & ~friendlyPieces & enemyPieces; // only captures

        var pawnMoveMask: Bitboard = FILE_A << @truncate(pawnFile);

        pawnMoveMask &= RANK_1 << @intCast(8 * (pawnRank + if (color == Color.White) @as(i64, 1) else @as(i64, -1)));

        // double move
        if (color == Color.White and pawnRank == 1) {
            pawnMoveMask |= pawnMoveMask << 8;
        } else if (color == Color.Black and pawnRank == 6) {
            pawnMoveMask |= pawnMoveMask >> 8;
        }

        var moves = pawnMoveMask & ~(friendlyPieces | enemyPieces); // ignore occupied squares

        while (moves != 0) {
            const targetSquare: u7 = @ctz(moves);
            moves &= moves - 1;

            const move = Move{
                .from_square = Square.fromFlat(@intCast(pawnPosition)),
                .to_square = Square.fromFlat(@intCast(targetSquare)),
                .move_type = MoveType.NoCapture, // Normal pawn move
            };
            try moveList.append(move);
        }

        while (attacks != 0) {
            const targetSquare: u7 = @ctz(attacks);
            attacks &= attacks - 1;

            const move = Move{
                .from_square = Square.fromFlat(@intCast(pawnPosition)),
                .to_square = Square.fromFlat(@intCast(targetSquare)),
                .move_type = if ((enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                    MoveType.Capture
                else
                    MoveType.Normal,
            };
            try moveList.append(move);
        }
    }
}

pub fn createRookMovementMask(square: u8) Bitboard {
    const file = @rem(square, 8);
    const rank = @divFloor(square, 8);

    var mask: Bitboard = FILE_A << @truncate(file); // Vertical mask
    mask |= RANK_1 << @truncate(rank * 8); // Horizontal mask

    // Remove the square itself from the mask
    mask &= ~(@as(Bitboard, 1) << @truncate(square));
    return mask;
}

pub fn getRookLegalMoves(blocker: Bitboard, square: u8) Bitboard {
    var legalMoves: Bitboard = 0;

    // Check horizontal
    const left: u64 = @as(u64, 1) << @truncate(square);
    const right: u64 = @as(u64, 1) << @truncate(square);

    const rank = @divFloor(square, 8);
    const file = @rem(square, 8);

    // Move left
    for (0..file) |i| {
        legalMoves |= left >> @truncate(i + 1);
        if (blocker & (left >> @truncate(i + 1)) != 0) break; // Stop if blocked
    }
    // Move right
    for (0..7 - file) |i| {
        legalMoves |= right << @truncate(i + 1);
        if (blocker & (right << @truncate(i + 1)) != 0) break; // Stop if blocked
    }
    // Check Vertical
    const up: u64 = @as(u64, 1) << @truncate(square);
    const down: u64 = @as(u64, 1) << @truncate(square);
    // Move up
    for (0..rank) |i| {
        legalMoves |= up >> @truncate((i + 1) * 8);
        if (blocker & (up >> @truncate((i + 1) * 8)) != 0) break; // Stop if blocked
    }
    // Move down
    for (0..7 - rank) |i| {
        legalMoves |= down << @truncate((i + 1) * 8);
        if (blocker & (down << @truncate((i + 1) * 8)) != 0) break; // Stop if blocked
    }
    return legalMoves;
}

fn generateStraightSlidingMoves(moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, position: u8) !void {
    const friendlyPieces = board.getOccupiedBitboard(color);
    const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

    const from_square = Square.fromFlat(position);

    const legalMoves = getRookLegalMoves(friendlyPieces | enemyPieces, position);

    var targets: Bitboard = legalMoves & ~friendlyPieces; // only consider empty squares or enemy pieces

    while (targets != 0) {
        const targetSquare: u7 = @ctz(targets);
        targets &= targets - 1; // clear the lowest bit

        const move = Move{
            .from_square = from_square,
            .to_square = Square.fromFlat(@intCast(targetSquare)),
            .move_type = if ((enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                MoveType.Capture
            else
                MoveType.Normal,
        };
        try moveList.append(move);
    }
}

pub fn createBishopMovementMask(square: u8) Bitboard {
    // For the eventual magic bitboard implementation
    _ = square;
    return 0;
}

pub fn getBishopLegalMoves(blocker: Bitboard, square: u8) Bitboard {
    var legalMoves: Bitboard = 0;

    // Check diagonal moves
    const leftUp: u64 = @as(u64, 1) << @truncate(square);
    const rightUp: u64 = @as(u64, 1) << @truncate(square);
    const leftDown: u64 = @as(u64, 1) << @truncate(square);
    const rightDown: u64 = @as(u64, 1) << @truncate(square);

    const rank = @divFloor(square, 8);
    const file = @rem(square, 8);

    // Move left-up
    for (0..@min(file, rank)) |i| {
        legalMoves |= leftUp >> @truncate((i + 1) * 9);
        if (blocker & (leftUp >> @truncate((i + 1) * 9)) != 0) break; // Stop if blocked
    }
    // Move right-up
    for (0..@min(7 - file, rank)) |i| {
        legalMoves |= rightUp >> @truncate((i + 1) * 7);
        if (blocker & (rightUp >> @truncate((i + 1) * 7)) != 0) break; // Stop if blocked
    }
    // Move left-down
    for (0..@min(file, 7 - rank)) |i| {
        legalMoves |= leftDown << @truncate((i + 1) * 7);
        if (blocker & (leftDown << @truncate((i + 1) * 7)) != 0) break; // Stop if blocked
    }
    // Move right-down
    for (0..@min(7 - file, 7 - rank)) |i| {
        legalMoves |= rightDown << @truncate((i + 1) * 9);
        if (blocker & (rightDown << @truncate((i + 1) * 9)) != 0) break; // Stop if blocked
    }
    return legalMoves;
}

fn generateDiagonalSlidingMoves(moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, position: u8) !void {
    const friendlyPieces = board.getOccupiedBitboard(color);
    const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

    const from_square = Square.fromFlat(position);
    const legalMoves = getBishopLegalMoves(friendlyPieces | enemyPieces, position);
    var targets: Bitboard = legalMoves & ~friendlyPieces; // only consider empty squares or enemy enemyPieces
    while (targets != 0) {
        const targetSquare: u7 = @ctz(targets);
        targets &= targets - 1; // clear the lowest bit

        const move = Move{
            .from_square = from_square,
            .to_square = Square.fromFlat(@intCast(targetSquare)),
            .move_type = if ((enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                MoveType.Capture
            else
                MoveType.Normal,
        };
        try moveList.append(move);
    }
}

fn generateRookMoves(moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color) !void {
    const rookBoard = board.getPieceBitboard(PieceType.Rook, color);

    if (rookBoard == 0) return; // no rook found (invalid position)

    var rooks = rookBoard;
    while (rooks != 0) {
        const i = @ctz(rooks); // find next rook
        rooks &= rooks - 1; // clear that rook's bit

        try generateStraightSlidingMoves(moveList, board, color, @intCast(i));
    }
}

fn generateBishopMoves(moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color) !void {
    const bishopBoard = board.getPieceBitboard(PieceType.Bishop, color);

    if (bishopBoard == 0) return; // no bishop found (invalid position)

    var bishops = bishopBoard;
    while (bishops != 0) {
        const i = @ctz(bishops); // find next bishop
        bishops &= bishops - 1; // clear that bishop's bit

        try generateDiagonalSlidingMoves(moveList, board, color, @intCast(i));
    }
}

fn generateKnightMoves(moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color) !void {
    const knightBoard = board.getPieceBitboard(PieceType.Knight, color);
    const friendlyPieces = board.getOccupiedBitboard(color);
    const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

    if (knightBoard == 0) return; // no king found (invalid position)

    var knights = knightBoard;
    while (knights != 0) {
        const i = @ctz(knights); // find next knight
        knights &= knights - 1; // clear that knight's bit

        const attacks = knightAttackMasks[i];
        var targets = attacks & ~friendlyPieces;

        while (targets != 0) {
            const targetSquare: u7 = @ctz(targets);
            targets &= targets - 1;

            const move = Move{
                .from_square = Square.fromFlat(@intCast(i)),
                .to_square = Square.fromFlat(@intCast(targetSquare)),
                .move_type = if ((enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                    MoveType.Capture
                else
                    MoveType.Normal,
            };
            try moveList.append(move);
        }
    }
}

fn generateQueenMoves(moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color) !void {
    const queenBoard = board.getPieceBitboard(PieceType.Queen, color);

    if (queenBoard == 0) return; // no queen found (invalid position)

    var queens = queenBoard;
    while (queens != 0) {
        const i = @ctz(queens); // find next queen
        queens &= queens - 1; // clear that queen's bit

        try generateStraightSlidingMoves(moveList, board, color, @intCast(i));
        try generateDiagonalSlidingMoves(moveList, board, color, @intCast(i));
    }
}

fn generateKingMoves(moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color) !void {
    const kingBoard = board.getPieceBitboard(PieceType.King, color);
    const friendlyPieces = board.getOccupiedBitboard(color);
    const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

    if (kingBoard == 0) return; // no king found (invalid position)
    const kingSquare = @ctz(kingBoard); // get least significant set bit (king's position)
    const attacks = kingAttackMasks[kingSquare];

    var targets: u64 = attacks & ~friendlyPieces;

    std.debug.print("King at {d}, attacks: {x}\n", .{ kingSquare, attacks });

    while (targets != 0) {
        const targetSquare: u7 = @ctz(targets);
        targets &= targets - 1; // clear the lowest bit

        const move = Move{
            .from_square = Square.fromFlat(@intCast(kingSquare)),
            .to_square = Square.fromFlat(@intCast(targetSquare)),
            .move_type = if ((enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                MoveType.Capture
            else
                MoveType.Normal,
        };
        try moveList.append(move);
    }

    // Castling
    var castlingMoves: [4]?Move = .{ null, null, null, null };
    const allOccupied = friendlyPieces | enemyPieces;
    if (color == Color.White) {
        if (board.castlingRights & 0b1000 != 0) {
            // King side
            if (allOccupied & 0b1100000 == 0) {
                castlingMoves[0] = Move{
                    .from_square = Square.fromFlat(4),
                    .to_square = Square.fromFlat(6),
                    .move_type = MoveType.Castle,
                };
            }
        }
        if (board.castlingRights & 0b0100 != 0) {
            // Queen side
            if (allOccupied & 0b1110 == 0) {
                castlingMoves[1] = Move{
                    .from_square = Square.fromFlat(4),
                    .to_square = Square.fromFlat(2),
                    .move_type = MoveType.Castle,
                };
            }
        }
    } else {
        if (board.castlingRights & 0b0010 != 0) {
            // King side
            if (allOccupied & 0x6000000000000000 == 0) {
                castlingMoves[2] = Move{
                    .from_square = Square.fromFlat(60),
                    .to_square = Square.fromFlat(62),
                    .move_type = MoveType.Castle,
                };
            }
        }
        if (board.castlingRights & 0b0001 != 0) {
            // Queen side
            if (allOccupied & 0xe00000000000000 == 0) {
                castlingMoves[3] = Move{
                    .from_square = Square.fromFlat(60),
                    .to_square = Square.fromFlat(58),
                    .move_type = MoveType.Castle,
                };
            }
        }
    }
    for (castlingMoves) |move| {
        if (move) |m| {
            try moveList.append(m);
        }
    }
}

pub const PinInfo = struct {
    pinned_square: u6,
    pin_dirx: i8,
    pin_diry: i8,
    attacker_square: u6,
};

pub fn getPins(board: *ChessBoard, color: Color, allocator: std.mem.Allocator) ![]PinInfo {
    const king_bb = board.getPieceBitboard(PieceType.King, color);
    if (king_bb == 0) return error.InvalidPosition;
    const king_sq = @ctz(king_bb);

    const directions = [_][2]i32{
        .{ 1, 0 }, // East
        .{ -1, 0 }, // West
        .{ 0, 1 }, // North
        .{ 0, -1 }, // South
        .{ 1, 1 }, // NE
        .{ -1, 1 }, // NW
        .{ 1, -1 }, // SE
        .{ -1, -1 }, // SW
    };

    var pins = try allocator.alloc(PinInfo, 8); // Max 8 directions = 8 possible pins
    var pin_count: usize = 0;

    for (directions) |dir| {
        const dx = dir[0];
        const dy = dir[1];

        var x: i32 = @mod(king_sq, 8);
        var y: i32 = @divFloor(king_sq, 8);

        var seen_friendly = false;
        var pinned_sq: ?u6 = null;

        while (true) {
            x += dx;
            y += dy;

            if (x < 0 or x >= 8 or y < 0 or y >= 8) break;
            const sq: u6 = @intCast(y * 8 + x);
            const piece = board.getPiece(sq) orelse continue;

            const ptype, const pcolor = piece.getValue();
            if (pcolor == color) {
                if (seen_friendly) break;
                seen_friendly = true;
                pinned_sq = sq;
                continue;
            } else {
                // Opponent piece
                if (!seen_friendly) break;

                const is_diag = dx != 0 and dy != 0;
                if (ptype == PieceType.Queen or
                    (!is_diag and ptype == PieceType.Rook) or
                    (is_diag and ptype == PieceType.Bishop))
                {
                    // Found valid pin
                    pins[pin_count] = .{
                        .pinned_square = pinned_sq.?,
                        .pin_dirx = @intCast(dx),
                        .pin_diry = @intCast(dy),
                        .attacker_square = sq,
                    };
                    pin_count += 1;
                }
                break;
            }
        }
    }

    return pins[0..pin_count];
}

pub fn initMoveGeneration() void {
    generateKnightMasks();
    generateKingAttackMasks();
}
fn isMoveAlongPinDirection(dx: i32, dy: i32, dirx: i32, diry: i32) bool {
    // Check if (dx, dy) is a scalar multiple of (dirx, diry)
    if (dirx == 0 and diry == 0) return false; // invalid pin direction
    if (dirx == 0) return dx == 0 and dy * diry > 0;
    if (diry == 0) return dy == 0 and dx * dirx > 0;
    return dx * diry == dy * dirx and (dx * dirx > 0 and dy * diry > 0);
}
pub fn generateMoves(allocator: std.mem.Allocator, board: *ChessBoard, color: Color, specific_piece: ?PieceType) ![]Move {
    var moves = std.ArrayList(Move).init(allocator);
    defer moves.deinit();

    if (specific_piece) |piece| {
        switch (piece) {
            PieceType.Pawn => try generatePawnMoves(&moves, board, color),
            PieceType.Knight => try generateKnightMoves(&moves, board, color),
            PieceType.King => try generateKingMoves(&moves, board, color),
            PieceType.Rook => try generateRookMoves(&moves, board, color),
            PieceType.Bishop => try generateBishopMoves(&moves, board, color),
            PieceType.Queen => try generateQueenMoves(&moves, board, color),
        }

        return moves.toOwnedSlice();
    }

    try generatePawnMoves(&moves, board, color);
    try generateKnightMoves(&moves, board, color);
    try generateKingMoves(&moves, board, color);
    try generateRookMoves(&moves, board, color);
    try generateBishopMoves(&moves, board, color);
    try generateQueenMoves(&moves, board, color);

    const pins = try getPins(board, color, allocator);
    defer allocator.free(pins);

    // Filter moves based on pins
    if (pins.len > 0) {
        var filtered_moves = std.ArrayList(Move).init(allocator);
        defer filtered_moves.deinit();
        for (moves.items, 0..moves.items.len) |move, idx| {
            var is_valid = true;
            for (pins) |pin| {
                if (pin.pinned_square == move.from_square.toFlat()) {
                    if (move.to_square.toFlat() == pin.attacker_square) {
                        continue; // This move is valid, it captures the attacker
                    }
                    // Check if the move is in the pin direction
                    var dx = @as(i32, @intCast(move.to_square.file)) - @as(i32, @intCast(move.from_square.file));
                    var dy = @as(i32, @intCast(move.to_square.rank)) - @as(i32, @intCast(move.from_square.rank));

                    // Normalize direction
                    if (dx != 0) dx = @divFloor(dx, @as(i32, @intCast(@abs(dx))));
                    if (dy != 0) dy = @divFloor(dy, @as(i32, @intCast(@abs(dy))));

                    std.debug.print("{d},{d} | {d},{d} | {s}\n", .{ dx, dy, pin.pin_dirx, pin.pin_diry, move.toString(allocator) catch "error" });

                    if (!isMoveAlongPinDirection(dx, dy, pin.pin_dirx, pin.pin_diry)) {
                        is_valid = false;
                        break;
                    }
                }
            }
            if (is_valid) {
                std.debug.print("Move {d} is valid: {s}\n", .{ idx, try move.toString(allocator) });
                try filtered_moves.append(move);
            }
        }
        return filtered_moves.toOwnedSlice();
    }
    return moves.toOwnedSlice();
}

pub fn getPossibleAttacksBitboard(allocator: std.mem.Allocator, board: *ChessBoard, color: Color) !Bitboard {
    var attacks: Bitboard = 0;

    const moves = try generateMoves(allocator, board, color, null);
    defer allocator.free(moves);

    for (moves) |move| {
        if (move.move_type == MoveType.Capture or move.move_type == MoveType.Normal) {
            attacks |= (@as(Bitboard, 1) << @truncate(move.to_square.toFlat()));
        }
    }

    return attacks;
}

pub fn getMovesInPosition(allocator: std.mem.Allocator, fen: []const u8, color: Color, piece: ?PieceType) ![]Move {
    var board = try ChessBoard.emptyBoard(allocator);
    defer board.deinit();
    try board.loadFEN(fen);

    const board_str = try board.toString(allocator);
    defer allocator.free(board_str);

    initMoveGeneration();

    const moves = try generateMoves(allocator, &board, color, piece);

    return moves;
}

pub fn movesToString(allocator: std.mem.Allocator, moves: []Move) ![]u8 {
    if (moves.len == 0) return allocator.alloc(u8, 0) catch return error.OutOfMemory;

    var move_strs = try allocator.alloc([]const u8, moves.len);
    defer allocator.free(move_strs);

    // Convert each move to a string
    for (moves, 0..) |move, i| {
        move_strs[i] = try move.toString(allocator);
    }

    // Sort the strings
    std.mem.sort([]const u8, move_strs, {}, Utils.u8lessThan);

    // Concatenate the sorted strings into a single buffer
    var result = allocator.alloc(u8, moves.len * 4 + moves.len - 1) catch return error.OutOfMemory;

    var i: usize = 0;
    for (move_strs) |s| {
        if (i > 0) {
            result[i] = ' ';
            i += 1;
        }
        const len = s.len;
        @memcpy(result[i .. i + len], s);
        i += len;
    }

    return result;
}
