import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart' show HttpDownloadWidget;

void main() {
  group('HttpDownloadWidget', () {
    testWidgets('should download a file', (WidgetTester tester) async {
      final url = 'https://example.com/index.html';
      final destinationPath = '.';

      await tester.pumpWidget(MaterialApp(
          home:
              HttpDownloadWidget(url: url, destinationPath: destinationPath)));

      expect(find.text(url), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.error), findsNothing);

      await tester.tap(find.byType(HttpDownloadWidget));
      await tester.pumpAndSettle();

      expect(find.text('File size:'), findsOneWidget);
      expect(find.text('Time taken:'), findsOneWidget);
      expect(find.text('Speed:'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });
}
