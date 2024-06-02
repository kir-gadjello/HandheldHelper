#!/bin/bash -l
NDK="$ANDROID_HOME/ndk/25.2.9519653";

HHH_DIR=$(pwd)

mkdir -p "./native"
rm -rf "./native/arm64-v8a"
mkdir -p "./native/arm64-v8a"

echo "$NDK/build/cmake/android.toolchain.cmake"
cd "$LLAMACPP_EMBED_DIR" || exit;

rm -rf build-arm64-v8a;
mkdir build-arm64-v8a;
cd build-arm64-v8a || exit;
cmake -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/25.2.9519653/build/cmake/android.toolchain.cmake" \
-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-23 \
-DCMAKE_C_FLAGS=-march=armv8.4a+dotprod \
-DBUILD_SHARED_LIBS=1 ..
cmake --build . --config Release --target rpcserver server_oaicompat;
cd ..;

cp "$LLAMACPP_EMBED_DIR/build-arm64-v8a/examples/server/librpcserver.so" "$HHH_DIR/native/arm64-v8a"
cp "$LLAMACPP_EMBED_DIR/examples/server/rpcserver.h" "$HHH_DIR/native/"
#cp "$LLAMACPP_EMBED_DIR/examples/server/rpcserver.h" "$HHH_DIR/"
#cp ./build-arm64-v8a/libllama.so "$HHH_DIR/native/arm64-v8a"

cd $HHH_DIR || exit;

mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp -R native/arm64-v8a/* android/app/src/main/jniLibs/arm64-v8a/

dart run ffigen;