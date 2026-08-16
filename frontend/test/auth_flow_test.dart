import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/locale_provider.dart';
import 'package:ocr_search/features/auth/auth_controller.dart';

import 'fakes.dart';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

void main() {
  testWidgets('shows login screen when unauthenticated', (tester) async {
    await tester.pumpWidget(testApp(FakeApiClient()));
    await tester.pumpAndSettle();

    expect(find.text('OCR Search'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('shows whitelist toast when Google sign-in returns 403',
      (tester) async {
    final fake = FakeApiClient()..loginErrorCode = 403;
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(find.text('Your email is not whitelisted'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('navigates to explorer after successful login', (tester) async {
    final fake = FakeApiClient();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('login screen uses Indonesian when locale is id', (tester) async {
    final fake = FakeApiClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(fake),
        localeProvider.overrideWith(IndonesianLocale.new),
      ],
      child: const OcrSearchApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Masuk dengan Google'), findsOneWidget);
  });
}
