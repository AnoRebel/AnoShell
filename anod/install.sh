#!/usr/bin/env bash
# install.sh — build anod and the ano CLI into ~/.local/bin (or $PREFIX/bin).
#   usage: anod/install.sh [--test]   (--test runs go test ./... first)
set -euo pipefail
cd "$(dirname "$0")"
bin="${PREFIX:-$HOME/.local}/bin"
[[ "${1:-}" == "--test" ]] && go test ./...
base="$(sed -n 's/^var Version = "\(.*\)"/\1/p' internal/version/version.go)"
ver="$base+$(git describe --always --dirty 2>/dev/null || echo dev)"
mkdir -p "$bin"
for cmd in anod ano; do
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X ano/anod/internal/version.Version=$ver" -o "$bin/$cmd" "./cmd/$cmd"
done
echo "installed anod + ano $ver to $bin"
case ":$PATH:" in *":$bin:"*) ;; *) echo "note: $bin is not in PATH" ;; esac
