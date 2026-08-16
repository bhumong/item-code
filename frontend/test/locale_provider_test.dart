import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/core/locale_provider.dart';

void main() {
  test('defaults to en when the platform locale is not id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('toggle flips between en and id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(localeProvider.notifier).toggle();
    expect(container.read(localeProvider), const Locale('id'));
    container.read(localeProvider.notifier).toggle();
    expect(container.read(localeProvider), const Locale('en'));
  });
}
