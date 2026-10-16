#!/usr/bin/env bash
# Toggle a screen recording. With the shell running this goes through it
# (recording.backend picks the recorder); without it, a plain fallback with
# the first recorder installed.
#   record.sh            region (slurp); again to stop
#   record.sh --fullscreen [--sound]
mode=region; sound=false
for a in "$@"; do case "$a" in --fullscreen) mode=screen ;; --sound) sound=true ;; esac; done
if qs -c ano ipc call recorder status >/dev/null 2>&1; then
    if [ "$mode" = region ]; then exec qs -c ano ipc call recorder toggle; fi
    exec qs -c ano ipc call recorder toggleScreen "$($sound && echo audio || echo none)"
fi
for r in gpu-screen-recorder wl-screenrec wf-recorder; do
    if pgrep -x "$r" >/dev/null; then pkill -INT -x "$r"; exit 0; fi
done
dir="${XDG_VIDEOS_DIR:-$HOME/Videos}"; mkdir -p "$dir"
file="$dir/Recording_$(date +%Y%m%d_%H%M%S).mp4"
geom=""; [ "$mode" = region ] && { geom="$(slurp)" || exit 1; }
if command -v wl-screenrec >/dev/null; then
    args=(-f "$file"); [ -n "$geom" ] && args+=(-g "$geom"); $sound && args+=(--audio); exec wl-screenrec "${args[@]}"
elif command -v wf-recorder >/dev/null; then
    args=(-f "$file"); [ -n "$geom" ] && args+=(-g "$geom"); $sound && args+=(--audio); exec wf-recorder "${args[@]}"
else
    notify-send -a "Ano Shell" "No screen recorder installed" "Install gpu-screen-recorder, wl-screenrec or wf-recorder."
    exit 1
fi
