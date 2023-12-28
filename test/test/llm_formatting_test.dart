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

  var msgs = [
    AIChatMessage("system", "sys_msg"),
    AIChatMessage("user", "user_msg"),
  ];

  group('Templated prompt formats', () {
    Map<String, dynamic> fmts =
        jsonDecode(File("assets/known_prompt_formats.json").readAsStringSync());

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

  group('Jinja prompt formats', () {
    test('openchat', () {
      const fmt_openchat =
          "{{ bos_token }}{% for message in messages %}{{ 'GPT4 Correct ' + message['role'].title() + ': ' + message['content'] + '<|end_of_turn|>'}}{% endfor %}{% if add_generation_prompt %}{{ 'GPT4 Correct Assistant:' }}{% endif %}";

      const fmt_chatml =
          '''{% for message in messages %}{{'<|im_start|>' + message['role'].title() + '\n' + message['content'] + '<|im_end|>' + '\n'}}
{% endfor %}''';

      const fmt_broken =
          '''{% for message in messages %}{{'<|im_start|>' + message['role'].title() + '\n'  + '<|im_end|>' + '\n'}}
{% endfor %}''';

      expect(validate_jinja_chat_template(fmt_openchat), true);
      expect(validate_jinja_chat_template(fmt_chatml), true);
      expect(validate_jinja_chat_template(fmt_broken), false);

      var out = format_chat_jinja(fmt_openchat, msgs);

      print("FORMATTED:\n$out");

      expect(out,
          "GPT4 Correct System: sys_msg<|end_of_turn|>GPT4 Correct User: user_msg<|end_of_turn|>GPT4 Correct Assistant:");

      var sep = extractSeparatorFromJinjaTemplate(fmt_openchat);

      expect(sep, "<|end_of_turn|>");
    });
  });
}
