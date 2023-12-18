import 'dart:convert';
import 'dart:io';
import '../lib/llm_engine.dart';
import 'package:test/test.dart';

void main() {
  test('trimLastCharacter', () {
    expect(trim_suffix("", ""), "");
    expect(trim_suffix("a", "a"), "");
    expect(trim_suffix("aa", "a"), "");
    expect(trim_suffix("ba", "a"), "b");
    expect(trim_suffix("ab", "a"), "ab");
    expect(trim_suffix("<|im_end|>", "<|im_end|>"), "");
    expect(trim_suffix("<|im_end|>a", "<|im_end|>"), "<|im_end|>a");
    expect(trim_suffix("<|im_start|><|im_end|>", "<|im_end|>"), "<|im_start|>");
  });

  test('ChatML format fix', () {
    expect(fix_chatml_markup(""), "");
    expect(fix_chatml_markup("<|im-end|>"), "<|im-end|>");
    expect(fix_chatml_markup("<|im_end|>"), "");
    expect(fix_chatml_markup("<|im_start|>"), "");
    expect(fix_chatml_markup("<|im_start|><|im_end|>"), "");
    expect(fix_chatml_markup("lorem ipsum <|im_end|>dolorem"), "lorem ipsum ");
    expect(fix_chatml_markup("lorem ipsum"), "lorem ipsum");
  });

  group('Templated prompt formats', () {
    Map<String, dynamic> fmts =
        jsonDecode(File("assets/known_prompt_formats.json").readAsStringSync());

    var msgs = [
      AIChatMessage("system", "sys_msg"),
      AIChatMessage("user", "user_msg"),
    ];

    test('vicuna', () {
      var loaded = LLMPromptFormat.fromTemplate(fmts["vicuna"], "vicuna");
      print("SEPARATOR: \"${loaded.separator}");
      print(
          "FORMATTED EXAMPLE:\n-----------\n${loaded.formatter(msgs)}\n-----------");
      expect(loaded.formatter(msgs), '''sys_msg

USER: user_msg
ASSISTANT:''');
    });
  });
}
