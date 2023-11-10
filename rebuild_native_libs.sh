#!/bin/bash

cd ../llama.cpp;
rm -rf build;
mkdir build;
cd build;
cmake .. -DBUILD_SHARED_LIBS=1 -DLLAMA_METAL=1
cmake --build . --config Release --target rpcserver server_oaicompat;
cd ..;

cp ./build/examples/server/librpcserver.dylib ../handheld_helper/native/
cp ./examples/server/rpcserver.h ../handheld_helper/native/
cp ./examples/server/rpcserver.h ../handheld_helper/
cp ./build/libllama.dylib ../handheld_helper/native/
cp ./ggml-metal.metal ../handheld_helper/native/

cd ../handheld_helper;
cp native/ggml-metal.metal macos/Runner/
cp native/*.dylib macos/Runner/
cp native/*.dylib .

flutter pub run ffigen;