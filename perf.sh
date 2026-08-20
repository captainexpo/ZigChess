sudo perf record -F 9999 --call-graph=fp zig-out/bin/bench 2000000

sudo perf script | stackcollapse-perf.pl > out.folded
flamegraph.pl out.folded > flame.svg
