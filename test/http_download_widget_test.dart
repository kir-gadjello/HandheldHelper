import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
// import 'package:mockito/mockito.dart';
import '../lib/main.dart' show HttpDownloadWidget;

class MockClient extends http.BaseClient {
  int statusCode = 200;
  String fileContent = 'Hello, World!';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    print("REQUEST: ${request.method} ${request.url}");
    if (request.url.path.endsWith('file.bin')) {
      return http.StreamedResponse(
        Stream.fromIterable(
          [utf8.encode(fileContent)],
        ),
        statusCode,
      );
    } else {
      return http.StreamedResponse(
        Stream.fromIterable(
          [utf8.encode('Not Found')],
        ),
        404,
      );
    }
  }
}

void main() {
  group('HttpDownloadWidget', () {
    testWidgets('should download a file', (WidgetTester tester) async {
      const fname = '12432432809238434.bin';
      final url = 'https://example.com/file.bin';
      final destinationPath = '/tmp/$fname';

      try {
        File('/tmp/$fname').deleteSync();
      } catch (e) {}

      await tester.pumpWidget(MaterialApp(
          home: HttpDownloadWidget(
              url: url,
              destinationPath: destinationPath,
              client: MockClient())));

      expect(find.text(url), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.error), findsNothing);

      // await tester.tap(find.byType(HttpDownloadWidget));
      await tester.pumpAndSettle(const Duration(seconds: 15));

      expect(find.text('File size:'), findsOneWidget);
      expect(find.text('Time taken:'), findsOneWidget);
      expect(find.text('Speed:'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });
}
