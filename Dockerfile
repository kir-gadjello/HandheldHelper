
FROM ghcr.io/cirruslabs/flutter:3.22.1

CMD ["dart --disable-analytics"]

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=$ANDROID_SDK_ROOT
ENV PATH=$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    make \
    cmake \
    unzip \
    openjdk-11-jdk \
    && rm -rf /var/lib/apt/lists/*

# Create directories for Android SDK
RUN mkdir -p $ANDROID_SDK_ROOT/cmdline-tools

# Download and extract Android SDK Command-line Tools
RUN curl -o commandlinetools.zip https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip \
    && unzip commandlinetools.zip -d $ANDROID_SDK_ROOT/cmdline-tools \
    && mv $ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools $ANDROID_SDK_ROOT/cmdline-tools/latest \
    && rm commandlinetools.zip

# Accept licenses
RUN yes | sdkmanager --licenses --no_https

# Install platform tools and NDK
RUN sdkmanager --install "platform-tools" "build-tools;34.0.0" "platforms;android-23" "ndk;25.2.9519653" --verbose

ENV ANDROID_HOME="/opt/android-sdk-linux"

# Clean up
RUN apt-get clean

# Set up working directory
WORKDIR /app

COPY . .

CMD ["/bin/bash"]

#
# RUN rebuild_native_libs.sh android
#
# RUN flutter pub get
#
# # Run flutter doctor to pre-cache Flutter dependencies
# RUN flutter doctor -v
#
# # Build the Flutter app (you can specify a different target like web or ios)
# RUN flutter build apk --release
#
# # The output APK will be in the build/app/outputs/flutter-apk directory