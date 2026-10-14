#!/usr/bin/env bash
# dist.sh — cross-build static anod + ano into dist/linux-<arch>/ for machines
# without Go (install.sh --prebuilt copies them). Run before tagging a release.
set -euo pipefail
cd "$(dirname "$0")"
base="$(sed -n 's/^var Version = "\(.*\)"/\1/p' internal/version/version.go)"
ver="$base+$(git describe --always 2>/dev/null || echo dev)"
for arch in amd64 arm64; do
    out="dist/linux-$arch"; mkdir -p "$out"
    for cmd in anod ano; do
        CGO_ENABLED=0 GOOS=linux GOARCH=$arch go build -trimpath -ldflags "-s -w -X ano/anod/internal/version.Version=$ver" -o "$out/$cmd" "./cmd/$cmd"
    done
    echo "$ver" > "$out/VERSION"
done
echo "built $ver into dist/"
