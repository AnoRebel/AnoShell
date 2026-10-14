#!/usr/bin/env bash
# install.sh — install anod and the ano CLI into ~/.local/bin (or $PREFIX/bin).
#   usage: anod/install.sh [--test] [--prebuilt]
#     --test      run go test ./... before building
#     --prebuilt  copy the bundled binaries from dist/linux-<arch>/ instead of
#                 building (automatic when Go isn't installed)
set -euo pipefail
cd "$(dirname "$0")"
bin="${PREFIX:-$HOME/.local}/bin"
test=0 prebuilt=0
for a in "$@"; do
    case "$a" in
        --test) test=1 ;;
        --prebuilt) prebuilt=1 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done
command -v go >/dev/null 2>&1 || prebuilt=1
mkdir -p "$bin"
if (( prebuilt )); then
    case "$(uname -m)" in
        x86_64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) echo "no bundled binaries for $(uname -m); install Go and rerun" >&2; exit 1 ;;
    esac
    src="dist/linux-$arch"
    [[ -x "$src/ano" && -x "$src/anod" ]] || { echo "no bundled binaries in anod/$src (run anod/dist.sh on a machine with Go, or install Go)" >&2; exit 1; }
    install -m 0755 "$src/anod" "$src/ano" "$bin/"
    echo "installed bundled anod + ano $(cat "$src/VERSION" 2>/dev/null) to $bin"
else
    (( test )) && go test ./...
    base="$(sed -n 's/^var Version = "\(.*\)"/\1/p' internal/version/version.go)"
    ver="$base+$(git describe --always --dirty 2>/dev/null || echo dev)"
    for cmd in anod ano; do
        CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X ano/anod/internal/version.Version=$ver" -o "$bin/$cmd" "./cmd/$cmd"
    done
    echo "installed anod + ano $ver to $bin"
fi
case ":$PATH:" in *":$bin:"*) ;; *) echo "note: $bin is not in PATH" ;; esac
