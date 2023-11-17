import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import '../lib/gguf.dart';

String getPrettyJSONString(Map<String, dynamic> map) {
  var encoder = JsonEncoder.withIndent(' ');
  return encoder.convert(map);
}

dynamic replaceArraysWithPlaceholder(dynamic value) {
  if (value is List) {
    return 'array of length ${value.length}';
  }
  return value;
}

void main(List<String> arguments) async {
  if (arguments.length < 1) {
    print('Usage: <program> <path_to_file> [<key> ...]');
    return;
  }

  String path = arguments[0];
  Set<String>? keys;
  if (arguments.length > 1) {
    keys = Set.from(arguments.skip(1));
  }

  Map<String, dynamic>? metadata = await parseGGUF(path, findKeys: keys);
  if (metadata == null) {
    print('Failed to parse metadata');
    return;
  }

  // Replace all array values with placeholders
  metadata = metadata
      .map((key, value) => MapEntry(key, replaceArraysWithPlaceholder(value)));

  String jsonString = getPrettyJSONString(metadata);
  print(jsonString);
}
