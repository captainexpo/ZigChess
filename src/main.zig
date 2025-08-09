const std = @import("std");

const Board = @import("board.zig").Board;
const Bot = @import("bot/bot.zig");
const Color = @import("piece.zig").Color;
const Move = @import("move.zig").Move;
const MoveGen = @import("movegen.zig").MoveGen;
const MoveType = @import("move.zig").MoveType;
const Piece = @import("piece.zig").Piece;
const Square = @import("board.zig").Square;
const UCI = @import("uci.zig").UCI;

pub const log_level: std.log.Level = .debug;

pub fn printMoves(allocator: std.mem.Allocator, moves: []Move) !void {
    for (moves) |move| {
        const movestr = try move.toString(allocator);
        defer allocator.free(movestr);

        std.debug.print("{s}\n", .{movestr});
    }
}

pub fn runUCI(allocator: std.mem.Allocator) !void {
    var moveGen = MoveGen.initMoveGeneration();

    var uci = try UCI.new(allocator, std.io.getStdOut().writer(), std.io.getStdIn().reader(), &moveGen);
    defer uci.deinit();
    uci.setBot(Bot.ChessBot{
        .allocator = allocator,
    });
    try uci.run(); // catch |err| {
    //switch (err) {
    //    error.InvalidCommand => std.debug.print("Error: Invalid Command\n", .{}),
    //    error.InvalidOption => std.debug.print("Error: Invalid Option\n", .{}),
    //    error.InvalidPosition => std.debug.print("Error: Invalid Position\n", .{}),
    //    error.InvalidMove => std.debug.print("Error: Invalid Move\n", .{}),
    //    error.NotReady => std.debug.print("Error: Not Ready\n", .{}),
    //    error.UnknownError => std.debug.print("Error: Unknown Error\n", .{}),
    //    error.UnknownCommand => std.debug.print("Error: Unknown Command\n", .{}),
    //    else => std.debug.print("Error: {!}\n", .{err}),
    //}
    //};
}

pub fn runStandalone(allocator: std.mem.Allocator, fenStr: []const u8) !void {
    var moveGen = MoveGen.initMoveGeneration();

    var board = try Board.emptyBoard(allocator, &moveGen);
    defer board.deinit();

    try board.loadFEN(fenStr);
    const boardStr = try board.toString(allocator);
    defer allocator.free(boardStr);
    std.debug.print("Starting position: {s}\n", .{boardStr});

    const moves = try moveGen.generateMoves(allocator, &board, Color.White, .{});
    defer allocator.free(moves);

    try printMoves(allocator, moves);
    const pins = try moveGen.getPins(&board, Color.White, allocator);
    defer allocator.free(pins);

    for (pins) |pin| {
        std.debug.print("Pin: {d},{d},({d},{d})\n", .{ pin.pinned_square, pin.attacker_square, pin.pin_dirx, pin.pin_diry });
    }
}

pub fn printHelp() void {
    std.debug.print("Usage: chess [run-uci|standalone <FEN>]\n", .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    if (std.mem.eql(u8, args[1], "run-uci")) {
        try runUCI(allocator);
    } else if (std.mem.eql(u8, args[1], "standalone")) {
        try runStandalone(allocator, args[2]);
    } else {
        printHelp();
    }
}
