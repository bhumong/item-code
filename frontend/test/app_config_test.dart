import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/core/config.dart';

void main() {
  group('AppConfig.resolveBackendBaseUrl', () {
    test('uses the current page origin when no override is configured', () {
      final pageUri = Uri.parse('https://app.example.com/search');

      expect(
        AppConfig.resolveBackendBaseUrl('', pageUri),
        'https://app.example.com',
      );
    });

    test('uses the explicit backend URL when configured', () {
      final pageUri = Uri.parse('http://localhost:8080/');

      expect(
        AppConfig.resolveBackendBaseUrl('http://localhost:8090', pageUri),
        'http://localhost:8090',
      );
    });
  });
}
