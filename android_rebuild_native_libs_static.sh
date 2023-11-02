#!/bin/bash -l
NDK="$ANDROID_HOME/ndk/25.2.9519653";
#echo $ANDROID_HOME;

echo "$NDK/build/cmake/android.toolchain.cmake"
cd ../llama.cpp || exit;
rm -rf build-arm64-v8a-static;
mkdir build-arm64-v8a-static;
cd build-arm64-v8a-static || exit;
cmake -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/25.2.9519653/build/cmake/android.toolchain.cmake" \
-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-23 \
-DCMAKE_C_FLAGS=-march=armv8.4a+dotprod \
-DBUILD_SHARED_LIBS=0 -DSERVER_VERBOSE=1 -DLLAMA_SERVER_VERBOSE=1 ..
cmake --build . --config Release --target rpcserver server_oaicompat;
cd ..;

cp ./build-arm64-v8a-static/examples/server/librpcserver.so ../handheld_helper/native/arm64-v8a
cp ./examples/server/rpcserver.h ../handheld_helper/native/
cp ./examples/server/rpcserver.h ../handheld_helper/
# cp ./build-arm64-v8a-static/libllama.so ../handheld_helper/native/arm64-v8a

cd ../handheld_helper || exit;

mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp -R native/arm64-v8a/* android/app/src/main/jniLibs/arm64-v8a/

flutter pub run ffigen;