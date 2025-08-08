// Implementation of a simple UCI (Universal Chess Interface) protocol handler in Zig.
const std = @import("std");

const Board = @import("board.zig").Board;
const Bot = @import("bot/bot.zig");
const Color = @import("piece.zig").Color;
const Move = @import("move.zig").Move;
const MoveGen = @import("movegen.zig").MoveGen;
const MoveType = @import("move.zig").MoveType;
const Piece = @import("piece.zig").Piece;
const Square = @import("board.zig").Square;

pub const UCIError = error{
    InvalidCommand,
    InvalidOption,
    InvalidPosition,
    InvalidMove,
    NotReady,
    UnknownError,
    UnknownCommand,
};

const startposition: []const u8 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub const UCI = struct {
    allocator: std.mem.Allocator,
    board: Board = undefined,
    stdout: std.fs.File.Writer,
    stdin: std.fs.File.Reader,

    moveGen: *MoveGen,

    bot: Bot.ChessBot,

    running: bool = false,

    pub fn new(allocator: std.mem.Allocator, stdout: std.fs.File.Writer, stdin: std.fs.File.Reader, moveGen: *MoveGen) !UCI {
        return UCI{
            .allocator = allocator,
            .stdout = stdout,
            .stdin = stdin,
            .bot = undefined,
            .moveGen = moveGen,
        };
    }

    pub fn setBot(self: *UCI, bot: Bot.ChessBot) void {
        self.bot = bot;
    }

    pub fn afterGoCommand(self: *UCI) !void {
        const boardStr = try self.board.toString(self.allocator);
        defer self.allocator.free(boardStr);

        try self.stdout.print("{s}\n", .{boardStr});
    }

    pub fn recieveFENLoadCommand(self: *UCI, cmd_str: []const u8, iterator: *std.mem.TokenIterator(u8, .any)) !void {
        const fenstart = iterator.index;
        for (0..6) |_| {
            if (iterator.next() == null) {
                return UCIError.InvalidPosition;
            }
        }
        const fenend = iterator.index;
        const fen = cmd_str[fenstart + 1 .. fenend]; // -1

        try self.board.loadFEN(fen);
    }

    pub fn recieveCommand(self: *UCI, cmd_str: []const u8) !void {
        if (std.mem.eql(u8, cmd_str, "uci")) {
            _ = try self.stdout.write("uciok\n");
            return;
        }
        if (std.mem.eql(u8, cmd_str, "isready")) {
            _ = try self.stdout.write("readyok\n");
            return;
        }
        if (std.mem.eql(u8, cmd_str, "ucinewgame")) {
            self.board = try Board.emptyBoard(self.allocator, self.moveGen);
            return;
        }
        if (std.mem.eql(u8, cmd_str, "quit")) {
            self.running = false;
            return;
        }
        if (std.mem.eql(u8, cmd_str, "legalmoves")) {
            const legalMoves = try self.moveGen.generateMoves(self.allocator, &self.board, self.board.turn, .{});
            for (legalMoves) |move| {
                const moveStr = try move.toString(self.allocator);
                defer self.allocator.free(moveStr);
                _ = try self.stdout.print("{s} ", .{moveStr});
            }
            _ = try self.stdout.print("\n", .{});
            return;
        }
        var tokenized = std.mem.tokenizeAny(u8, cmd_str, " ");
        const first = tokenized.next() orelse {
            return UCIError.InvalidCommand;
        };
        if (std.mem.eql(u8, first, "position")) {
            const loadtype = tokenized.next() orelse {
                return UCIError.InvalidCommand;
            };
            if (std.mem.eql(u8, loadtype, "fen")) {
                try self.recieveFENLoadCommand(cmd_str, &tokenized);
            } else if (std.mem.eql(u8, loadtype, "startpos")) {
                try self.board.loadFEN(startposition);
            }
            _ = tokenized.next() orelse {
                return;
            }; // Skip "moves"
            var lastMove: []const u8 = "";
            while (tokenized.next()) |next| {
                lastMove = next;
            }
            try self.board.makeMove(try Move.fromUCIStr(lastMove));
        }
        if (std.mem.eql(u8, first, "go")) {
            // Ignore time control, just get the best move
            const newBoard = try self.allocator.create(Board);

            newBoard.* = self.board;

            const move = try self.bot.getMove(newBoard);

            try self.board.makeMove(move);
            self.allocator.destroy(newBoard);

            const moveStr = try move.toString(self.allocator);
            defer self.allocator.free(moveStr);
            _ = try self.stdout.print("bestmove {s}\n", .{moveStr});

            afterGoCommand(self) catch |err| {
                std.debug.print("Error after go command: {!}\n", .{err});
            };
            return;
        }
    }

    pub fn run(self: *UCI) !void {
        self.running = true;
        while (self.running) {
            const line = try self.stdin.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024) orelse unreachable;
            defer self.allocator.free(line);

            if (line.len == 0) {
                continue; // EOF or empty line
            }
            const cmd_str = std.mem.trim(u8, line, "\r\n");

            try self.recieveCommand(cmd_str);
        }
    }

    pub fn deinit(self: *UCI) void {
        self.board.deinit();
    }
};
