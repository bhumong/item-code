import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/core/api_client.dart';

void main() {
  test('ApiException exposes statusCode and message', () {
    const e = ApiException(403, 'Your email is not whitelisted');
    expect(e.statusCode, 403);
    expect(e.message, 'Your email is not whitelisted');
    expect(e.toString(), 'Your email is not whitelisted');
  });
}
