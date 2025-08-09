#!/bin/bash

echo -e "ucinewgame\nposition fen $1\nlegalmoves\n" | zig build run --release=fast -- run-uci
