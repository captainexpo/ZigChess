const std = @import("std");
const Bitboard = @import("bitboards.zig").Bitboard;
const createRookMovementMask = @import("movegen.zig").createRookMovementMask;
const getRookLegalMoves = @import("movegen.zig").getRookLegalMoves;

pub fn createAllBlockerBitboards(allocator: std.mem.Allocator, mask: Bitboard) ![]Bitboard {
    var blockerBitboards: std.ArrayList(Bitboard) = std.ArrayList(Bitboard).init(allocator);
    defer blockerBitboards.deinit();

    // Iterate through all possible combinations of bits in the mask
    const totalCombinations = @as(u64, 1) << @truncate(@popCount(mask));
    for (0..totalCombinations) |i| {
        var bb: Bitboard = 0;
        var bitIndex: u8 = 0;

        // Set bits according to the current combination
        for (0..64) |j| {
            if ((mask & (@as(Bitboard, 1) << @truncate(j))) != 0) {
                if ((i & (@as(u64, 1) << @truncate(bitIndex))) != 0) {
                    bb |= (@as(Bitboard, 1) << @truncate(j));
                }
                bitIndex += 1;
            }
        }

        try blockerBitboards.append(bb);
    }

    return blockerBitboards.toOwnedSlice();
}

fn createRookLookupTable(allocator: std.mem.Allocator) !std.HashMap(struct { i32, Bitboard }, Bitboard) {
    var table = std.HashMap(struct { i32, Bitboard }, Bitboard).init(allocator);
    defer table.deinit();

    // Example: Populate the lookup table with some dummy data
    // In a real implementation, you would calculate the magic numbers and their corresponding bitboards
    for (0..64) |i| {
        const movementMask = createRookMovementMask(@truncate(i));
        const blockerPatterns = try createAllBlockerBitboards(allocator, movementMask);

        for (blockerPatterns) |blocker| {
            const legalMoveBitboard = getRookLegalMoves(blocker, @truncate(i));
            try table.put(.{ i, blocker }, legalMoveBitboard);
        }
    }

    return table;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Example usage
    const mask: Bitboard = 0x10101010ff101010;
    const blockerBitboards = try createAllBlockerBitboards(allocator, mask);

    for (blockerBitboards) |bb| {
        std.debug.print("{b}\n", .{bb});
    }
}
