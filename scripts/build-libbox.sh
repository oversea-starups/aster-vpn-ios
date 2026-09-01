#!/bin/sh
set -eu

SING_BOX_TAG="v1.13.16"
GOMOBILE_VERSION="v0.1.13"
BUILD_ROOT="${TMPDIR:-/tmp}/aster-libbox-build"
OUTPUT_DIR="$PWD/build"

git clone --depth 1 --branch "$SING_BOX_TAG" \
  https://github.com/SagerNet/sing-box.git "$BUILD_ROOT/sing-box"

go install "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE_VERSION"
go install "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE_VERSION"
"$(go env GOPATH)/bin/gomobile" init

mkdir -p "$OUTPUT_DIR"
cd "$BUILD_ROOT/sing-box"
PATH="$(go env GOPATH)/bin:$PATH" "$(go env GOPATH)/bin/gomobile" bind \
  -o "$OUTPUT_DIR/Libbox.xcframework" \
  -target ios,iossimulator \
  -libname=box \
  -iosversion=16.0 \
  -tags with_gvisor,with_utls,with_clash_api,with_low_memory,grpcnotrace \
  ./experimental/libbox

ditto -c -k --sequesterRsrc --keepParent \
  "$OUTPUT_DIR/Libbox.xcframework" \
  "$OUTPUT_DIR/Libbox.xcframework.zip"
