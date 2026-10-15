#!/usr/bin/env bash
# install.sh — install anod and the ano CLI into ~/.local/bin (or $PREFIX/bin).
#   usage: anod/install.sh [--test] [--prebuilt]
#     --test      run go test ./... before building
#     --prebuilt  install prebuilt binaries instead of building (automatic when
#                 Go isn't installed): dist/linux-<arch>/ if present, else the
#                 GitHub release tarball (checksum-verified) from a channel:
#                   ANO_RELEASE=vX.Y.Z   a tagged version
#                   ANO_CHANNEL=stable   rolling build of main (the default)
#                   ANO_CHANNEL=dev      rolling build of dev (the default when
#                                        this checkout is on the dev branch)
#                 ANO_RELEASE_URL points at a mirror.
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
    if [[ ! -x "$src/ano" || ! -x "$src/anod" ]]; then
        # No local build: fetch the release tarball and verify its checksum.
        repo="https://github.com/AnoRebel/AnoShell/releases"
        branch="$(git -C .. branch --show-current 2>/dev/null || true)"
        [[ "$branch" == dev ]] && default_channel=dev || default_channel=stable
        # A version is its own tag; channels are the rolling channel-<name> tags.
        if [[ -n "${ANO_RELEASE:-}" ]]; then rel="$ANO_RELEASE"; else rel="channel-${ANO_CHANNEL:-$default_channel}"; fi
        url="${ANO_RELEASE_URL:-$repo/download/$rel}" # a mirror, or a local server for testing
        asset="anoshell-linux-$arch.tar.gz"
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
        # A progress bar on a terminal, quiet otherwise.
        fetch() {
            if command -v curl >/dev/null; then
                if [[ -t 2 ]]; then curl -fL --progress-bar -o "$2" "$1"; else curl -fsSL -o "$2" "$1"; fi
            elif [[ -t 2 ]]; then wget -q --show-progress -O "$2" "$1"
            else wget -qO "$2" "$1"; fi
        }
        echo "downloading $asset ($rel) from $url"
        fetch "$url/$asset" "$tmp/$asset" && fetch "$url/SHA256SUMS" "$tmp/SHA256SUMS" \
            || { echo "download failed from $url (no release yet? install Go instead)" >&2; exit 1; }
        (cd "$tmp" && grep " $asset\$" SHA256SUMS | sha256sum -c --quiet -) \
            || { echo "checksum mismatch for $asset; not installing" >&2; exit 1; }
        src="$tmp/x"; mkdir -p "$src"; tar -C "$src" -xzf "$tmp/$asset"
    fi
    install -m 0755 "$src/anod" "$src/ano" "$bin/"
    echo "installed prebuilt anod + ano $(cat "$src/VERSION" 2>/dev/null) to $bin"
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
