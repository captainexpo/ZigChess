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
const Magic = @import("magicdata.zig");

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
    get_pseudo_legal: bool = false,
};

const PinInfo = struct {
    pinned_square: u6,
    pin_dirx: i8,
    pin_diry: i8,
    attacker_square: u6,
};

const MoveBuffer = struct {
    items: [300]Move = undefined,
    len: usize = 0,

    fn append(self: *MoveBuffer, move: Move) MoveGenError!void {
        if (self.len >= self.items.len) return MoveGenError.OutOfMemory;
        self.items[self.len] = move;
        self.len += 1;
    }

    fn toOwnedSlice(self: *const MoveBuffer, allocator: std.mem.Allocator) MoveGenError![]Move {
        const out = allocator.alloc(Move, self.len) catch return MoveGenError.OutOfMemory;
        @memcpy(out, self.items[0..self.len]);
        return out;
    }
};

const MoveContext = struct {
    pawnBoard: Bitboard,
    knightBoard: Bitboard,
    bishopBoard: Bitboard,
    rookBoard: Bitboard,
    queenBoard: Bitboard,
    kingBoard: Bitboard,
    opponentKingBoard: Bitboard,
    friendlyPieces: Bitboard,
    enemyPieces: Bitboard,
    allOccupied: Bitboard,
    attackerMask: Bitboard,
    pins: [8]PinInfo = undefined,
    numPins: usize = 0,
    numChecks: u64 = 0,
    validMovesMask: Bitboard = std.math.maxInt(u64),
    has_legality: bool = false,
};

