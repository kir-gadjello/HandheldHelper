// import 'dart:isolate';
// import 'dart:convert';
// import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';

bool isMobile() => Platform.isAndroid;
bool isDevelopment() =>
    const String.fromEnvironment("DEVELOPMENT", defaultValue: "").isNotEmpty;

String capitalizeAllWord(String value) {
  var result = value[0].toUpperCase();
  for (int i = 1; i < value.length; i++) {
    if (value[i - 1] == " ") {
      result = result + value[i].toUpperCase();
    } else {
      result = result + value[i];
    }
  }
  return result;
}

String truncateWithEllipsis(int cutoff, String myString) {
  return (myString.length <= cutoff)
      ? myString
      : '${myString.substring(0, cutoff)}...';
}

Future<int> checkFileSize(String path) async {
  try {
    // Resolve symbolic links
    String resolvedPath = await File(path).resolveSymbolicLinks();

    // Check if file exists
    if (await File(resolvedPath).exists()) {
      // Get file size
      int size = await File(resolvedPath).length();
      return size;
    }
  } catch (e) {
    // If the file does not exist or is a directory, return -1
    return -1;
  }

  return -1;
}

String humanReadableDate(DateTime date) {
  final dt = date;
  final now = DateTime.now();
  final firstDayOfWeek =
      DateTime(now.year, now.month, now.day - now.weekday + 1);
  final isInCurrentWeek = dt.isAfter(firstDayOfWeek) &&
      dt.isBefore(firstDayOfWeek.add(Duration(days: 7)));

  String heading;

  if (dt.difference(now).inDays == 0) {
    heading = "Today, ${DateFormat('HH:mm:ss').format(dt)}";
  } else if (dt.difference(now.subtract(Duration(days: 1))).inDays == 0) {
    heading = "Yesterday, ${DateFormat('HH:mm:ss').format(dt)}";
  } else if (isInCurrentWeek) {
    final dateFormat = DateFormat('EEEE, HH:mm:ss');
    heading = dateFormat.format(dt);
  } else {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    heading = dateFormat.format(dt);
  }

  return heading;
}
