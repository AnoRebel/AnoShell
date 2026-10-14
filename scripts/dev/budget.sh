#!/usr/bin/env bash
# budget.sh — sample idle CPU and RSS of the ano shell (qs) and anod.
#
# usage: budget.sh [--window SECONDS] [--warmup SECONDS]
#   Measures already-running processes; start ano first and leave it idle.
#   --warmup waits before sampling (default 0), --window is the sample span (default 60).
# Output: one line per process: name pid cpu%(avg over window, of one core) rss_mb
set -euo pipefail

window=60 warmup=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --window) window="$2"; shift 2 ;;
        --warmup) warmup="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

hz=$(getconf CLK_TCK)

# pid of `qs -c ano` / `qs -p .../ano` and of anod (empty if not running)
qs_pid=$(pgrep -f -o '^qs (-c ano|-p [^ ]*/ano)( |$)' || true)
anod_pid=$(pgrep -x -o anod || true)

ticks() { awk '{print $14 + $15}' "/proc/$1/stat" 2>/dev/null || echo 0; }
rss_mb() { awk '/^VmRSS/ {printf "%.1f", $2/1024}' "/proc/$1/status" 2>/dev/null || echo 0; }

[[ -z "$qs_pid" ]] && { echo "qs -c ano is not running" >&2; exit 1; }
sleep "$warmup"

declare -A t0
for p in $qs_pid $anod_pid; do t0[$p]=$(ticks "$p"); done
sleep "$window"

report() { # name pid
    local t1; t1=$(ticks "$2")
    awk -v n="$1" -v p="$2" -v d=$((t1 - t0[$2])) -v hz="$hz" -v w="$window" -v r="$(rss_mb "$2")" \
        'BEGIN { printf "%-5s pid=%-8s cpu=%.2f%% rss=%sMB\n", n, p, 100*d/hz/w, r }'
}
report qs "$qs_pid"
[[ -n "$anod_pid" ]] && report anod "$anod_pid"
exit 0
