#!/bin/bash -l
NDK="$ANDROID_HOME/ndk/25.2.9519653";
#echo $ANDROID_HOME;

echo "$NDK/build/cmake/android.toolchain.cmake"
cd ../llama.cpp || exit;
rm -rf build-arm64-v8a-static-compat;
mkdir build-arm64-v8a-static-compat;
cd build-arm64-v8a-static-compat || exit;
cmake -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/25.2.9519653/build/cmake/android.toolchain.cmake" \
-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-23 \
-DCMAKE_C_FLAGS=-march=armv8-a -DLLAMA_LTO=1 \
-DBUILD_SHARED_LIBS=0 -DSERVER_VERBOSE=1 -DLLAMA_SERVER_VERBOSE=1 ..
cmake --build . --config Release --target rpcserver;
cd ..;

cp ./build-arm64-v8a-static-compat/examples/server/librpcserver.so ../handheld_helper/native/arm64-v8a/librpcserver.so #-compat.so
cp ./examples/server/rpcserver.h ../handheld_helper/native/
cp ./examples/server/rpcserver.h ../handheld_helper/

cd ../handheld_helper || exit;

mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp -R native/arm64-v8a/librpcserver.so android/app/src/main/jniLibs/arm64-v8a/

flutter pub run ffigen;