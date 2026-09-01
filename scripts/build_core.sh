#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
source_revision="650ef881c8fb216259e4ebcfbd74234554c39612"
gomobile_version="v0.1.12"
go_toolchain="go1.25.5"
expected_device_hash="7aea9ec03b31b0fc45f4533ede934c54b4030b435faeceefc3e139eca2ff677a"
expected_simulator_hash="dd33886edab107eb841a5c18f2724ed1b358ec03ea6c608fda25a1670b205f6f"
build_root="$(mktemp -d /private/tmp/aster-libbox-build.XXXXXX)"
source_root="$build_root/sing-box"
isolated_gopath="$build_root/gopath"
output="$source_root/Libbox.xcframework"
destination="$repository_root/Aster/Frameworks/Libbox.xcframework"
patch_file="$repository_root/scripts/libbox-minimal-tags.patch"

cleanup() {
  rm -rf "$build_root"
}
trap cleanup EXIT

echo "Cloning pinned sing-box source..."
git clone --quiet https://github.com/SagerNet/sing-box.git "$source_root"
git -C "$source_root" checkout --quiet --detach "$source_revision"
git -C "$source_root" apply --check "$patch_file"
git -C "$source_root" apply "$patch_file"

mkdir -p "$isolated_gopath"
echo "Installing pinned gomobile tool..."
env GOPATH="$isolated_gopath" GOTOOLCHAIN="$go_toolchain" \
  go install "github.com/sagernet/gomobile/cmd/gomobile@$gomobile_version"

echo "Building minimal iOS/iOS Simulator Libbox with uTLS..."
(
  cd "$source_root"
  env GOPATH="$isolated_gopath" GOTOOLCHAIN="$go_toolchain" \
    PATH="$isolated_gopath/bin:$PATH" \
    go run ./cmd/internal/build_libbox -target apple -platform ios,iossimulator
)

device_binary="$output/ios-arm64/Libbox.framework/Versions/A/Libbox"
simulator_binary="$output/ios-arm64_x86_64-simulator/Libbox.framework/Versions/A/Libbox"
device_hash="$(shasum -a 256 "$device_binary" | awk '{print $1}')"
simulator_hash="$(shasum -a 256 "$simulator_binary" | awk '{print $1}')"

if [[ "$device_hash" != "$expected_device_hash" || "$simulator_hash" != "$expected_simulator_hash" ]]; then
  echo "error: Libbox hashes differ from the reviewed build." >&2
  echo "device:    $device_hash" >&2
  echo "simulator: $simulator_hash" >&2
  exit 1
fi

for binary in "$device_binary" "$simulator_binary"; do
  strings "$binary" | grep -E -- '-tags=with_utls,ios(,iossimulator)?,with_low_memory' >/dev/null || {
    echo "error: required uTLS/low-memory build tags are missing from $binary" >&2
    exit 1
  }
  nm -gU "$binary" 2>/dev/null | grep '_LibboxGetTunnelFileDescriptor$' >/dev/null || {
    echo "error: public tunnel file-descriptor bridge is missing from $binary" >&2
    exit 1
  }
done

ditto "$output" "$destination"
echo "Libbox rebuilt and verified at $destination"
