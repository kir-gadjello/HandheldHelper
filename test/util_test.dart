import '../lib/util.dart';
import 'package:test/test.dart';

void main() {
  test('Test HashGenerator.computeHash with simple map', () {
    var map = {'key': 'value', 'anotherKey': 'anotherValue'};
    var expectedHash = 'G4nojMarDeS1VtVUJ658BywxFuozPRa5n1kPceRomZY=';
    expect(MapHasher.hash(map), equals(expectedHash));

    var map2 = {'anotherKey': 'anotherValue', 'key': 'value'};
    expect(MapHasher.hash(map2), equals(expectedHash));
  });

  test('Test HashGenerator.computeHash with nested map', () {
    var map = {
      'key': 'value',
      'nestedMap': {'innerKey': 'innerValue'}
    };
    var expectedHash = 'WBcTbOCFk_O09gT5KJI9m-OYck-bQCFMx7W5fAeAUTE=';
    expect(MapHasher.hash(map), equals(expectedHash));

    var map2 = {
      'key': 'value',
      'nestedMap': {'innerKey': 'innerValue1'}
    };
    expect(MapHasher.hash(map2), isNot(equals(expectedHash)));
  });
}
