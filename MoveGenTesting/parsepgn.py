# Requires: pip install python-chess
import chess.pgn

infile = "KingBaseLite2019-01.pgn"  # large PGN file you downloaded
outfile = "fens.txt"  # output: one FEN per line

with open(infile, encoding="utf-8") as pgn, open(outfile, "w", encoding="utf-8") as out:
    i = 0
    while True:
        i += 1
        print("Processing game", i + 1, end="\r")

        game = chess.pgn.read_game(pgn)
        if game is None:
            break
        board = game.board()
        # write starting position if you want: out.write(board.fen() + "\n")
        for move in game.mainline_moves():
            board.push(move)
            out.write(board.fen() + "\n")
