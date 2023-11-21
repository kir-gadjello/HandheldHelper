import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

dynamic parseArray(RandomAccessFile raf) async {
  final arrTypeBuffer = await raf.read(4);
  final arrType = arrTypeBuffer.buffer.asByteData().getUint32(0, Endian.little);

  final numEltsBuffer = await raf.read(8);
  final numElts = numEltsBuffer.buffer.asByteData().getUint64(0, Endian.little);

  final ret = <dynamic>[];
  for (var i = 0; i < numElts; i++) {
    switch (arrType) {
      case 0: // uint8
        final valueBuffer = await raf.read(1);
        ret.add(valueBuffer.buffer.asByteData().getUint8(0));
        break;
      case 1: // int8
        final valueBuffer = await raf.read(1);
        ret.add(valueBuffer.buffer.asByteData().getInt8(0));
        break;
      case 2: // uint16
        final valueBuffer = await raf.read(2);
        ret.add(valueBuffer.buffer.asByteData().getUint16(0, Endian.little));
        break;
      case 3: // int16
        final valueBuffer = await raf.read(2);
        ret.add(valueBuffer.buffer.asByteData().getInt16(0, Endian.little));
        break;
      case 4: // uint32
        final valueBuffer = await raf.read(4);
        ret.add(valueBuffer.buffer.asByteData().getUint32(0, Endian.little));
        break;
      case 5: // int32
        final valueBuffer = await raf.read(4);
        ret.add(valueBuffer.buffer.asByteData().getInt32(0, Endian.little));
        break;
      case 6: // float32
        final valueBuffer = await raf.read(4);
        ret.add(valueBuffer.buffer.asByteData().getFloat32(0, Endian.little));
        break;
      case 7: // bool
        final valueBuffer = await raf.read(1);
        ret.add(valueBuffer.buffer.asByteData().getUint8(0) != 0);
        break;
      case 8: // string
        final stringLengthBuffer = await raf.read(8);
        final stringLength =
            stringLengthBuffer.buffer.asByteData().getUint64(0, Endian.little);
        final stringBuffer = await raf.read(stringLength.toInt());
        ret.add(utf8.decode(stringBuffer.buffer.asUint8List()));
        break;
      case 9: // array
        return await parseArray(raf);
      case 10: // uint64
        final valueBuffer = await raf.read(8);
        ret.add(valueBuffer.buffer.asByteData().getUint64(0, Endian.little));
        break;
      case 11: // int64
        final valueBuffer = await raf.read(8);
        ret.add(valueBuffer.buffer.asByteData().getInt64(0, Endian.little));
        break;
      case 12: // float64
        final valueBuffer = await raf.read(8);
        ret.add(valueBuffer.buffer.asByteData().getFloat64(0, Endian.little));
        break;
      default:
        throw Exception('Unknown value type: $arrType');
    }
  }
  return ret;
}

dynamic parseValue(RandomAccessFile raf, int valueType) async {
  switch (valueType) {
    case 0: // uint8
      final valueBuffer = await raf.read(1);
      return valueBuffer.buffer.asByteData().getUint8(0);
    case 1: // int8
      final valueBuffer = await raf.read(1);
      return valueBuffer.buffer.asByteData().getInt8(0);
    case 2: // uint16
      final valueBuffer = await raf.read(2);
      return valueBuffer.buffer.asByteData().getUint16(0, Endian.little);
    case 3: // int16
      final valueBuffer = await raf.read(2);
      return valueBuffer.buffer.asByteData().getInt16(0, Endian.little);
    case 4: // uint32
      final valueBuffer = await raf.read(4);
      return valueBuffer.buffer.asByteData().getUint32(0, Endian.little);
    case 5: // int32
      final valueBuffer = await raf.read(4);
      return valueBuffer.buffer.asByteData().getInt32(0, Endian.little);
    case 6: // float32
      final valueBuffer = await raf.read(4);
      return valueBuffer.buffer.asByteData().getFloat32(0, Endian.little);
    case 7: // bool
      final valueBuffer = await raf.read(1);
      return valueBuffer.buffer.asByteData().getUint8(0) != 0;
    case 8: // string
      final stringLengthBuffer = await raf.read(8);
      final stringLength =
          stringLengthBuffer.buffer.asByteData().getUint64(0, Endian.little);

      final stringBuffer = await raf.read(stringLength.toInt());
      return utf8.decode(stringBuffer.buffer.asUint8List());
    case 9: // array
      return parseArray(raf);
    case 10: // uint64
      final valueBuffer = await raf.read(8);
      return valueBuffer.buffer.asByteData().getUint64(0, Endian.little);
    case 11: // int64
      final valueBuffer = await raf.read(8);
      return valueBuffer.buffer.asByteData().getInt64(0, Endian.little);
    case 12: // float64
      final valueBuffer = await raf.read(8);
      return valueBuffer.buffer.asByteData().getFloat64(0, Endian.little);
    default:
      throw Exception('Unknown value type: $valueType');
  }
}

Future<Map<String, dynamic>?> parseGGUF(String path,
    {Set<String>? findKeys}) async {
  final _keys = findKeys != null ? Set.from(findKeys) : null;
  final file = File(path);

  RandomAccessFile raf = await file.open();

  final magicNumberBuffer = await raf.read(4);
  final magicNumber =
      magicNumberBuffer.buffer.asByteData().getUint32(0, Endian.big);
  if (magicNumber != 0x47475546) {
    raf.close();
    return null;
  }

  final versionBuffer = await raf.read(4);
  final version = versionBuffer.buffer.asByteData().getUint32(0, Endian.little);
  if (version != 3) {
    raf.close();
    return null;
  }

  final tensorCountBuffer = await raf.read(8);
  final tensorCount =
      tensorCountBuffer.buffer.asByteData().getUint64(0, Endian.little);

  final metadataKvCountBuffer = await raf.read(8);
  final metadataKvCount =
      metadataKvCountBuffer.buffer.asByteData().getUint64(0, Endian.little);

  final metadata = <String, dynamic>{};
  for (var i = 0; i < metadataKvCount; i++) {
    final keyLengthBuffer = await raf.read(8);
    final keyLength =
        keyLengthBuffer.buffer.asByteData().getUint64(0, Endian.little);

    final keyBuffer = await raf.read(keyLength.toInt());
    final key = utf8.decode(keyBuffer.buffer.asUint8List());

    final valueTypeBuffer = await raf.read(4);
    final valueType =
        valueTypeBuffer.buffer.asByteData().getUint32(0, Endian.little);

    metadata[key] = await parseValue(raf, valueType);

    if (_keys != null) {
      _keys.remove(key);
      if (_keys.isEmpty) {
        raf.close();
        return metadata;
      }
    }
  }

  raf.close();
  return metadata;
}
