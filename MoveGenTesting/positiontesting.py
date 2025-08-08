import chess
import chess.engine
import subprocess

import sys

engine = chess.engine.SimpleEngine.popen_uci(sys.argv[1])
zigengine = subprocess.Popen(
    ["../zig-out/bin/Engine", "run-uci"], stdin=subprocess.PIPE, stdout=subprocess.PIPE
)

if zigengine.stdin is None or zigengine.stdout is None:
    raise RuntimeError("Zig engine is not properly initialized.")


zigengine.stdin.write(b"ucinewgame\n")
zigengine.stdin.flush()


def get_moves(fen: str) -> list[str]:
    if zigengine.stdin is None or zigengine.stdout is None:
        raise RuntimeError("Zig engine is not properly initialized.")
    zigengine.stdin.write(b"position fen " + fen.encode() + b"\n")
    zigengine.stdin.flush()
    zigengine.stdin.write(b"legalmoves\n")
    zigengine.stdin.flush()
    result = zigengine.stdout.readline().decode().strip().split(" ")
    return result


with open("fens.txt") as f:
    print("Testing positions...")
    good = 0
    bad = 0
    for line in f:
        fen = line.strip()
        board = chess.Board(fen)

        zig_moves = set(get_moves(fen))
        stockfish_moves = set(str(m) for m in board.legal_moves)

        if not zig_moves:
            print(f"\033[93m⚠ No moves from Zig: {fen}\033[0m")
            continue

        if zig_moves != stockfish_moves:
            bad += 1
            only_yours = zig_moves - stockfish_moves
            missing = stockfish_moves - zig_moves

            print(f"\033[91m✘ {fen}\033[0m")
            if only_yours:
                print(f"  \033[94mYour only : {sorted(only_yours)}\033[0m")
            if missing:
                print(f"  \033[95mMissing   : {sorted(missing)}\033[0m")
        else:
            good += 1
            print(f"\033[92m✔ {fen}\033[0m")
    print(f"\n{good} good positions, {bad} bad positions.")
engine.quit()
