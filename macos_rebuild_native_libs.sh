#!/bin/bash -l
BUILD_ARCH="apple_silicon"

HHH_DIR=$(pwd)
DST_DIR="$HHH_DIR/native/$BUILD_ARCH"
HEADER_DIR="$HHH_DIR/native"

mkdir -p "./native"
rm -rf "$DST_DIR"
mkdir -p "$DST_DIR"

cd "$LLAMACPP_EMBED_DIR" || exit;

BUILD_DIR="build-$BUILD_ARCH"

rm -rf "$BUILD_DIR";
mkdir "$BUILD_DIR";
cd "$BUILD_DIR" || exit;

cmake .. -DBUILD_SHARED_LIBS=1 -DLLAMA_METAL=1
cmake --build . --config Release --target rpcserver;
cd ..;

cp "$LLAMACPP_EMBED_DIR/$BUILD_DIR/examples/server/librpcserver.dylib" "$DST_DIR/"
cp "$LLAMACPP_EMBED_DIR/$BUILD_DIR/libllama.dylib" "$DST_DIR/"
cp "$LLAMACPP_EMBED_DIR/ggml-metal.metal" "$DST_DIR/"
cp "$LLAMACPP_EMBED_DIR/examples/server/rpcserver.h" "$HEADER_DIR/"

cd "$HHH_DIR";
cp "$DST_DIR/ggml-metal.metal" macos/Runner/
cp "$DST_DIR/librpcserver.dylib" macos/Runner/
cp "$DST_DIR/libllama.dylib" macos/Runner/

cd $HHH_DIR || exit;

dart run ffigen;