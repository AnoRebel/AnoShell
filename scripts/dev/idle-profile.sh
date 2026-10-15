#!/usr/bin/env bash
# idle-profile.sh — what keeps the shell awake while idle.
#
# usage: idle-profile.sh [SECONDS=60] [WARMUP=20]
#   Starts a separate `qs -c ano` under the QML debugger (uses your config; run
#   it while ano itself is NOT running), waits WARMUP s, records SECONDS of idle
#   with qmlprofiler, and reports:
#     - QML signal handlers / timers / bindings by source file:line (count, time)
#     - child processes the shell spawned during the window (by command)
set -euo pipefail
secs=${1:-60}; warm=${2:-20}
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
port=$((20000 + RANDOM % 20000))

qs -c ano --debug "$port" --waitfordebug >"$work/qs.log" 2>&1 &
qspid=$!
mkfifo "$work/ctl"
( sleep "$((warm + secs))"; echo "f $work/trace.qtd"; sleep 10; echo q; sleep 1; echo y ) >"$work/ctl" &
/usr/lib/qt6/bin/qmlprofiler --interactive --attach localhost --port "$port" <"$work/ctl" >"$work/prof.log" 2>&1 &
profpid=$!

# Count processes spawned by qs during the measured window (after warm-up).
sleep "$warm"
declare -A seen
end=$((SECONDS + secs))
while [ $SECONDS -lt $end ]; do
    for c in $(pgrep -P "$qspid" 2>/dev/null); do
        [[ -n "${seen[$c]:-}" ]] && continue
        # A short-lived child can exit between pgrep and the read.
        seen[$c]=$( { tr '\0' ' ' < "/proc/$c/cmdline"; } 2>/dev/null | cut -c1-80 || true)
    done
    sleep 0.01
done
wait "$profpid" 2>/dev/null || true
kill "$qspid" 2>/dev/null || true

echo "== processes spawned in ${secs}s idle: ${#seen[@]}"
for c in "${!seen[@]}"; do echo "${seen[$c]}"; done | sort | uniq -c | sort -rn | head -15
echo "== QML activity in ${secs}s idle (count, ms, source)"
python3 -I "$here/qtd-summary.py" "$work/trace.qtd" "$warm"
