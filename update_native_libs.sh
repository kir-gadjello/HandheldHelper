#!/bin/bash

cp ../llama.cpp/ggml-metal.metal native/
cp ../llama.cpp/build/examples/server/librpcserver.dylib native/
cp ../llama.cpp/build/libllama.dylib native/
cp native/ggml-metal.metal macos/Runner/
cp native/*.dylib macos/Runner/