pub const MoveGen = struct {
    knightAttackMasks: [64]u64 = undefined,
    kingAttackMasks: [64]u64 = undefined,
    rookAttackTable: [64][4096]u64 = undefined,
    bishopAttackTable: [64][512]u64 = undefined,

    fn setOccupancy(index: usize, attack_mask: Bitboard) Bitboard {
        var occupancy: Bitboard = 0;
        var mask = attack_mask;
        var bit_index: usize = 0;

        while (mask != 0) {
            const square: u7 = @ctz(mask);
            mask &= mask - 1;

            if ((index & (@as(usize, 1) << @intCast(bit_index))) != 0) {
                occupancy |= (@as(Bitboard, 1) << @truncate(square));
            }
            bit_index += 1;
        }

        return occupancy;
    }

    fn initMagicAttackTables(self: *MoveGen) void {
        for (0..64) |square| {
            const rook_mask = Magic.ROOK_MASKS[square];
            const rook_bits = Magic.ROOK_RELEVANT_BITS[square];
            const rook_permutations: usize = @as(usize, 1) << rook_bits;

            for (0..rook_permutations) |i| {
                const occupancy = setOccupancy(i, rook_mask);
                const rook_shift: u6 = @truncate(@as(u7, 64) - rook_bits);
                const magic_index: usize = @intCast((occupancy *% Magic.ROOK_MAGICS[square]) >> rook_shift);
                self.rookAttackTable[square][magic_index] = self.getRookLegalMovesSlow(occupancy, @intCast(square));
            }

            const bishop_mask = Magic.BISHOP_MASKS[square];
            const bishop_bits = Magic.BISHOP_RELEVANT_BITS[square];
            const bishop_permutations: usize = @as(usize, 1) << bishop_bits;

            for (0..bishop_permutations) |i| {
                const occupancy = setOccupancy(i, bishop_mask);
                const bishop_shift: u6 = @truncate(@as(u7, 64) - bishop_bits);
                const magic_index: usize = @intCast((occupancy *% Magic.BISHOP_MAGICS[square]) >> bishop_shift);
                self.bishopAttackTable[square][magic_index] = self.getBishopLegalMovesSlow(occupancy, @intCast(square));
            }
        }
    }

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

    fn getPinForSquare(pins: []const PinInfo, numPins: usize, square: u6) ?PinInfo {
        for (pins[0..numPins]) |pin| {
            if (pin.pinned_square == square) return pin;
        }
        return null;
    }

    fn moveFollowsPin(from_square: Square, to_square: Square, pin: PinInfo) bool {
        var dx = @as(i32, @intCast(to_square.file)) - @as(i32, @intCast(from_square.file));
        var dy = @as(i32, @intCast(to_square.rank)) - @as(i32, @intCast(from_square.rank));

        if (dx != 0) dx = @divFloor(dx, @as(i32, @intCast(@abs(dx))));
        if (dy != 0) dy = @divFloor(dy, @as(i32, @intCast(@abs(dy))));

        return isMoveAlongPinDirection(dx, dy, pin.pin_dirx, pin.pin_diry);
    }

    fn moveAllowedForContext(
        ctx: *const MoveContext,
        color: Color,
        piece_type: PieceType,
        from_square: Square,
        move: Move,
        pin: ?PinInfo,
    ) bool {
        if (!ctx.has_legality) return true;

        if (ctx.numChecks >= 2 and piece_type != .King) return false;

        if (piece_type != .King and ctx.numChecks == 1) {
            if (move.move_type == .EnPassant) {
                const capturedPawnSq = if (color == .White)
                    move.to_square.toFlat() - 8
                else
                    move.to_square.toFlat() + 8;
                const capturedMask = @as(u64, 1) << @truncate(capturedPawnSq);
                if ((capturedMask & ctx.validMovesMask) == 0) return false;
            } else {
                const moveMask = @as(u64, 1) << @truncate(move.to_square.toFlat());
                if ((moveMask & ctx.validMovesMask) == 0) return false;
            }
        }

        if (piece_type == .Knight) {
            return pin == null;
        }

        if (pin) |p| {
            if (move.to_square.toFlat() == p.attacker_square) return true;
            if (!moveFollowsPin(from_square, move.to_square, p)) return false;
        }

        return true;
    }

    fn addPromotionMoves(moveList: *MoveBuffer, from_square: Square, to_square: Square, move_type: MoveType) MoveGenError!void {
        const promotionPieces = [_]PieceType{ .Queen, .Rook, .Bishop, .Knight };
        for (promotionPieces) |promotionPiece| {
            const move = Move{
                .from_square = from_square,
                .to_square = to_square,
                .move_type = move_type,
                .promotion_piecetype = promotionPiece,
            };
            try moveList.append(move);
        }
    }

    fn generatePawnMoves(moveList: *MoveBuffer, board: *ChessBoard, color: Color, options: MoveGenOptions, ctx: *const MoveContext) MoveGenError!void {
        if (ctx.pawnBoard == 0) return;
        if (ctx.has_legality and ctx.numChecks >= 2) return;

        var pawns = ctx.pawnBoard;
        while (pawns != 0) {
            const pawnPosition = @ctz(pawns);
            const pawnFile = @rem(pawnPosition, 8);
            const pawnRank = @divFloor(pawnPosition, 8);
            const from_square = Square.fromFlat(@intCast(pawnPosition));
            const pin = if (ctx.has_legality) getPinForSquare(ctx.pins[0..ctx.numPins], ctx.numPins, @intCast(pawnPosition)) else null;

            pawns &= pawns - 1;

            var pawnAttacksMask: Bitboard = 0;
            if (pawnFile < 7) pawnAttacksMask |= FILE_A << @truncate(pawnFile + 1);
            if (pawnFile > 0) pawnAttacksMask |= FILE_A << @truncate(pawnFile - 1);

            pawnAttacksMask &= RANK_1 << @intCast(8 * (pawnRank + if (color == Color.White) @as(i64, 1) else @as(i64, -1)));

            var attacks: Bitboard = 0;
            if (options.get_pseudo_legal) {
                attacks = pawnAttacksMask;
            } else {
                attacks = pawnAttacksMask & ~ctx.friendlyPieces & (ctx.enemyPieces | board.enPassantMask);
            }

            var pawnMoveMask: Bitboard = FILE_A << @truncate(pawnFile);
            pawnMoveMask &= RANK_1 << @intCast(8 * (pawnRank + if (color == Color.White) @as(i64, 1) else @as(i64, -1)));

            if (color == Color.White and pawnRank == 1) {
                pawnMoveMask &= ~ctx.allOccupied;
                pawnMoveMask |= pawnMoveMask << 8;
            } else if (color == Color.Black and pawnRank == 6) {
                pawnMoveMask &= ~ctx.allOccupied;
                pawnMoveMask |= pawnMoveMask >> 8;
            }

            var moves = pawnMoveMask & ~ctx.allOccupied;

            while (moves != 0) {
                const targetSquare: u7 = @ctz(moves);
                const targetRank = @divFloor(targetSquare, 8);
                moves &= moves - 1;

                const target_square = Square.fromFlat(@intCast(targetSquare));
                const move_type: MoveType = if (@abs(@as(i32, @intCast(targetSquare)) - @as(i32, @intCast(pawnPosition))) == 16)
                    MoveType.DoublePush
                else
                    MoveType.NoCapture;

                if (targetRank == 0 or targetRank == 7) {
                    const promotionMove = Move{
                        .from_square = from_square,
                        .to_square = target_square,
                        .move_type = MoveType.NoCapture,
                    };
                    if (moveAllowedForContext(ctx, color, .Pawn, from_square, promotionMove, pin)) {
                        try addPromotionMoves(moveList, from_square, target_square, MoveType.NoCapture);
                    }
                    continue;
                }

                const move = Move{
                    .from_square = from_square,
                    .to_square = target_square,
                    .move_type = move_type,
                };
                if (moveAllowedForContext(ctx, color, .Pawn, from_square, move, pin)) {
                    try moveList.append(move);
                }
            }

            while (attacks != 0) {
                const targetSquare: u7 = @ctz(attacks);
                const targetRank = @divFloor(targetSquare, 8);
                attacks &= attacks - 1;

                const target_square = Square.fromFlat(@intCast(targetSquare));
                const move_type: MoveType = if ((ctx.enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                    MoveType.Capture
                else
                    MoveType.EnPassant;

                if (targetRank == 0 or targetRank == 7) {
                    const promotionMove = Move{
                        .from_square = from_square,
                        .to_square = target_square,
                        .move_type = MoveType.Capture,
                    };
                    if (moveAllowedForContext(ctx, color, .Pawn, from_square, promotionMove, pin)) {
                        try addPromotionMoves(moveList, from_square, target_square, MoveType.Capture);
                    }
                    continue;
                }

                const move = Move{
                    .from_square = from_square,
                    .to_square = target_square,
                    .move_type = move_type,
                };
                if (moveAllowedForContext(ctx, color, .Pawn, from_square, move, pin)) {
                    try moveList.append(move);
                }
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

    fn getRookLegalMovesSlow(self: *MoveGen, blocker: Bitboard, square: u8) Bitboard {
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

    pub fn getRookLegalMoves(self: *MoveGen, blocker: Bitboard, square: u8) Bitboard {
        const sq = @as(usize, square);
        const blockers = blocker & Magic.ROOK_MASKS[sq];
        const shift: u6 = @truncate(@as(u7, 64) - Magic.ROOK_RELEVANT_BITS[sq]);
        const index: usize = @intCast((blockers *% Magic.ROOK_MAGICS[sq]) >> shift);
        return self.rookAttackTable[sq][index];
    }

    fn generateStraightSlidingMoves(self: *MoveGen, moveList: *MoveBuffer, color: Color, position: u8, options: MoveGenOptions, ctx: *const MoveContext) MoveGenError!void {
        const from_square = Square.fromFlat(@intCast(position));
        if (ctx.has_legality and ctx.numChecks >= 2) return;

        var blockers = ctx.allOccupied;
        if (options.get_pseudo_legal) blockers &= ~ctx.opponentKingBoard;
        const legalMoves = self.getRookLegalMoves(blockers, position);

        var targets: Bitboard = legalMoves;
        if (!options.get_pseudo_legal) targets &= ~ctx.friendlyPieces;

        const pin = if (ctx.has_legality) getPinForSquare(ctx.pins[0..ctx.numPins], ctx.numPins, @intCast(position)) else null;

        while (targets != 0) {
            const targetSquare: u7 = @ctz(targets);
            targets &= targets - 1;

            const move = Move{
                .from_square = from_square,
                .to_square = Square.fromFlat(@intCast(targetSquare)),
                .move_type = if ((ctx.enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                    MoveType.Capture
                else
                    MoveType.Normal,
            };

            if (moveAllowedForContext(ctx, color, .Rook, from_square, move, pin)) {
                try moveList.append(move);
            }
        }
    }

    pub fn createBishopMovementMask(self: *MoveGen, square: u8) Bitboard {
        _ = self;
        return Magic.BISHOP_MASKS[@as(usize, square)];
    }

    fn getBishopLegalMovesSlow(self: *MoveGen, blocker: Bitboard, square: u8) Bitboard {
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

    pub fn getBishopLegalMoves(self: *MoveGen, blocker: Bitboard, square: u8) Bitboard {
        const sq = @as(usize, square);
        const blockers = blocker & Magic.BISHOP_MASKS[sq];
        const shift: u6 = @truncate(@as(u7, 64) - Magic.BISHOP_RELEVANT_BITS[sq]);
        const index: usize = @intCast((blockers *% Magic.BISHOP_MAGICS[sq]) >> shift);
        return self.bishopAttackTable[sq][index];
    }

    fn generateDiagonalSlidingMoves(self: *MoveGen, moveList: *MoveBuffer, color: Color, position: u8, options: MoveGenOptions, ctx: *const MoveContext) MoveGenError!void {
        const from_square = Square.fromFlat(@intCast(position));
        if (ctx.has_legality and ctx.numChecks >= 2) return;

        var blockers = ctx.allOccupied;
        if (options.get_pseudo_legal) blockers &= ~ctx.opponentKingBoard;

        const legalMoves = self.getBishopLegalMoves(blockers, position);
        var targets: Bitboard = legalMoves;
        if (!options.get_pseudo_legal) targets &= ~ctx.friendlyPieces;

        const pin = if (ctx.has_legality) getPinForSquare(ctx.pins[0..ctx.numPins], ctx.numPins, @intCast(position)) else null;

        while (targets != 0) {
            const targetSquare: u7 = @ctz(targets);
            targets &= targets - 1;

            const move = Move{
                .from_square = from_square,
                .to_square = Square.fromFlat(@intCast(targetSquare)),
                .move_type = if ((ctx.enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                    MoveType.Capture
                else
                    MoveType.Normal,
            };

            if (moveAllowedForContext(ctx, color, .Bishop, from_square, move, pin)) {
                try moveList.append(move);
            }
        }
    }

    fn generateRookMoves(self: *MoveGen, moveList: *MoveBuffer, color: Color, options: MoveGenOptions, ctx: *const MoveContext) MoveGenError!void {
        if (ctx.rookBoard == 0) return;

        var rooks = ctx.rookBoard;
        while (rooks != 0) {
            const i = @ctz(rooks);
            rooks &= rooks - 1;

            try self.generateStraightSlidingMoves(moveList, color, @intCast(i), options, ctx);
        }
    }

    fn generateBishopMoves(self: *MoveGen, moveList: *MoveBuffer, color: Color, options: MoveGenOptions, ctx: *const MoveContext) MoveGenError!void {
        if (ctx.bishopBoard == 0) return;

        var bishops = ctx.bishopBoard;
        while (bishops != 0) {
            const i = @ctz(bishops);
            bishops &= bishops - 1;

            try self.generateDiagonalSlidingMoves(moveList, color, @intCast(i), options, ctx);
        }
    }

    fn generateKnightMoves(self: *MoveGen, moveList: *MoveBuffer, color: Color, options: MoveGenOptions, ctx: *const MoveContext) MoveGenError!void {
        if (ctx.knightBoard == 0) return;
        if (ctx.has_legality and ctx.numChecks >= 2) return;

        var knights = ctx.knightBoard;
        while (knights != 0) {
            const i = @ctz(knights);
            knights &= knights - 1;

            const attacks = self.knightAttackMasks[i];
            var targets = attacks;
            if (!options.get_pseudo_legal) targets &= ~ctx.friendlyPieces;

            const pin = if (ctx.has_legality) getPinForSquare(ctx.pins[0..ctx.numPins], ctx.numPins, @intCast(i)) else null;

            while (targets != 0) {
                const targetSquare: u7 = @ctz(targets);
                targets &= targets - 1;

                const move = Move{
                    .from_square = Square.fromFlat(@intCast(i)),
                    .to_square = Square.fromFlat(@intCast(targetSquare)),
                    .move_type = if ((ctx.enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                        MoveType.Capture
                    else
                        MoveType.Normal,
                };

                if (moveAllowedForContext(ctx, color, .Knight, move.from_square, move, pin)) {
                    try moveList.append(move);
                }
            }
        }
    }

    fn generateQueenMoves(self: *MoveGen, moveList: *MoveBuffer, color: Color, options: MoveGenOptions, ctx: *const MoveContext) MoveGenError!void {
        if (ctx.queenBoard == 0) return;

        var queens = ctx.queenBoard;
        while (queens != 0) {
            const i = @ctz(queens);
            queens &= queens - 1;

            try self.generateStraightSlidingMoves(moveList, color, @intCast(i), options, ctx);
            try self.generateDiagonalSlidingMoves(moveList, color, @intCast(i), options, ctx);
        }
    }

    fn generateKingMoves(self: *MoveGen, moveList: *MoveBuffer, board: *ChessBoard, color: Color, options: MoveGenOptions, ctx: *const MoveContext) MoveGenError!void {
        if (ctx.kingBoard == 0) return;
        const kingSquare = @ctz(ctx.kingBoard);
        const attacks = self.kingAttackMasks[kingSquare];

        var targets: u64 = attacks;
        if (!options.get_pseudo_legal) targets &= ~ctx.friendlyPieces;
        if (!options.get_pseudo_legal) targets &= ~ctx.attackerMask;

        while (targets != 0) {
            const targetSquare: u7 = @ctz(targets);
            targets &= targets - 1; // clear the lowest bit

            const move = Move{
                .from_square = Square.fromFlat(@intCast(kingSquare)),
                .to_square = Square.fromFlat(@intCast(targetSquare)),
                .move_type = if ((ctx.enemyPieces & (@as(Bitboard, 1) << @truncate(targetSquare))) != 0)
                    MoveType.Capture
                else
                    MoveType.Normal,
            };
            try moveList.append(move);
        }

        // Castling
        var castlingMoves: [4]?Move = .{ null, null, null, null };
        const allOccupied = ctx.allOccupied;
        if (color == Color.White and kingSquare == 4) {
            if (board.castlingRights & 0b1000 != 0) {
                // King side
                const wksidemask: u64 = 0b1110000;
                if ((allOccupied & ~ctx.kingBoard) & wksidemask == 0 and ctx.attackerMask & wksidemask == 0) {
                    const rook = board.getPiece(7);
                    if (rook != null and rook.?.getType() == .Rook and rook.?.getColor() == .White) {
                        castlingMoves[0] = Move{
                            .from_square = Square.fromFlat(4),
                            .to_square = Square.fromFlat(6),
                            .move_type = MoveType.Castle,
                        };
                    }
                }
            }
            if (board.castlingRights & 0b0100 != 0) {
                // Queen side
                const wqsideattackmask: u64 = 0b11100;
                const wqsidevacancymask: u64 = 0b11110;
                if ((allOccupied & ~ctx.kingBoard) & wqsidevacancymask == 0 and ctx.attackerMask & wqsideattackmask == 0) {
                    const rook = board.getPiece(0);
                    if (rook != null and rook.?.getType() == .Rook and rook.?.getColor() == .White) {
                        castlingMoves[1] = Move{
                            .from_square = Square.fromFlat(4),
                            .to_square = Square.fromFlat(2),
                            .move_type = MoveType.Castle,
                        };
                    }
                }
            }
        } else if (color == Color.Black and kingSquare == 60) {
            if (board.castlingRights & 0b0010 != 0) {
                // King side
                const bksidemask: u64 = 0x7000000000000000;
                if ((allOccupied & ~ctx.kingBoard) & bksidemask == 0 and ctx.attackerMask & bksidemask == 0) {
                    const rook = board.getPiece(63);
                    if (rook != null and rook.?.getType() == .Rook and rook.?.getColor() == .Black) {
                        castlingMoves[2] = Move{
                            .from_square = Square.fromFlat(60),
                            .to_square = Square.fromFlat(62),
                            .move_type = MoveType.Castle,
                        };
                    }
                }
            }
            if (board.castlingRights & 0b0001 != 0) {
                // Queen side
                const bqsidemask: u64 = 0x1c00000000000000;
                const bqsidevacancymask: u64 = 0x1e00000000000000;
                if ((allOccupied & ~ctx.kingBoard) & bqsidevacancymask == 0 and ctx.attackerMask & bqsidemask == 0) {
                    const rook = board.getPiece(56);
                    if (rook != null and rook.?.getType() == .Rook and rook.?.getColor() == .Black) {
                        castlingMoves[3] = Move{
                            .from_square = Square.fromFlat(60),
                            .to_square = Square.fromFlat(58),
                            .move_type = MoveType.Castle,
                        };
                    }
                }
            }
        }
        for (castlingMoves) |move| {
            if (move) |m| {
                try moveList.append(m);
            }
        }
    }

    pub fn getPins(self: *MoveGen, board: *ChessBoard, color: Color) MoveGenError!struct { [8]PinInfo, usize } {
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

        var pins: [8]PinInfo = undefined; // Max 8 directions = 8 possible pins
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
        return .{ pins, pin_count };
    }

    pub fn initMoveGeneration() MoveGen {
        var moveGen = MoveGen{};

        moveGen.generateKnightMasks();
        moveGen.generateKingAttackMasks();
        moveGen.initMagicAttackTables();

        return moveGen;
    }

    fn prepareMoveContext(self: *MoveGen, board: *ChessBoard, color: Color, want_legality: bool) MoveGenError!MoveContext {
        const pawnBoard = board.getPieceBitboard(PieceType.Pawn, color);
        const knightBoard = board.getPieceBitboard(PieceType.Knight, color);
        const bishopBoard = board.getPieceBitboard(PieceType.Bishop, color);
        const rookBoard = board.getPieceBitboard(PieceType.Rook, color);
        const queenBoard = board.getPieceBitboard(PieceType.Queen, color);
        const kingBoard = board.getPieceBitboard(PieceType.King, color);
        const opponentKingBoard = board.getPieceBitboard(PieceType.King, color.opposite());
        const friendlyPieces = board.getOccupiedBitboard(color);
        const enemyPieces = board.getOccupiedBitboard(color.opposite());

        var ctx = MoveContext{
            .pawnBoard = pawnBoard,
            .knightBoard = knightBoard,
            .bishopBoard = bishopBoard,
            .rookBoard = rookBoard,
            .queenBoard = queenBoard,
            .kingBoard = kingBoard,
            .opponentKingBoard = opponentKingBoard,
            .friendlyPieces = friendlyPieces,
            .enemyPieces = enemyPieces,
            .allOccupied = friendlyPieces | enemyPieces,
            .attackerMask = 0,
        };

        if (want_legality) {
            if (kingBoard == 0) return MoveGenError.InvalidPosition;
            ctx.attackerMask = try self.getPossibleAttacksBitboard(std.heap.page_allocator, board, color.opposite());
            const pins, const numPins = try self.getPins(board, color);
            ctx.pins = pins;
            ctx.numPins = numPins;
            const numChecks, const validMovesMask = try self.getValidCheckMoves(board, color, ctx.attackerMask);
            ctx.numChecks = numChecks;
            ctx.validMovesMask = validMovesMask;
            ctx.has_legality = true;
        }

        return ctx;
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

    pub const MoveGenResult = struct {
        moves: []Move,
        king_in_check: bool = false,
        is_checkmate: bool = false,
        is_stalemate: bool = false,
    };

    pub fn hasZeroLegalMoves(self: *MoveGen, allocator: std.mem.Allocator, board: *ChessBoard, color: Color) MoveGenError!bool {
        const result = try self.generateMoves(allocator, board, color, .{
            .get_pseudo_legal = false,
            .specific_piece = null,
            .include_attacker_mask = true,
        });
        defer allocator.free(result.moves);
        return result.moves.len == 0;
    }

    pub fn inCheck(self: *MoveGen, board: *ChessBoard, color: Color) MoveGenError!bool {
        const kingBitboard = board.getPieceBitboard(PieceType.King, color);
        if (kingBitboard == 0) return MoveGenError.InvalidPosition;
        const attackerMask = try self.getPossibleAttacksBitboard(std.heap.page_allocator, board, color.opposite());
        return (kingBitboard & attackerMask) != 0;
    }

    pub fn getCaptureMoves(self: *MoveGen, allocator: std.mem.Allocator, board: *ChessBoard, color: Color) MoveGenError![]Move {
        const result = try self.generateMoves(allocator, board, color, .{
            .get_pseudo_legal = false,
            .specific_piece = null,
            .include_attacker_mask = false,
        });
        defer allocator.free(result.moves);

        var capture_count: usize = 0;
        for (result.moves) |move| {
            if (move.move_type == .Capture or move.move_type == .EnPassant) {
                capture_count += 1;
            }
        }

        const captures = allocator.alloc(Move, capture_count) catch return MoveGenError.OutOfMemory;
        var write_idx: usize = 0;

        for (result.moves) |move| {
            if (move.move_type == .Capture or move.move_type == .EnPassant) {
                captures[write_idx] = move;
                write_idx += 1;
            }
        }
        return captures;
    }

    pub fn generateMoves(self: *MoveGen, allocator: std.mem.Allocator, board: *ChessBoard, color: Color, options: MoveGenOptions) MoveGenError!MoveGenResult {
        var moves = MoveBuffer{};

        const want_legality = (options.specific_piece == null or options.specific_piece == .King) and !options.get_pseudo_legal and options.include_attacker_mask;
        const ctx = try self.prepareMoveContext(board, color, want_legality);

        if (options.specific_piece) |piece| {
            switch (piece) {
                PieceType.Pawn => try generatePawnMoves(&moves, board, color, options, &ctx),
                PieceType.Knight => try self.generateKnightMoves(&moves, color, options, &ctx),
                PieceType.King => try self.generateKingMoves(&moves, board, color, options, &ctx),
                PieceType.Rook => try self.generateRookMoves(&moves, color, options, &ctx),
                PieceType.Bishop => try self.generateBishopMoves(&moves, color, options, &ctx),
                PieceType.Queen => try self.generateQueenMoves(&moves, color, options, &ctx),
            }

            return .{
                .moves = try moves.toOwnedSlice(allocator),
                .king_in_check = false,
                .is_checkmate = false,
                .is_stalemate = false,
            };
        }

        try generatePawnMoves(&moves, board, color, options, &ctx);
        try self.generateKnightMoves(&moves, color, options, &ctx);
        try self.generateKingMoves(&moves, board, color, options, &ctx);
        try self.generateRookMoves(&moves, color, options, &ctx);
        try self.generateBishopMoves(&moves, color, options, &ctx);
        try self.generateQueenMoves(&moves, color, options, &ctx);

        if (options.get_pseudo_legal) {
            return .{ .moves = try moves.toOwnedSlice(allocator) };
        }
        const m = try moves.toOwnedSlice(allocator);

        return MoveGenResult{
            .moves = m,
            .king_in_check = ctx.numChecks > 0,
            .is_checkmate = (ctx.numChecks > 0 and m.len == 0),
            .is_stalemate = (ctx.numChecks == 0 and m.len == 0),
        };
    }

    pub fn getPossibleAttacksBitboard(self: *MoveGen, allocator: std.mem.Allocator, board: *ChessBoard, color: Color) MoveGenError!Bitboard {
        _ = allocator;

        var attacks: Bitboard = 0;

        const pawns = board.getPieceBitboard(.Pawn, color);
        if (color == .White) {
            attacks |= (pawns & ~FILE_A) << 7;
            attacks |= (pawns & ~FILE_H) << 9;
        } else {
            attacks |= (pawns & ~FILE_A) >> 9;
            attacks |= (pawns & ~FILE_H) >> 7;
        }

        var knights = board.getPieceBitboard(.Knight, color);
        while (knights != 0) {
            const sq: u7 = @ctz(knights);
            attacks |= self.knightAttackMasks[sq];
            knights &= knights - 1;
        }

        var kings = board.getPieceBitboard(.King, color);
        while (kings != 0) {
            const sq: u7 = @ctz(kings);
            attacks |= self.kingAttackMasks[sq];
            kings &= kings - 1;
        }

        var blockers = board.getOccupiedBitboard(.White) | board.getOccupiedBitboard(.Black);
        blockers &= ~board.getPieceBitboard(.King, color.opposite());

        var bishops = board.getPieceBitboard(.Bishop, color);
        while (bishops != 0) {
            const sq: u7 = @ctz(bishops);
            attacks |= self.getBishopLegalMoves(blockers, @intCast(sq));
            bishops &= bishops - 1;
        }

        var rooks = board.getPieceBitboard(.Rook, color);
        while (rooks != 0) {
            const sq: u7 = @ctz(rooks);
            attacks |= self.getRookLegalMoves(blockers, @intCast(sq));
            rooks &= rooks - 1;
        }

        var queens = board.getPieceBitboard(.Queen, color);
        while (queens != 0) {
            const sq: u7 = @ctz(queens);
            attacks |= self.getRookLegalMoves(blockers, @intCast(sq));
            attacks |= self.getBishopLegalMoves(blockers, @intCast(sq));
            queens &= queens - 1;
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

        const result = try self.generateMoves(allocator, &board, color, .{ .specific_piece = piece });

        return result.moves;
    }

    pub fn movesToString(allocator: std.mem.Allocator, moves: []Move) MoveGenError![]u8 {
        if (moves.len == 0) return allocator.alloc(u8, 0) catch return MoveGenError.OutOfMemory;

        var move_strs: [][]const u8 = try allocator.alloc([]const u8, moves.len);
        defer allocator.free(move_strs);

        // Convert each move to a string
        for (moves, 0..) |move, i| {
            move_strs[i] = try move.toString(allocator);
        }
        defer {
            for (move_strs) |s| allocator.free(s);
        }

        // Sort the strings
        std.mem.sort([]const u8, move_strs, {}, Utils.u8lessThan);

        // Concatenate the sorted strings into a single buffer
        var result: []u8 = allocator.alloc(u8, moves.len * 4 + moves.len - 1) catch return MoveGenError.OutOfMemory;

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
