const std = @import("std");
const Piece = @import("piece.zig").Piece;
const Color = @import("piece.zig").Color;
const Square = @import("board.zig").Square;
const MoveType = @import("move.zig").MoveType;
const Move = @import("move.zig").Move;
const Board = @import("board.zig").Board;
const MoveGen = @import("movegen.zig");
const UCI = @import("uci.zig").UCI;
const Bot = @import("bot/bot.zig");
pub fn printMoves(allocator: std.mem.Allocator, moves: []Move) !void {
    for (moves) |move| {
        const movestr = try move.toString(allocator);
        defer allocator.free(movestr);

        std.debug.print("{s}\n", .{movestr});
    }
}

pub fn old_main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var board = try Board.emptyBoard(allocator);
    defer board.deinit();
    try board.loadFEN(args[1]);

    std.debug.print("Initial Board:\n", .{});

    const board_str = try board.toString(allocator);
    defer allocator.free(board_str);

    std.debug.print("{s}\n", .{board_str});

    MoveGen.initMoveGeneration();
    const moves = try MoveGen.generateMoves(allocator, board, Color.White, null);
    defer allocator.free(moves);

    std.debug.print("Generated {d} Moves:\n", .{moves.len});

    try printMoves(allocator, moves);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    MoveGen.initMoveGeneration();

    var uci = try UCI.new(allocator, std.io.getStdOut().writer(), std.io.getStdIn().reader());
    defer uci.deinit();
    uci.setBot(Bot.ChessBot{
        .allocator = allocator,
    });
    uci.run() catch |err| {
        switch (err) {
            error.InvalidCommand => std.debug.print("Error: Invalid Command\n", .{}),
            error.InvalidOption => std.debug.print("Error: Invalid Option\n", .{}),
            error.InvalidPosition => std.debug.print("Error: Invalid Position\n", .{}),
            error.InvalidMove => std.debug.print("Error: Invalid Move\n", .{}),
            error.NotReady => std.debug.print("Error: Not Ready\n", .{}),
            error.UnknownError => std.debug.print("Error: Unknown Error\n", .{}),
            error.UnknownCommand => std.debug.print("Error: Unknown Command\n", .{}),
            else => std.debug.print("Error: {!}\n", .{err}),
        }
    };
}
