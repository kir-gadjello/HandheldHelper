#!/bin/bash -l
NDK="$ANDROID_HOME/ndk/25.2.9519653";
#echo $ANDROID_HOME;

echo "$NDK/build/cmake/android.toolchain.cmake"
cd ../llama.cpp || exit;
rm -rf build-arm64-v8a;
mkdir build-arm64-v8a;
cd build-arm64-v8a || exit;
cmake -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/25.2.9519653/build/cmake/android.toolchain.cmake" \
-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-23 \
-DCMAKE_C_FLAGS=-march=armv8.4a+dotprod \
-DBUILD_SHARED_LIBS=1 ..
cmake --build . --config Release --target rpcserver server_oaicompat;
cd ..;

cp ./build-arm64-v8a/examples/server/librpcserver.so ../handheld_helper/native/arm64-v8a
cp ./examples/server/rpcserver.h ../handheld_helper/native/
cp ./examples/server/rpcserver.h ../handheld_helper/
cp ./build-arm64-v8a/libllama.so ../handheld_helper/native/arm64-v8a

cd ../handheld_helper || exit;
#cp native/ggml-metal.metal macos/Runner/
#cp native/*.dylib macos/Runner/
#cp native/*.dylib .

flutter pub run ffigen;