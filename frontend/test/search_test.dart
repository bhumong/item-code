import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/locale_provider.dart';
import 'package:ocr_search/core/models.dart';
import 'package:ocr_search/features/auth/auth_controller.dart';

import 'fakes.dart';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

void main() {
  testWidgets('search screen debounces and shows highlighted results',
      (tester) async {
    final fake = FakeApiClient()
      ..userEmail = 'bob@gmail.com'
      ..searchResults = [
        const SearchResult(
          documentId: 'd1',
          documentTitle: 'Manual',
          pageId: 'p1',
          pageNumber: 3,
          snippet: 'the <em>needle</em> valve regulates flow',
          pageImage: 'http://localhost:8090/api/files/pages/p1/page_abc.png',
        ),
      ];
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    // Drive navigation through the explorer search field, then type in the
    // search screen's own field to trigger the debounced fetch.
    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Manual - page 3'), findsOneWidget);
    expect(find.textContaining('valve regulates flow'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    final imageTop = tester.getTopLeft(find.byType(Image)).dy;
    final titleTop = tester.getTopLeft(find.text('Manual - page 3')).dy;
    expect(imageTop, lessThan(titleTop));
    final richText = tester.widget<RichText>(find.byType(RichText).last);
    final hasBold = richText.text.visitChildren((span) {
      return span.style?.fontWeight != FontWeight.bold;
    });
    expect(hasBold, true);
  });

  testWidgets('clearing the query shows empty state without new api calls',
      (tester) async {
    final fake = FakeApiClient()..userEmail = 'bob@gmail.com';
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    // Navigate with a query; the initial fetch runs once.
    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fake.searchCalls, 1);

    // Clear the search field -> debounce -> empty results, no new api call.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('No results. Try different terms.'), findsOneWidget);
    expect(fake.searchCalls, 1);
  });

  testWidgets('search screen uses Indonesian when locale is id', (tester) async {
    final fake = FakeApiClient()..userEmail = 'bob@gmail.com';
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(fake),
        localeProvider.overrideWith(IndonesianLocale.new),
      ],
      child: const OcrSearchApp(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada hasil. Coba kata lain.'), findsOneWidget);
  });
}
