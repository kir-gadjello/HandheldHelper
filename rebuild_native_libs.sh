#!/bin/bash -l

# Check if LLAMACPP_EMBED_DIR exists and is a valid directory
if [ -z "$LLAMACPP_EMBED_DIR" ]; then
  LLAMACPP_EMBED_DIR="$(pwd)/llamacpp-embed"
  if [ ! -d "$LLAMACPP_EMBED_DIR" ]; then
    echo "LLAMACPP_EMBED_DIR is not set and local directory $LLAMACPP_EMBED_DIR does not exist. Initializing submodule..."
    git submodule update --init --recursive
  fi
else
  if [ ! -d "$LLAMACPP_EMBED_DIR" ]; then
    echo "LLAMACPP_EMBED_DIR is not a valid directory. Please set it to the correct directory."
    exit 1
  fi
fi

HHH_DIR=$(pwd)
HEADER_DIR="./native"

# Set variables based on the input argument
if [ "$1" = "android-arm64-v8a-dotprod" ] || [ "$1" = "android" ]; then
  BUILD_FLAVOR="android"
  BUILD_ARCH="android-arm64-v8a"
  NDK="$ANDROID_HOME/ndk/25.2.9519653"
  TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
  CMAKE_FLAGS="-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-23 -DCMAKE_C_FLAGS=-march=armv8.4a+dotprod -DBUILD_SHARED_LIBS=1"
  LIB_EXT="so"
  TARGET_DIR="android/app/src/main/jniLibs/arm64-v8a"
elif [ "$1" = "apple-silicon" ]; then
  BUILD_FLAVOR="apple-silicon"
  BUILD_ARCH="apple_silicon"
  CMAKE_FLAGS="-DBUILD_SHARED_LIBS=1 -DLLAMA_METAL=1"
  LIB_EXT="dylib"
  TARGET_DIR="macos/Runner"
else
  echo "Invalid argument. Please specify 'android', 'android-arm64-v8a-dotprod' or 'apple-silicon'."
  exit 1
fi

BUILD_DIR="build-$BUILD_ARCH"
DST_DIR="native/$BUILD_ARCH"

# Create directories
mkdir -p "native"
rm -rf "$DST_DIR"
mkdir -p "$DST_DIR"

# Change into the LLAMACPP_EMBED_DIR directory
cd "$LLAMACPP_EMBED_DIR" || exit

# Create build directory and configure CMake
rm -rf "$BUILD_DIR"
mkdir "$BUILD_DIR"
cd "$BUILD_DIR" || exit
cmake .. $CMAKE_FLAGS
cmake --build . --config Release --target rpcserver

# Copy built artifacts
cp "$LLAMACPP_EMBED_DIR/$BUILD_DIR/examples/server/librpcserver.$LIB_EXT" "$HHH_DIR/$DST_DIR/"
cp "$LLAMACPP_EMBED_DIR/$BUILD_DIR/libllama.$LIB_EXT" "$HHH_DIR/$DST_DIR/"
cp "$LLAMACPP_EMBED_DIR/examples/server/rpcserver.h" "$HHH_DIR/$HEADER_DIR/"
if [ "$BUILD_FLAVOR" = "apple-silicon" ]; then
  cp "$LLAMACPP_EMBED_DIR/ggml-metal.metal" "$HHH_DIR/$DST_DIR/"
fi

# Copy artifacts to target directory
if [ "$BUILD_FLAVOR" = "android" ]; then
  mkdir -p "$HHH_DIR/$TARGET_DIR"
  echo "$HHH_DIR/$DST_DIR/"
  cp "$HHH_DIR/$DST_DIR/"* "$HHH_DIR/$TARGET_DIR/"
else
  cp "$HHH_DIR/$DST_DIR/ggml-metal.metal" "$HHH_DIR/$TARGET_DIR/"
  cp "$HHH_DIR/$DST_DIR/librpcserver.$LIB_EXT" "$HHH_DIR/$TARGET_DIR/"
  cp "$HHH_DIR/$DST_DIR/libllama.$LIB_EXT" "$HHH_DIR/$TARGET_DIR/"
fi

# Run ffigen
cd "$HHH_DIR" || exit
dart run ffigen