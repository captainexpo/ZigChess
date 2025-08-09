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
const SquareName = @import("board.zig").SquareName;

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

pub const MoveGenError = error{
    InvalidPosition,
    InvalidMove,
    InvalidCommand,
    InvalidOption,
    NotReady,
    UnknownError,
    OutOfMemory,
};

pub const MoveGenOptions = struct {
    specific_piece: ?PieceType = null,
    include_attacker_mask: bool = true,
    include_all_attackers: bool = false,
};

const PinInfo = struct {
    pinned_square: u6,
    pin_dirx: i8,
    pin_diry: i8,
    attacker_square: u6,
};

pub const MoveGen = struct {
    knightAttackMasks: [64]u64 = undefined,
    kingAttackMasks: [64]u64 = undefined,

    fn generateKnightMasks(self: *MoveGen) void {
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

            self.knightAttackMasks[i] = mask;
        }
    }

    fn generateKingAttackMasks(self: *MoveGen) void {
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
            self.kingAttackMasks[i] = mask;
        }
    }

    fn addPromotionMoves(self: *MoveGen, moveList: *std.ArrayList(Move), from_square: Square, to_square: Square, move_type: MoveType) MoveGenError!void {
        const promotionPieces = [_]PieceType{ .Queen, .Rook, .Bishop, .Knight };
        for (promotionPieces) |promotionPiece| {
            const move = Move{
                .from_square = from_square,
                .to_square = to_square,
                .move_type = move_type,
                .promotion_piecetype = promotionPiece,
            };
            moveList.append(move) catch {
                return MoveGenError.OutOfMemory;
            };
        }
        _ = self;
    }

    fn generatePawnMoves(self: *MoveGen, moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, options: MoveGenOptions) MoveGenError!void {
        const pawnBoard = board.getPieceBitboard(PieceType.Pawn, color);
        const friendlyPieces = board.getOccupiedBitboard(color);
        const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

        if (pawnBoard == 0) return; // no king found (invalid position)

        var pawns = pawnBoard;
        var _allPawnAttacks: Bitboard = 0;
        while (pawns != 0) {
            const pawnPosition = @ctz(pawns); // find next pawn
            const pawnFile = @rem(pawnPosition, 8);

            pawns &= pawns - 1; // clear that pawn's bit

            var pawnAttacksMask: Bitboard = 0;
            if (pawnFile < 7) pawnAttacksMask |= FILE_A << @truncate(pawnFile + 1);
            if (pawnFile > 0) pawnAttacksMask |= FILE_A << @truncate(pawnFile - 1);

            const pawnRank = @divFloor(pawnPosition, 8);
            pawnAttacksMask &= RANK_1 << @intCast(8 * (pawnRank + if (color == Color.White) @as(i64, 1) else @as(i64, -1)));

            var attacks: Bitboard = 0;
            if (options.include_all_attackers) {
                attacks = pawnAttacksMask;
            } else {
                attacks = pawnAttacksMask & ~friendlyPieces & (enemyPieces | board.enPassantMask); // only captures
            }

            _allPawnAttacks |= attacks;

            var pawnMoveMask: Bitboard = FILE_A << @truncate(pawnFile);

            pawnMoveMask &= RANK_1 << @intCast(8 * (pawnRank + if (color == Color.White) @as(i64, 1) else @as(i64, -1)));

            // double move
            if (color == Color.White and pawnRank == 1) {
                // Make sure no piece is blocking the double move
                pawnMoveMask &= ~(friendlyPieces | enemyPieces);
                pawnMoveMask |= pawnMoveMask << 8;
            } else if (color == Color.Black and pawnRank == 6) {
                // Make sure no piece is blocking the double move
                pawnMoveMask &= ~(friendlyPieces | enemyPieces);
                pawnMoveMask |= pawnMoveMask >> 8;
            }

            var moves = pawnMoveMask & ~(friendlyPieces | enemyPieces); // ignore occupied squares

            while (moves != 0) {
                const targetSquare: u7 = @ctz(moves);
                const targetRank = @divFloor(targetSquare, 8);
                moves &= moves - 1;

                if (targetRank == 0 or targetRank == 7) {
                    // Promotion
                    try self.addPromotionMoves(
                        moveList,
                        Square.fromFlat(@intCast(pawnPosition)),
                        Square.fromFlat(@intCast(targetSquare)),
                        MoveType.NoCapture,
                    );
                    continue;
                }

                const move = Move{
                    .from_square = Square.fromFlat(@intCast(pawnPosition)),
                    .to_square = Square.fromFlat(@intCast(targetSquare)),
                    .move_type = MoveType.NoCapture, // Normal pawn move
                };

                moveList.append(move) catch {
                    return MoveGenError.OutOfMemory;
                };
            }

            while (attacks != 0) {
                const targetSquare: u7 = @ctz(attacks);
                const targetRank = @divFloor(targetSquare, 8);
                attacks &= attacks - 1;

                if (targetRank == 0 or targetRank == 7) {
                    // Promotion capture
                    try self.addPromotionMoves(
                        moveList,
                        Square.fromFlat(@intCast(pawnPosition)),
                        Square.fromFlat(@intCast(targetSquare)),
                        MoveType.Capture,
                    );
                    continue;
                }
                const move = Move{
                    .from_square = Square.fromFlat(@intCast(pawnPosition)),
                    .to_square = Square.fromFlat(@intCast(targetSquare)),
                    .move_type = if (board.getPiece(targetSquare) == null) MoveType.EnPassant else MoveType.Capture,
                };
                moveList.append(move) catch {
                    return MoveGenError.OutOfMemory;
                };
            }
        }
    }

    pub fn createRookMovementMask(self: *MoveGen, square: u8) Bitboard {
        const file = @rem(square, 8);
        const rank = @divFloor(square, 8);

        var mask: Bitboard = FILE_A << @truncate(file); // Vertical mask
        mask |= RANK_1 << @truncate(rank * 8); // Horizontal mask

        // Remove the square itself from the mask
        mask &= ~(@as(Bitboard, 1) << @truncate(square));
        _ = self;
        return mask;
    }

    pub fn getRookLegalMoves(self: *MoveGen, blocker: Bitboard, square: u8) Bitboard {
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
        _ = self;
        return legalMoves;
    }

    fn generateStraightSlidingMoves(self: *MoveGen, moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, position: u8, options: MoveGenOptions) MoveGenError!void {
        const friendlyPieces = board.getOccupiedBitboard(color);
        const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

        const from_square = Square.fromFlat(@intCast(position));

        var blockers = friendlyPieces | enemyPieces;
        if (options.include_all_attackers) blockers &= ~board.getPieceBitboard(.King, color.opposite());
        const legalMoves = self.getRookLegalMoves(blockers, position);

        var targets: Bitboard = legalMoves;
        if (!options.include_all_attackers) targets &= ~friendlyPieces; // only consider empty squares or enemy pieces

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
            moveList.append(move) catch {
                return MoveGenError.OutOfMemory;
            };
        }
    }

    pub fn createBishopMovementMask(self: *MoveGen, square: u8) Bitboard {
        // For the eventual magic bitboard implementation
        _ = square;
        _ = self;
        return 0;
    }

    pub fn getBishopLegalMoves(self: *MoveGen, blocker: Bitboard, square: u8) Bitboard {
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
        _ = self;
        return legalMoves;
    }

    fn generateDiagonalSlidingMoves(self: *MoveGen, moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, position: u8, options: MoveGenOptions) MoveGenError!void {
        const friendlyPieces = board.getOccupiedBitboard(color);
        const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

        const from_square = Square.fromFlat(@intCast(position));
        var blockers = friendlyPieces | enemyPieces;
        if (options.include_all_attackers) blockers &= ~board.getPieceBitboard(.King, color.opposite());
        const legalMoves = self.getBishopLegalMoves(blockers, position);
        var targets: Bitboard = legalMoves;
        if (!options.include_all_attackers) targets &= ~friendlyPieces; // only consider empty squares or enemy enemyPieces
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
            moveList.append(move) catch {
                return MoveGenError.OutOfMemory;
            };
        }
    }

    fn generateRookMoves(self: *MoveGen, moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, options: MoveGenOptions) MoveGenError!void {
        const rookBoard = board.getPieceBitboard(PieceType.Rook, color);

        if (rookBoard == 0) return;

        var rooks = rookBoard;
        while (rooks != 0) {
            const i = @ctz(rooks);
            rooks &= rooks - 1;

            try self.generateStraightSlidingMoves(moveList, board, color, @intCast(i), options);
        }
    }

    fn generateBishopMoves(self: *MoveGen, moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, options: MoveGenOptions) MoveGenError!void {
        const bishopBoard = board.getPieceBitboard(PieceType.Bishop, color);

        if (bishopBoard == 0) return;

        var bishops = bishopBoard;
        while (bishops != 0) {
            const i = @ctz(bishops);
            bishops &= bishops - 1;

            try self.generateDiagonalSlidingMoves(moveList, board, color, @intCast(i), options);
        }
    }

    fn generateKnightMoves(self: *MoveGen, moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, options: MoveGenOptions) MoveGenError!void {
        const knightBoard = board.getPieceBitboard(PieceType.Knight, color);
        const friendlyPieces = board.getOccupiedBitboard(color);
        const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

        if (knightBoard == 0) return; // no king found (invalid position)

        var knights = knightBoard;
        while (knights != 0) {
            const i = @ctz(knights); // find next knight
            knights &= knights - 1; // clear that knight's bit

            const attacks = self.knightAttackMasks[i];
            var targets = attacks;
            if (!options.include_all_attackers) targets &= ~friendlyPieces;

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

    fn generateQueenMoves(self: *MoveGen, moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, options: MoveGenOptions) MoveGenError!void {
        const queenBoard = board.getPieceBitboard(PieceType.Queen, color);

        if (queenBoard == 0) return; // no queen found (invalid position)

        var queens = queenBoard;
        while (queens != 0) {
            const i = @ctz(queens); // find next queen
            queens &= queens - 1; // clear that queen's bit

            try self.generateStraightSlidingMoves(moveList, board, color, @intCast(i), options);
            try self.generateDiagonalSlidingMoves(moveList, board, color, @intCast(i), options);
        }
    }

    fn generateKingMoves(self: *MoveGen, moveList: *std.ArrayList(Move), board: *ChessBoard, color: Color, attackerMask: Bitboard, options: MoveGenOptions) MoveGenError!void {
        const kingBoard = board.getPieceBitboard(PieceType.King, color);
        const friendlyPieces = board.getOccupiedBitboard(color);
        const enemyPieces = board.getOccupiedBitboard(if (color == Color.White) Color.Black else Color.White);

        if (kingBoard == 0) return; // no king found (invalid position)
        const kingSquare = @ctz(kingBoard); // get least significant set bit (king's position)
        const attacks = self.kingAttackMasks[kingSquare];

        var targets: u64 = attacks;
        if (!options.include_all_attackers) targets &= ~friendlyPieces;
        targets &= ~attackerMask; // Exclude squares attacked by enemy pieces

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
        if (color == Color.White and kingSquare == 4) {
            if (board.castlingRights & 0b1000 != 0) {
                // King side
                const wksidemask: u64 = 0b1110000;
                if ((allOccupied & ~kingBoard) & wksidemask == 0 and attackerMask & wksidemask == 0) {
                    castlingMoves[0] = Move{
                        .from_square = Square.fromFlat(4),
                        .to_square = Square.fromFlat(6),
                        .move_type = MoveType.Castle,
                    };
                }
            }
            if (board.castlingRights & 0b0100 != 0) {
                // Queen side
                const wqsideattackmask: u64 = 0b11100;
                const wqsidevacancymask: u64 = 0b11110;
                if ((allOccupied & ~kingBoard) & wqsidevacancymask == 0 and attackerMask & wqsideattackmask == 0) {
                    castlingMoves[1] = Move{
                        .from_square = Square.fromFlat(4),
                        .to_square = Square.fromFlat(2),
                        .move_type = MoveType.Castle,
                    };
                }
            }
        } else if (color == Color.Black and kingSquare == 60) {
            if (board.castlingRights & 0b0010 != 0) {
                // King side
                const bksidemask: u64 = 0x7000000000000000;
                if ((allOccupied & ~kingBoard) & bksidemask == 0 and attackerMask & bksidemask == 0) {
                    castlingMoves[2] = Move{
                        .from_square = Square.fromFlat(60),
                        .to_square = Square.fromFlat(62),
                        .move_type = MoveType.Castle,
                    };
                }
            }
            if (board.castlingRights & 0b0001 != 0) {
                // Queen side
                const bqsidemask: u64 = 0x1c00000000000000;
                const bqsidevacancymask: u64 = 0x1e00000000000000;
                if ((allOccupied & ~kingBoard) & bqsidevacancymask == 0 and attackerMask & bqsidemask == 0) {
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

    pub fn getPins(self: *MoveGen, board: *ChessBoard, color: Color, allocator: std.mem.Allocator) MoveGenError![]PinInfo {
        const king_bb = board.getPieceBitboard(PieceType.King, color);
        if (king_bb == 0) return MoveGenError.InvalidPosition;
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

        var pin_masks: [8]Bitboard = @splat(0);
        for (directions, 0..) |dir, i| {
            const dx = dir[0];
            const dy = dir[1];

            var x: i32 = @mod(king_sq, 8);
            var y: i32 = @divFloor(king_sq, 8);

            var seen_friendly = false;
            var pinned_sq: ?u6 = null;

            while (true) {
                pin_masks[i] |= (@as(Bitboard, 1) << @intCast(y * 8 + x));

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
        _ = self;
        return pins[0..pin_count];
    }

    pub fn initMoveGeneration() MoveGen {
        var moveGen = MoveGen{};

        moveGen.generateKnightMasks();
        moveGen.generateKingAttackMasks();

        return moveGen;
    }

    fn isMoveAlongPinDirection(dx: i32, dy: i32, dirx: i32, diry: i32) bool {
        if (dirx == 0 and diry == 0) return false; // invalid pin direction
        if (dirx == 0) return dx == 0;
        if (diry == 0) return dy == 0;
        return dx * diry == dy * dirx;
    }

    fn getKnightAttackers(self: *MoveGen, pos: u7, board: *ChessBoard, color: Color) struct { u64, Bitboard } {
        const knightBitboard = self.knightAttackMasks[pos];
        const attackers = knightBitboard & board.getPieceBitboard(.Knight, color.opposite());
        return .{ @as(u64, @intCast(@popCount(attackers))), attackers };
    }

    fn getCheckRays(self: *MoveGen, board: *ChessBoard, color: Color, king_sq: u7) MoveGenError!struct { u64, Bitboard } {
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

        var checkbitboard: Bitboard = 0;
        var numChecks: u64 = 0;

        for (directions) |dir| {
            const dx = dir[0];
            const dy = dir[1];

            var x: i32 = @mod(king_sq, 8) + dx;
            var y: i32 = @divFloor(king_sq, 8) + dy;

            var ray: Bitboard = 0;

            while (x >= 0 and x < 8 and y >= 0 and y < 8) {
                const sq: u6 = @intCast(y * 8 + x);
                ray |= (@as(Bitboard, 1) << sq);

                const piece = board.getPiece(sq) orelse {
                    x += dx;
                    y += dy;
                    continue;
                };

                const ptype, const pcolor = piece.getValue();

                if (pcolor == color) break;

                const is_diag = dx != 0 and dy != 0;
                if (ptype == PieceType.Queen or
                    (!is_diag and ptype == PieceType.Rook) or
                    (is_diag and ptype == PieceType.Bishop))
                {
                    numChecks += 1;
                    checkbitboard |= ray; // Only add this ray if it's an actual check
                }
                break;
            }
        }
        _ = self;
        return .{ numChecks, checkbitboard };
    }

    fn getPawnChecks(self: *MoveGen, board: *ChessBoard, color: Color, king_sq: u7) MoveGenError!struct { u64, Bitboard } {
        var numChecks: u64 = 0;
        var checkbitboard: Bitboard = 0;
        const pawn_attack_offsets = if (color == Color.Black)
            [_][2]i32{ .{ -1, -1 }, .{ 1, -1 } }
        else
            [_][2]i32{ .{ -1, 1 }, .{ 1, 1 } };

        for (pawn_attack_offsets) |off| {
            const px = @mod(king_sq, 8) + off[0];
            const py = @divFloor(king_sq, 8) + off[1];
            if (px < 0 or px >= 8 or py < 0 or py >= 8) continue;

            const sq: u6 = @intCast(py * 8 + px);
            const piece = board.getPiece(sq) orelse continue;

            const ptype, const pcolor = piece.getValue();
            if (pcolor != color and ptype == PieceType.Pawn) {
                numChecks += 1;
                checkbitboard |= (@as(Bitboard, 1) << sq);
            }
        }
        _ = self;
        return .{ numChecks, checkbitboard };
    }

    fn getValidCheckMoves(self: *MoveGen, board: *ChessBoard, color: Color, attackerMask: Bitboard) MoveGenError!struct { u64, Bitboard } {
        const kingBitboard = board.getPieceBitboard(PieceType.King, color);
        const kingIsInCheck = (kingBitboard & attackerMask) != 0;
        if (!kingIsInCheck) {
            return .{ 0, std.math.maxInt(u64) }; // All moves allowed if not in check
        }

        const kingPosition = @ctz(kingBitboard);
        var checks: u64 = 0;
        var validCheckMoves: Bitboard = 0; // Union of all valid "capture/block" squares

        // Knight checks
        const knightChecks, const knightCheckPositions =
            self.getKnightAttackers(kingPosition, board, color);
        checks += knightChecks;
        validCheckMoves |= knightCheckPositions;
        if (checks >= 2) return .{ checks, 0 };

        // Pawn checks
        const numPawnChecks, const pawnChecksBitboard =
            try self.getPawnChecks(board, color, kingPosition);
        checks += numPawnChecks;
        validCheckMoves |= pawnChecksBitboard;
        if (checks >= 2) return .{ checks, 0 };

        // Sliding checks
        const numSlidingChecks, const slidingChecksBitboard =
            try self.getCheckRays(board, color, kingPosition);
        checks += numSlidingChecks;
        validCheckMoves |= slidingChecksBitboard;
        if (checks >= 2) return .{ checks, 0 };

        return .{ checks, validCheckMoves };
    }

    pub fn generateMoves(self: *MoveGen, allocator: std.mem.Allocator, board: *ChessBoard, color: Color, options: MoveGenOptions) MoveGenError![]Move {
        var moves = std.ArrayList(Move).init(allocator);
        defer moves.deinit();

        const attackerMask = if (options.include_attacker_mask) self.getPossibleAttacksBitboard(allocator, board, color.opposite()) catch {
            return MoveGenError.InvalidPosition;
        } else 0;

        if (options.specific_piece) |piece| {
            switch (piece) {
                PieceType.Pawn => try self.generatePawnMoves(&moves, board, color, options),
                PieceType.Knight => try self.generateKnightMoves(&moves, board, color, options),
                PieceType.King => try self.generateKingMoves(&moves, board, color, attackerMask, options),
                PieceType.Rook => try self.generateRookMoves(&moves, board, color, options),
                PieceType.Bishop => try self.generateBishopMoves(&moves, board, color, options),
                PieceType.Queen => try self.generateQueenMoves(&moves, board, color, options),
            }

            return moves.toOwnedSlice();
        }

        try self.generatePawnMoves(&moves, board, color, options);
        try self.generateKnightMoves(&moves, board, color, options);
        try self.generateKingMoves(&moves, board, color, attackerMask, options);
        try self.generateRookMoves(&moves, board, color, options);
        try self.generateBishopMoves(&moves, board, color, options);
        try self.generateQueenMoves(&moves, board, color, options);

        if (options.include_all_attackers) return moves.toOwnedSlice();

        const pins = try self.getPins(board, color, allocator);
        defer allocator.free(pins);

        // Get number of checks + valid capture/block mask
        const numChecks, const validMovesMask = try self.getValidCheckMoves(board, color, attackerMask);
        var final_moves = std.ArrayList(Move).init(allocator);
        defer final_moves.deinit();

        for (moves.items) |move| {
            const fromSq = move.from_square.toFlat();
            const toSq = move.to_square.toFlat();

            // Double check → only king moves are allowed
            if (numChecks >= 2) {
                if (board.getPiece(fromSq).?.getType() == .King) {
                    final_moves.append(move) catch return MoveGenError.OutOfMemory;
                }
                continue;
            }

            // Single check → king moves always allowed
            if (numChecks == 1 and board.getPiece(fromSq).?.getType() != .King) {
                const moveMask = @as(u64, 1) << @truncate(toSq);
                if (!(move.move_type == .EnPassant)) {
                    if ((moveMask & validMovesMask) == 0) continue;
                } else {
                    const capturedPawnSq = if (color == .White) toSq - 8 else toSq + 8;
                    const capturedMask = @as(u64, 1) << @truncate(capturedPawnSq);
                    if ((capturedMask & validMovesMask) == 0) continue;
                }
            }

            // Pin filtering
            var is_valid = true;
            for (pins) |pin| {
                if (pin.pinned_square == fromSq) {
                    if (toSq == pin.attacker_square) {
                        break; // capturing attacker is fine
                    }
                    if (board.getPiece(fromSq).?.getType() == .Knight) {
                        is_valid = false;
                        break;
                    }
                    // Check if the move is along the pin line
                    var dx = @as(i32, @intCast(move.to_square.file)) - @as(i32, @intCast(move.from_square.file));
                    var dy = @as(i32, @intCast(move.to_square.rank)) - @as(i32, @intCast(move.from_square.rank));

                    if (dx != 0) dx = @divFloor(dx, @as(i32, @intCast(@abs(dx))));
                    if (dy != 0) dy = @divFloor(dy, @as(i32, @intCast(@abs(dy))));

                    if (!isMoveAlongPinDirection(dx, dy, pin.pin_dirx, pin.pin_diry)) {
                        is_valid = false;
                        break;
                    }
                }
            }
            if (!is_valid) continue;

            final_moves.append(move) catch return MoveGenError.OutOfMemory;
        }

        return final_moves.toOwnedSlice();
    }

    pub fn getPossibleAttacksBitboard(self: *MoveGen, allocator: std.mem.Allocator, board: *ChessBoard, color: Color) MoveGenError!Bitboard {
        var attacks: Bitboard = 0;

        const moves = try self.generateMoves(allocator, board, color, .{ .include_attacker_mask = false, .include_all_attackers = true });
        defer allocator.free(moves);

        for (moves) |move| {
            if (move.move_type != MoveType.Castle and move.move_type != MoveType.Unknown and move.move_type != MoveType.DoublePush and move.move_type != MoveType.NoCapture) {
                attacks |= (@as(Bitboard, 1) << @truncate(move.to_square.toFlat()));
            }
        }
        return attacks;
    }

    pub fn getMovesInPosition(self: *MoveGen, allocator: std.mem.Allocator, fen: []const u8, color: Color, piece: ?PieceType) MoveGenError![]Move {
        var board = try ChessBoard.emptyBoard(allocator, self);
        defer board.deinit();
        board.loadFEN(fen) catch {
            return MoveGenError.InvalidPosition;
        };

        const board_str = try board.toString(allocator);
        defer allocator.free(board_str);

        self.initMoveGeneration();

        const moves = try self.generateMoves(allocator, &board, color, .{ .specific_piece = piece });

        return moves;
    }

    pub fn movesToString(allocator: std.mem.Allocator, moves: []Move) MoveGenError![]u8 {
        if (moves.len == 0) return allocator.alloc(u8, 0) catch return MoveGenError.OutOfMemory;

        var move_strs = try allocator.alloc([]const u8, moves.len);
        defer allocator.free(move_strs);

        // Convert each move to a string
        for (moves, 0..) |move, i| {
            move_strs[i] = try move.toString(allocator);
        }

        // Sort the strings
        std.mem.sort([]const u8, move_strs, {}, Utils.u8lessThan);

        // Concatenate the sorted strings into a single buffer
        var result = allocator.alloc(u8, moves.len * 4 + moves.len - 1) catch return MoveGenError.OutOfMemory;

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
};
