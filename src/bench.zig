const std = @import("std");

const Board = @import("board.zig").Board;
const MoveGen = @import("movegen.zig").MoveGen;

const Position = struct {
    name: []const u8,
    fen: []const u8,
};

const BenchResult = struct {
    nodes: u64,
    nanos: u64,
};

fn runPosition(allocator: std.mem.Allocator, movegen: *MoveGen, fen: []const u8, iterations: usize) !BenchResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var board = try Board.emptyBoard(allocator, movegen);
    defer board.deinit();

    try board.loadFEN(fen);

    var total_nodes: u64 = 0;
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = arena.reset(.retain_capacity);
        const result = try movegen.generateMoves(arena.allocator(), &board, board.turn, .{});
        total_nodes += result.moves.len;
    }

    return .{
        .nodes = total_nodes,
        .nanos = timer.read(),
    };
}

fn printResult(name: []const u8, result: BenchResult) void {
    const seconds = @as(f64, @floatFromInt(result.nanos)) / @as(f64, std.time.ns_per_s);
    const nps = if (result.nanos == 0)
        @as(f64, 0)
    else
        (@as(f64, @floatFromInt(result.nodes)) * @as(f64, std.time.ns_per_s)) / @as(f64, @floatFromInt(result.nanos));

    std.debug.print("{s}: nodes={d}, time={d:.3}s, nodes/s={d:.0}\n", .{
        name,
        result.nodes,
        seconds,
        nps,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const iterations = if (args.len >= 2)
        try std.fmt.parseUnsigned(usize, args[1], 10)
    else
        20_000;

    const warmup_iterations = @max(iterations / 10, 200);

    const positions = [_]Position{
        .{ .name = "startpos", .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" },
        .{ .name = "middlegame", .fen = "r3k2r/pp1n1ppp/2pbpn2/q2p4/3P4/2N1PN2/PPQ2PPP/R3KB1R w KQkq - 0 1" },
        .{ .name = "endgame", .fen = "8/2k5/8/3K4/8/2P5/8/8 w - - 0 1" },
    };

    std.debug.print("Benchmarking move generation\n", .{});
    std.debug.print("Iterations per position: {d} (warmup {d})\n\n", .{ iterations, warmup_iterations });

    var movegen = MoveGen.initMoveGeneration();

    var total_nodes: u64 = 0;
    var total_nanos: u64 = 0;

    for (positions) |pos| {
        _ = try runPosition(allocator, &movegen, pos.fen, warmup_iterations);
        const result = try runPosition(allocator, &movegen, pos.fen, iterations);
        printResult(pos.name, result);
        total_nodes += result.nodes;
        total_nanos += result.nanos;
    }

    std.debug.print("\n", .{});
    printResult("total", .{ .nodes = total_nodes, .nanos = total_nanos });
}
