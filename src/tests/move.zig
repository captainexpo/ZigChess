const std = @import("std");
const Move = @import("../move.zig");
const Piece = @import("../piece.zig");

test "char to piece" {
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('p'), Piece.Piece.new(.Pawn, .Black));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('B'), Piece.Piece.new(.Bishop, .White));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('n'), Piece.Piece.new(.Knight, .Black));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('R'), Piece.Piece.new(.Rook, .White));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('q'), Piece.Piece.new(.Queen, .Black));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('K'), Piece.Piece.new(.King, .White));
}
