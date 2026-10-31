import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/models.dart';
import 'package:ocr_search/features/auth/auth_controller.dart';
import 'package:ocr_search/features/search/search_results_screen.dart';

import 'fakes.dart';

const _kFileUrlBase = 'http://localhost:8090/api/files/pages';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

/// A fake seeded with one image-bearing search result and already on the
/// search screen with the query submitted.
Future<FakeApiClient> pumpSearchResults(WidgetTester tester) async {
  final fake = FakeApiClient()
    ..userEmail = 'bob@gmail.com'
    ..searchImage = 'page_abc.png'
    ..searchResults = [
      const SearchResult(
        documentId: 'd1',
        documentTitle: 'Manual',
        pageId: 'p1',
        pageNumber: 3,
        snippet: 'the <em>needle</em> valve',
      ),
    ];
  await tester.pumpWidget(testApp(fake));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, 'needle');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  // Network images never load under flutter_test's stubbed HTTP client, so
  // tests assert on the Image widget's provider instead of on decoded pixels.
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

  testWidgets('result thumbnail uses a server-side cropped thumb',
      (tester) async {
    await pumpSearchResults(tester);

    final thumbnail = find.descendant(
      of: find.byType(SearchResultsScreen),
      matching: find.byType(Image),
    );
    expect(thumbnail, findsOneWidget);
    final image = tester.widget<Image>(thumbnail);
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url,
        '$_kFileUrlBase/p1/page_abc.png?thumb=100x120t');
  });

  testWidgets('result thumbnail opens a fullscreen viewer with close button',
      (tester) async {
    await pumpSearchResults(tester);

    final thumbnail = find.descendant(
      of: find.byType(SearchResultsScreen),
      matching: find.byType(Image),
    );

    await tester.tap(thumbnail);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Manual - page 3'), findsNWidgets(2));

    // The viewer loads the full-resolution page, not the cropped thumbnail.
    final viewer = tester.widget<Image>(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Image)),
    );
    expect(viewer.image, isA<NetworkImage>());
    expect((viewer.image as NetworkImage).url,
        '$_kFileUrlBase/p1/page_abc.png');
    expect(viewer.fit, BoxFit.contain);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('viewer dismisses on backdrop tap and Escape', (tester) async {
    await pumpSearchResults(tester);

    final thumbnail = find.descendant(
      of: find.byType(SearchResultsScreen),
      matching: find.byType(Image),
    );

    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    // The dialog fills the viewport, so a tap in the letterboxed area beside
    // the image is handled by the viewer itself.
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}

