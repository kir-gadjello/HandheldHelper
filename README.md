# Handheld Helper

Basic AI capability should be owned by everyone.

An AI that fits in the palm of your hand.

# Hardware requirements
* Mobile: An Android smartphone with >=4GiB RAM
* Desktop: A Mac M1 with >=16GiB RAM, a Linux PC with >=16GiB RAM

# Building

TBD

## MacOS
Note that you will have to deal with signing or bypassing app signature warning on your own.
```bash
./rebuild_native_libs.sh 'apple_silicon'
fvm use 3.22.2
fvm flutter pub run flutter_launcher_icons:main
fvm flutter build macos --release;
```
## Linux
TBD

## Android
```bash
./rebuild_native_libs.sh 'android'
fvm use 3.22.2
fvm flutter pub run flutter_launcher_icons:main
fvm flutter build apk --release;
```
=>
```
Running Gradle task 'assembleDebug'...                            528.2s
✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

# IMPORTANT LICENSE NOTICE
Please be aware that this software project is licensed under the GNU General Public License Agreement Version 3 (GPLv3) with additional restrictions. By using, modifying, or distributing this software, you agree to be bound by the terms and conditions of this license.

## KEY RESTRICTIONS
You are prohibited from using any part of this software to build applications and plugins that are published on appstore-like platforms, including but not limited to Google Play, Apple App Store, and Jetbrains Marketplace.
Only Kirill Gadzhello, the creator of this software, is permitted to create and publish applications and plugins based on this software on appstore-like platforms.

## VIOLATIONS WILL BE ENFORCED
Failure to comply with these terms may result in legal action, including notification of the appropriate appstore administration. By using this software, you acknowledge that you have read, understand, and agree to be bound by the terms and conditions of this license.
Please ensure that you understand and comply with the terms of this license before using, modifying, or distributing this software.