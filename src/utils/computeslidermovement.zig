const std = @import("std");
const Magic = @import("magicdata.zig");

fn indexFromOccupancy(occupancy: u64, mask: u64, magic: u64, relevant_bits: u6) usize {
    return @intCast(((occupancy & mask) *% magic) >> @intCast(64 - @as(u7, relevant_bits)));
}

fn rookAttacksOnTheFly(square: u6, occupancy: u64) u64 {
    var attacks: u64 = 0;

    // north
    var s = square;
    while (s < 56) : (s += 8) {
        attacks |= (@as(u64, 1) << @intCast(s));
        if ((occupancy & (@as(u64, 1) << @intCast(s))) != 0) break;
    }
    // south
    s = square;
    while (s >= 8) : (s -= 8) {
        attacks |= (@as(u64, 1) << @intCast(s));
        if ((occupancy & (@as(u64, 1) << @intCast(s))) != 0) break;
    }
    // east
    s = square;
    while ((s % 8) < 7) : (s += 1) {
        attacks |= (@as(u64, 1) << @intCast(s));
        if ((occupancy & (@as(u64, 1) << @intCast(s))) != 0) break;
    }
    // west
    s = square;
    while ((s % 8) > 0) : (s -= 1) {
        attacks |= (@as(u64, 1) << @intCast(s));
        if ((occupancy & (@as(u64, 1) << @intCast(s))) != 0) break;
    }

    return attacks;
}

fn setOccupancy(index: usize, relevant_bits: u6, mask: u64) u64 {
    var occupancy: u64 = 0;
    var bits = mask;
    var i: u6 = 0;
    while (i < relevant_bits) : (i += 1) {
        const bit = @ctz(bits); // find least significant set bit
        bits &= bits - 1; // clear it
        if ((index & (@as(u64, 1) << i)) != 0)
            occupancy |= (@as(u64, 1) << @truncate(bit));
    }
    return occupancy;
}

pub var rookAttacks: [64][]u64 = undefined;

fn initRookAttacks(allocator: *std.mem.Allocator) !void {
    for (0..64) |square| {
        const relevant_bits = Magic.ROOK_RELEVANT_BITS[square];
        const mask = Magic.ROOK_MASKS[square];
        const magic = Magic.ROOK_MAGICS[square];
        const tableSize = @as(usize, 1) << @intCast(relevant_bits);

        rookAttacks[square] = try allocator.alloc(u64, tableSize);

        for (0..tableSize) |index| {
            const occupancy = setOccupancy(index, relevant_bits, mask);
            const magicIndex = indexFromOccupancy(occupancy, mask, magic, relevant_bits);
            rookAttacks[square][magicIndex] = rookAttacksOnTheFly(@intCast(square), occupancy);
        }
    }
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    try initRookAttacks(&allocator);

    // Print out table
    var stdout = std.io.getStdOut().writer();
    _ = try stdout.print("const ROOK_ATTACKS = [64][{d}]u64{{\n", .{4096});
    for (0..64) |square| {
        _ = try stdout.print("    .{{", .{});
        for (0..rookAttacks[square].len) |i| {
            if (i > 0) _ = try stdout.print(", ", .{});
            _ = try stdout.print("0x{x}", .{rookAttacks[square][i]});
        }
        _ = try stdout.print("}},\n", .{});
    }
    _ = try stdout.print("}};\n", .{});
}
