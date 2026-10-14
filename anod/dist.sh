#!/usr/bin/env bash
# dist.sh — cross-build static anod + ano for machines without Go.
#   dist/linux-<arch>/{anod,ano,VERSION}   used by install.sh --prebuilt
#   dist/anoshell-linux-<arch>.tar.gz      release assets (CI uploads these)
#   dist/SHA256SUMS                        checksums the installer verifies
# ANO_VERSION overrides the version string (CI passes the tag).
set -euo pipefail
cd "$(dirname "$0")"
base="$(sed -n 's/^var Version = "\(.*\)"/\1/p' internal/version/version.go)"
ver="${ANO_VERSION:-$base+$(git describe --always 2>/dev/null || echo dev)}"
rm -rf dist; mkdir -p dist
for arch in amd64 arm64; do
    out="dist/linux-$arch"; mkdir -p "$out"
    for cmd in anod ano; do
        CGO_ENABLED=0 GOOS=linux GOARCH=$arch go build -trimpath -ldflags "-s -w -X ano/anod/internal/version.Version=$ver" -o "$out/$cmd" "./cmd/$cmd"
    done
    echo "$ver" > "$out/VERSION"
    tar -C "$out" -czf "dist/anoshell-linux-$arch.tar.gz" anod ano VERSION
done
(cd dist && sha256sum anoshell-linux-*.tar.gz > SHA256SUMS)
echo "built $ver into dist/"
