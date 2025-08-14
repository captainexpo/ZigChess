const std = @import("std");

pub const Bitboard = u64;

const DIR = struct {
    pub const N: i32 = 8;
    pub const S: i32 = -8;
    pub const E: i32 = 1;
    pub const W: i32 = -1;
    pub const NE: i32 = 9;
    pub const NW: i32 = 7;
    pub const SE: i32 = -7;
    pub const SW: i32 = -9;
};

inline fn sq_rank(sq: u8) u8 {
    return sq / 8;
}
inline fn sq_file(sq: u8) u8 {
    return @rem(sq, 8);
}

inline fn bit(sq: u8) Bitboard {
    return @as(Bitboard, 1) << @intCast(sq);
}

fn popcount(x: Bitboard) u6 {
    return @intCast(@popCount(x));
}

fn lsb(x: Bitboard) u6 {
    return @intCast(@ctz(x));
}

fn rook_mask(square: u8) Bitboard {
    // Sliding rays excluding board edges (so "relevant" blockers only)
    var mask: Bitboard = 0;
    const r = sq_rank(square);
    const f = sq_file(square);
    // North
    var rr: i32 = @as(i32, r) + 1;
    while (rr <= 6) : (rr += 1) mask |= bit(@intCast(rr * 8 + f));
    // South
    rr = @as(i32, r) - 1;
    while (rr >= 1) : (rr -= 1) mask |= bit(@intCast(rr * 8 + f));
    // East
    var ff: i32 = @as(i32, f) + 1;
    while (ff <= 6) : (ff += 1) mask |= bit(@intCast(r * 8 + ff));
    // West
    ff = @as(i32, f) - 1;
    while (ff >= 1) : (ff -= 1) mask |= bit(@intCast(r * 8 + ff));
    return mask;
}

fn bishop_mask(square: u8) Bitboard {
    var mask: Bitboard = 0;
    const r = sq_rank(square);
    const f = sq_file(square);

    var rr: i32 = @as(i32, r) + 1;
    var ff: i32 = @as(i32, f) + 1;
    while (rr <= 6 and ff <= 6) : (rr += 1) {
        mask |= bit(@intCast(rr * 8 + ff));
        ff += 1;
    }
    rr = @as(i32, r) + 1;
    ff = @as(i32, f) - 1;
    while (rr <= 6 and ff >= 1) : (rr += 1) {
        mask |= bit(@intCast(rr * 8 + ff));
        ff -= 1;
    }
    rr = @as(i32, r) - 1;
    ff = @as(i32, f) + 1;
    while (rr >= 1 and ff <= 6) : (rr -= 1) {
        mask |= bit(@intCast(rr * 8 + ff));
        ff += 1;
    }
    rr = @as(i32, r) - 1;
    ff = @as(i32, f) - 1;
    while (rr >= 1 and ff >= 1) : (rr -= 1) {
        mask |= bit(@intCast(rr * 8 + ff));
        ff -= 1;
    }
    return mask;
}

fn gen_occupancy_from_index(index: u64, mask: Bitboard) Bitboard {
    var occ: Bitboard = 0;
    var m = mask;
    var i: u64 = index;
    while (m != 0) {
        const sq: u6 = lsb(m);
        m &= m - 1;
        if ((i & 1) != 0) occ |= (@as(Bitboard, 1) << sq);
        i >>= 1;
    }
    return occ;
}

inline fn on_board(sq: i32) bool {
    return sq >= 0 and sq < 64;
}
inline fn file_of(sq: i32) i32 {
    return @rem(sq, 8);
}

fn sliding_attacks(square: u8, occ: Bitboard, rook: bool) Bitboard {
    var attacks: Bitboard = 0;
    const dirs = if (rook) [_]i32{ DIR.N, DIR.S, DIR.E, DIR.W } else [_]i32{ DIR.NE, DIR.NW, DIR.SE, DIR.SW };

    for (dirs) |d| {
        var s: i32 = @intCast(square);
        while (true) {
            const prev_file = file_of(s);
            s += d;
            if (!on_board(s)) break;
            // prevent wrapping E/W on files
            const cur_file = file_of(s);
            if (@abs(cur_file - prev_file) > 1 and (d == DIR.E or d == DIR.W or d == DIR.NE or d == DIR.SE or d == DIR.NW or d == DIR.SW))
                break;

            attacks |= (@as(Bitboard, 1) << @intCast(s));
            if ((occ & (@as(Bitboard, 1) << @intCast(s))) != 0) break;
        }
    }
    return attacks;
}

fn rook_attacks(square: u8, occ: Bitboard) Bitboard {
    return sliding_attacks(square, occ, true);
}

fn bishop_attacks(square: u8, occ: Bitboard) Bitboard {
    return sliding_attacks(square, occ, false);
}

fn random_sparse_u64(r: *std.Random) u64 {
    // Sparse (many zeros) to help magic quality
    return r.int(u64) & r.int(u64) & r.int(u64);
}

