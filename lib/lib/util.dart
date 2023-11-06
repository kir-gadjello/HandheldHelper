// import 'dart:isolate';
// import 'dart:convert';
// import 'dart:async';
import 'dart:io';

bool isMobile() => Platform.isAndroid;
bool isDevelopment() =>
    const String.fromEnvironment("DEVELOPMENT", defaultValue: "").isNotEmpty;
