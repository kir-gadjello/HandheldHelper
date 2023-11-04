import '../lib/conv.dart';
import 'package:test/test.dart';

void main() {
  test('trimLastCharacter', () {
    expect(trimLastCharacter("", ""), "");
    expect(trimLastCharacter("a", "a"), "");
    expect(trimLastCharacter("aa", "a"), "");
    expect(trimLastCharacter("ba", "a"), "b");
    expect(trimLastCharacter("ab", "a"), "ab");
    expect(trimLastCharacter("<|im_end|>", "<|im_end|>"), "");
    expect(trimLastCharacter("<|im_end|>a", "<|im_end|>"), "<|im_end|>a");
    expect(trimLastCharacter("<|im_start|><|im_end|>", "<|im_end|>"), "<|im_start|>");
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
}