fn find_magic_for_square(
    allocator: std.mem.Allocator,
    square: u8,
    mask: Bitboard,
    rook: bool,
    rng: *std.Random,
) !u64 {
    const relevant_bits = popcount(mask);
    const table_size = @as(usize, 1) << relevant_bits;

    // Precompute all occupancies and their true attacks
    var occupancies = try allocator.alloc(Bitboard, table_size);
    defer allocator.free(occupancies);
    var attacks = try allocator.alloc(Bitboard, table_size);
    defer allocator.free(attacks);

    var i: usize = 0;
    while (i < table_size) : (i += 1) {
        const occ = gen_occupancy_from_index(@intCast(i), mask);
        occupancies[i] = occ;
        attacks[i] = if (rook) rook_attacks(square, occ) else bishop_attacks(square, occ);
    }

    // Helper buffers for testing candidates
    var used = try allocator.alloc(Bitboard, table_size);
    defer allocator.free(used);

    var attempt: usize = 0;
    const max_attempts: usize = 1_000_000;

    while (attempt < max_attempts) : (attempt += 1) {
        const magic = random_sparse_u64(rng);

        // A mild heuristic to skip obviously bad magics
        //const mul, const overflowed = @mulWithOverflow(mask, magic);
        //_ = overflowed; // ignore overflow
        //if (popcount((mul) & 0xFF00_0000_0000_0000) < 6) continue;

        // Reset used table
        @memset(used, 0);

        var ok = true;
        i = 0;
        while (i < table_size) : (i += 1) {
            const idx = @as(usize, @intCast(((occupancies[i] *% magic)) >> @intCast(64 - @as(u64, relevant_bits))));
            if (used[idx] == 0) {
                used[idx] = attacks[i];
            } else if (used[idx] != attacks[i]) {
                ok = false;
                break;
            }
        }

        if (ok) return magic;
    }

    return error.MagicNotFound;
}

fn print_bitboard_hex(x: Bitboard) void {
    std.debug.print("0x{X:0>16}", .{x});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    var rng = prng.random();

    var rook_masks: [64]Bitboard = undefined;
    var bishop_masks: [64]Bitboard = undefined;

    var rook_magics: [64]Bitboard = undefined;
    var bishop_magics: [64]Bitboard = undefined;

    var rook_relevant: [64]u6 = undefined;
    var bishop_relevant: [64]u6 = undefined;

    for (0..64) |sq_usize| {
        const sq: u8 = @intCast(sq_usize);
        rook_masks[sq] = rook_mask(sq);
        bishop_masks[sq] = bishop_mask(sq);
        rook_relevant[sq] = popcount(rook_masks[sq]);
        bishop_relevant[sq] = popcount(bishop_masks[sq]);
    }

    // Find magics
    std.debug.print("Generating rook magics...\n", .{});
    for (0..64) |sq_usize| {
        const sq: u8 = @intCast(sq_usize);
        const m = try find_magic_for_square(allocator, sq, rook_masks[sq], true, &rng);
        rook_magics[sq] = m;
    }

    std.debug.print("Generating bishop magics...\n", .{});
    for (0..64) |sq_usize| {
        const sq: u8 = @intCast(sq_usize);
        const m = try find_magic_for_square(allocator, sq, bishop_masks[sq], false, &rng);
        bishop_magics[sq] = m;
    }

    // Print as Zig arrays you can paste into your engine
    std.debug.print("\n// ---- Rook ----\n", .{});
    std.debug.print("pub const ROOK_RELEVANT_BITS: [64]u6 = .{{\n", .{});
    for (0..64) |i| {
        std.debug.print("    {},\n", .{rook_relevant[i]});
    }
    std.debug.print("}};\n\n", .{});

    std.debug.print("pub const ROOK_MASKS: [64]u64 = .{{\n", .{});
    for (0..64) |i| {
        std.debug.print("    ", .{});
        print_bitboard_hex(rook_masks[i]);
        std.debug.print(",\n", .{});
    }
    std.debug.print("}};\n\n", .{});

    std.debug.print("pub const ROOK_MAGICS: [64]u64 = .{{\n", .{});
    for (0..64) |i| {
        std.debug.print("    ", .{});
        print_bitboard_hex(rook_magics[i]);
        std.debug.print(",\n", .{});
    }
    std.debug.print("}};\n\n", .{});

    std.debug.print("// ---- Bishop ----\n", .{});
    std.debug.print("pub const BISHOP_RELEVANT_BITS: [64]u6 = .{{\n", .{});
    for (0..64) |i| {
        std.debug.print("    {},\n", .{bishop_relevant[i]});
    }
    std.debug.print("}};\n\n", .{});

    std.debug.print("pub const BISHOP_MASKS: [64]u64 = .{{\n", .{});
    for (0..64) |i| {
        std.debug.print("    ", .{});
        print_bitboard_hex(bishop_masks[i]);
        std.debug.print(",\n", .{});
    }
    std.debug.print("}};\n\n", .{});

    std.debug.print("pub const BISHOP_MAGICS: [64]u64 = .{{\n", .{});
    for (0..64) |i| {
        std.debug.print("    ", .{});
        print_bitboard_hex(bishop_magics[i]);
        std.debug.print(",\n", .{});
    }
    std.debug.print("}};\n\n", .{});

    std.debug.print("// Note: build your attack tables with (occ & MASK) -> index = ((occ * MAGIC) >> (64 - relevant_bits)).\n", .{});
}
