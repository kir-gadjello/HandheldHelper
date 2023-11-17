import 'dart:io';
import 'package:test/test.dart';
import '../lib/gguf.dart';

void checkKeyValueMappings(
    Map<dynamic, dynamic> dynamicMap, Map<dynamic, dynamic> expectedMappings) {
  // Iterate over the expected mappings
  expectedMappings.forEach((key, value) {
    expect(dynamicMap.containsKey(key), isTrue);
    // Check if the dynamic map contains the key
    if (dynamicMap.containsKey(key)) {
      // If it does, check if the value matches the expected value
      expect(dynamicMap[key], value);
    }
  });
}

void main() {
  test('parseGGUF correctly parses a GGUF file', () async {
    final filePath =
        Platform.environment["TESTGGUF"] ?? "test/hermes2.5.header.gguf";

    final short_metadata_parsed = await parseGGUF(filePath, findKeys: {
      "general.architecture",
      "general.name",
      "llama.context_length"
    });

    final shortMetadata = {
      "general.architecture": "llama",
      "general.name": "teknium_openhermes-2.5-mistral-7b",
      "llama.context_length": 32768,
    };

    checkKeyValueMappings(
        short_metadata_parsed as Map<String, dynamic>, shortMetadata);

    final full_metadata_parsed = await parseGGUF(filePath);

    // Replace with the expected metadata
    final expectedMetadata = {
      "general.architecture": "llama",
      "general.name": "teknium_openhermes-2.5-mistral-7b",
      "llama.context_length": 32768,
      "llama.embedding_length": 4096,
      "llama.block_count": 32,
      "llama.feed_forward_length": 14336,
      "llama.rope.dimension_count": 128,
      "llama.attention.head_count": 32,
      "llama.attention.head_count_kv": 8,
      "llama.attention.layer_norm_rms_epsilon": 0.000009999999747378752,
      "llama.rope.freq_base": 10000.0,
      "general.file_type": 15,
      "tokenizer.ggml.model": "llama",
      "tokenizer.ggml.bos_token_id": 1,
      "tokenizer.ggml.eos_token_id": 32000,
      "tokenizer.ggml.padding_token_id": 0,
      "general.quantization_version": 2
    };

    // expect((metadata as Map<String, dynamic>).entries,
    //     containsAll(expectedMetadata.entries));

    checkKeyValueMappings(
        full_metadata_parsed as Map<String, dynamic>, expectedMetadata);
  });
}
