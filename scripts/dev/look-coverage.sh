#!/bin/bash
# Look coverage: every colour on a surface must come from the theme
# (Appearance.colors / m3colors) so looks and wallpapers restyle it. Flags hex
# colours in modules/ that aren't a `?? "#..."` theme fallback. Allowed: pure
# black/white scrims and outlines (legibility over images), comment lines, and
# Appearance.qml / Config.qml where the palette and defaults are defined, and
# lines marked `look-coverage: fixed (<why>)` (the readers' always-dark reading
# surfaces, whose text is light whatever the look).
cd "$(dirname "$0")/../.." || exit 2
hits=$(grep -rnE '"#[0-9A-Fa-f]{6,8}"' --include='*.qml' modules \
  | grep -vE '^modules/common/(Appearance|Config)\.qml:' \
  | grep -vE '^[^:]+:[0-9]+:\s*(//|\*)' \
  | grep -vE '\?\?\s*"#' \
  | grep -v 'look-coverage: fixed' \
  | grep -viE '"#([0-9a-f]{2})?(000000|ffffff)"' )
if [ -n "$hits" ]; then
  echo "$hits"
  echo "look-coverage: $(wc -l <<<"$hits") hard-coded colour(s); use Appearance.colors.* (colSuccess/colWarning/colInfo/colError for status)"
  exit 1
fi
echo "look-coverage: ok"
