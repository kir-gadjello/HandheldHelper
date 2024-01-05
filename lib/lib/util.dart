// import 'dart:isolate';
// import 'dart:convert';
// import 'dart:async';
import 'dart:io';
import 'dart:collection';
// import 'dart:ui';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart';

bool isMobile() => Platform.isAndroid;
bool isDevelopment() =>
    const String.fromEnvironment("DEVELOPMENT", defaultValue: "").isNotEmpty;
void Function(Object?) dlog = (Object? args) {};

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

Future<bool> directoryExistsAndWritable(String path) async {
  final directory = Directory(path);

  // Check if directory exists
  bool exists = await directory.exists();
  if (!exists) {
    return false;
  }

  // Check if the app process can create and delete a temp file in it
  final tempFile = File('${directory.path}/._tempfile_perm_check');
  try {
    await tempFile.create();
    await tempFile.delete();
  } catch (e) {
    return false;
  }

  return true;
}

bool directoryExistsAndWritableSync(String path) {
  final directory = Directory(path);

  // Check if directory exists
  bool exists = directory.existsSync();
  if (!exists) {
    return false;
  }

  // Check if the app process can create and delete a temp file in it
  final tempFile = File('${directory.path}/._tempfile_perm_check');
  try {
    tempFile.createSync();
    tempFile.deleteSync();
  } catch (e) {
    return false;
  }

  return true;
}

final Map<String, int> sizeSuffixesDecimal = {
  'k': 1000,
  'm': 1000000,
  'g': 1000000000,
  't': 1000000000000,
};

final Map<String, int> sizeSuffixesBinary = {
  'k': 1024,
  'm': 1024 * 1024,
  'g': 1024 * 1024 * 1024,
  't': 1024 * 1024 * 1024 * 1024,
};

int? parseStringWithSuffix(String input, {bool decimal = false}) {
  input = input.toLowerCase();
  String lastChar = input.substring(input.length - 1);

  var sizeSuffixes = decimal ? sizeSuffixesDecimal : sizeSuffixesBinary;

  if (sizeSuffixes.containsKey(lastChar)) {
    String numberString = input.substring(0, input.length - 1);
    int? number = int.tryParse(numberString);
    if (number != null) {
      return number * sizeSuffixes[lastChar]!;
    }
  } else {
    return int.tryParse(input);
  }

  return null;
}

int? parse_numeric_shorthand(dynamic x, {int? fallback, bool decimal = false}) {
  if (x is String) {
    var ret = parseStringWithSuffix(x, decimal: decimal);
    if (ret != null) {
      return ret;
    }
  } else if (x is int) {
    return x;
  }
  if (fallback != null) {
    return fallback;
  }
}

int? extract_ctxlen_from_name(String s) {
  final intRegex = RegExp(r'\d+');
  final intWithSuffixRegex = RegExp(r'\d+[kK]');

  var match = intWithSuffixRegex.firstMatch(s);
  if (match != null) {
    return parseStringWithSuffix(match.group(0)!);
  }

  match = intRegex.firstMatch(s);
  if (match != null) {
    var x = int.parse(match.group(0)!);
    if (x > 512) {
      return x;
    }
  }

  return null;
}

class _AutoClearMapEntry<V> {
  final V value;
  final DateTime addedAt;

  _AutoClearMapEntry(this.value, this.addedAt);
}

class AutoClearMap<K, V> extends MapBase<K, V> {
  final Map<K, _AutoClearMapEntry<V>> _map = {};
  final int maxAge;

  AutoClearMap({required this.maxAge});

  @override
  V? operator [](Object? key) {
    final entry = _map[key as K];
    return entry?.value;
  }

  @override
  void operator []=(K key, V value) {
    _map[key] = _AutoClearMapEntry(value, DateTime.now());
    cleanUpOldEntries();
  }

  void cleanUpOldEntries() {
    _map.removeWhere((key, entry) =>
        DateTime.now().difference(entry.addedAt).inSeconds > maxAge);
  }

  @override
  Iterable<K> get keys => _map.keys.where((key) {
        final entry = _map[key];
        return entry == null ||
            DateTime.now().difference(entry.addedAt).inSeconds <= maxAge;
      });

  @override
  Iterable<V> get values => _map.values.map((entry) => entry.value);

  @override
  Iterable<MapEntry<K, V>> get entries =>
      _map.entries.map((entry) => MapEntry(entry.key, entry.value.value));

  @override
  int get length => _map.length;

  @override
  void clear() {
    _map.clear();
  }

  @override
  V? remove(Object? key) {
    final entry = _map.remove(key as K);
    return entry?.value;
  }
}

String limitText(String text, int max_out_len,
    {bool ellipsis = true, int? max_n_lines}) {
  int start = 0;
  int end = max_out_len;

  if (end > text.length) {
    end = text.length;
  }

  String limitedText = text.substring(start, end);

  if (max_n_lines != null) {
    var lines = limitedText.split('\n');
    int linesCount = lines.length;
    if (linesCount > max_n_lines) {
      limitedText = lines.sublist(0, max_n_lines).join('\n');
    }
  }

  if (ellipsis && end < text.length) {
    limitedText += '...';
  }

  return limitedText;
}

String genUuidString({int length = 16}) {
  final rng = Random();
  final bytes = <int>[];
  for (var i = 0; i < length; i++) {
    bytes.add(rng.nextInt(256));
  }
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join('')
      .toUpperCase();
}

class Memoizer {
  final Map<String, String> _cache = {};

  String memoize(String Function(String) func, String input) {
    if (_cache.containsKey(input)) {
      return _cache[input]!;
    } else {
      var result = func(input);
      _cache[input] = result;
      return result;
    }
  }
}

dynamic replaceArraysWithPlaceholder(dynamic value) {
  if (value is List) {
    return 'array of length ${value.length}';
  }
  return value;
}

dynamic shorten_gguf_metadata(Map<String, dynamic>? metadata) => (metadata ??
        {})
    .map((key, value) => MapEntry(key, replaceArraysWithPlaceholder(value)));

class MapHasher {
  static List<List<dynamic>> sortKeys(Map<String, dynamic> map) {
    var keys = map.keys.toList();
    keys.sort((a, b) => a.compareTo(b));
    return keys.map((key) {
      var value = map[key]!;
      if (value is Map<String, dynamic>) {
        return [key, sortKeys(value)];
      }
      return [key, value];
    }).toList();
  }

  static String hash(Map<String, dynamic> map) {
    var sortedMap = sortKeys(map);
    String? jsonStr;
    try {
      jsonStr = jsonEncode(sortedMap);
    } catch (e) {
      print("Exception in MapHasher: $e");
      var keys = map.entries.toList();
      keys.sort((a, b) => a.key.compareTo(b.key));
      jsonStr = keys.map((kv) {
        String value = kv.value.toString();
        try {
          value = jsonEncode(kv.value);
        } catch (e) {}
        return "(${kv.key}:$value)";
      }).join(",");
    }
    var bytes = utf8.encode(jsonStr);
    var digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes);
  }
}
