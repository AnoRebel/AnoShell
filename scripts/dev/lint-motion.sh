#!/usr/bin/env bash
# lint-motion.sh — animations must use the motion tokens.
# Fails on literal `duration: <number>` (use AnimationConfig.scaledDuration(n) or a
# MotionNumber/MotionSpring token) and on Easing types other than BezierSpline
# (token curves from Appearance.animationCurves) and Linear (spinners, progress).
# Config.qml is exempt: its `duration` values are config data, not animations.
# widgets/ is exempt: desktop widgets (the ported Bioma organisms keep Bioma's
# own Timing tokens, and user widgets are theirs to write).
set -euo pipefail
cd "$(dirname "$0")/../.."
exempt='^modules/common/(Appearance|AnimationConfig|Config)\.qml$|^modules/common/widgets/Motion(Number|Spring)\.qml$|^widgets/'
fail=0
while IFS= read -r f; do
    [[ "$f" =~ $exempt ]] && continue
    hits=$(grep -nP '\bduration: *[0-9]|Easing\.(?!BezierSpline\b|Linear\b)[A-Z][A-Za-z]+' "$f" | grep -vP '^[0-9]+:\s*//' || true)
    if [[ -n "$hits" ]]; then echo "== $f"; echo "$hits"; fail=1; fi
done < <(git ls-files '*.qml')
exit $fail
