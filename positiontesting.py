import chess
import chess.engine
import sys

engine = chess.engine.SimpleEngine.popen_uci(sys.argv[1])


with open("fens.txt") as f:
    for line in f:
        fen = line.strip()
        board = chess.Board(fen)

        # Your move generation logic
        your_moves = set(your_generate_moves(fen))  # <-- Implement this

        # Stockfish move generation
        legal_moves = set(str(m) for m in board.legal_moves)

        if your_moves != legal_moves:
            print(f"Mismatch in FEN: {fen}")
            print(f"Your moves: {your_moves}")
            print(f"Stockfish: {legal_moves}")

engine.quit()
