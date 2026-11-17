#!/usr/bin/env bash
# Location from the Wi-Fi access points around you (services/Location.qml, location.wifi).
# Sends their hardware addresses and signal strengths, no names, to beaconDB's
# Ichnaea-compatible API (https://beacondb.net). Prints {"lat","lon","accuracy"} or exits 1.
set -euo pipefail

command -v nmcli >/dev/null && command -v jq >/dev/null && command -v curl >/dev/null || exit 1
[ "$(nmcli radio wifi 2>/dev/null)" = enabled ] || exit 1

# nmcli --terse escapes the colons inside a field as "\:", so a line is SIGNAL:BSSID:SSID.
# Left out: networks whose owners opted out (SSID ending in _nomap), randomised/locally
# administered addresses (they move with phones and hotspots), and very weak ones.
request=$(nmcli --terse --fields SIGNAL,BSSID,SSID device wifi list --rescan auto 2>/dev/null | jq -R -s '
  [ split("\n")[]
    | capture("^(?<sig>[0-9]+):(?<mac>(?:[0-9A-Fa-f]{2}\\\\:){5}[0-9A-Fa-f]{2}):(?<ssid>.*)$")?
    | select(.ssid | test("_nomap$") | not)
    | { macAddress: (.mac | gsub("\\\\"; "") | ascii_downcase),
        signalStrength: ((.sig | tonumber) / 2 - 100 | floor) }
    | select(.macAddress | test("^.[2367abef]") | not)
    | select(.signalStrength >= -95) ]
  | unique_by(.macAddress)
  | { considerIp: false, fallbacks: { ipf: false, lacf: false }, wifiAccessPoints: . }')

# The API needs at least two access points to place you.
jq -e '.wifiAccessPoints | length >= 2' <<<"$request" >/dev/null || exit 1

resp=$(curl -fsS --max-time 10 -H 'Content-Type: application/json' -H 'User-Agent: AnoShell-location/1' \
  --data-binary "$request" https://api.beacondb.net/v1/geolocate) || exit 1

jq -ce 'select((.location.lat | type) == "number" and (.location.lng | type) == "number"
               and (.location.lat | fabs) <= 90 and (.location.lng | fabs) <= 180 and .fallback == null)
        | { lat: .location.lat, lon: .location.lng, accuracy: (.accuracy // 0) }' <<<"$resp"
