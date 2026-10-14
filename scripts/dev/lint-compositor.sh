#!/usr/bin/env bash
# lint-compositor.sh — compositor specifics must stay behind CompositorService.
# Fails if any QML outside services/compositor/ (and the niri IPC client
# services/NiriService.qml, plus the niri-only MinimizedWindows emulation) runs hyprctl / niri msg or uses Quickshell.Hyprland,
# except Hyprland GlobalShortcut (bind integration until keybinds go through IPC, task 10.13).
set -euo pipefail
cd "$(dirname "$0")/../.."
allowed='^(services/compositor/|services/NiriService\.qml|services/NiriKeybinds\.qml|services/MinimizedWindows\.qml|services/HyprlandKeybinds\.qml|external/|\.backups/)'
fail=0
while IFS= read -r f; do
    [[ "$f" =~ $allowed ]] && continue
    hits=$(grep -nE '"hyprctl"|"niri", *"msg"|\bHyprland\.[a-zA-Z]|NiriService\.[a-zA-Z]+\(' "$f" | grep -v '^\s*//' || true)
    if grep -q 'import Quickshell.Hyprland' "$f" && ! grep -qE '\bGlobalShortcut\b' "$f"; then
        hits+=$'\n'"(imports Quickshell.Hyprland without using GlobalShortcut)"
    fi
    if [[ -n "${hits//[$'\n ']/}" ]]; then echo "== $f"; echo "$hits" | sed '/^$/d'; fail=1; fi
done < <(git ls-files '*.qml')
exit $fail
