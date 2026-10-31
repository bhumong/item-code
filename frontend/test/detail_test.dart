import 'package:flutter/material.dart' hide Page;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/models.dart';
import 'package:ocr_search/features/auth/auth_controller.dart';
import 'package:ocr_search/features/pages/page_gallery.dart';
import 'package:ocr_search/features/pages/upload_controller.dart';

import 'fakes.dart';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

FakeApiClient seededFake() {
  final fake = FakeApiClient()..userEmail = 'bob@gmail.com';
  fake.documents.add(const Document(id: 'd1', title: 'Manual'));
  fake.pagesByDocument['d1'] = [
    Page(
      id: 'p1',
      documentId: 'd1',
      pageNumber: 1,
      status: 'completed',
      imageUrl: '',
    ),
    Page(
      id: 'p2',
      documentId: 'd1',
      pageNumber: 2,
      status: 'processing',
      imageUrl: '',
    ),
    Page(
      id: 'p3',
      documentId: 'd1',
      pageNumber: 3,
      status: 'failed',
      imageUrl: '',
    ),
  ];
  return fake;
}

void main() {
  testWidgets('detail shows pages with status tags', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Add Pages'), findsOneWidget);
  });

  testWidgets('gallery thumbnails open a fullscreen viewer', (tester) async {
    final fake = seededFake();
    fake.pagesByDocument['d1']![0] = Page(
      id: 'p1',
      documentId: 'd1',
      pageNumber: 1,
      status: 'completed',
      imageUrl: 'http://localhost:8090/api/files/pages/p1/page_abc.png',
    );
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    // Gallery tiles request the cropped server-side thumbnail.
    final tile = find.descendant(
      of: find.byType(PageGallery),
      matching: find.byType(Image),
    );
    expect(tile, findsOneWidget);
    final tileImage = tester.widget<Image>(tile);
    expect((tileImage.image as NetworkImage).url,
        'http://localhost:8090/api/files/pages/p1/page_abc.png?thumb=360x360t');

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Manual - page 1'), findsOneWidget);
    final viewer = tester.widget<Image>(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Image)),
    );
    expect((viewer.image as NetworkImage).url,
        'http://localhost:8090/api/files/pages/p1/page_abc.png');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('pages without an image stay non-interactive', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    // seededFake pages all have an empty imageUrl, so no tile opens a viewer.
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('uploading pages increments progress and refreshes gallery',
      (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.text('Add Pages')),
      listen: false,
    );
    await container.read(uploadControllerProvider.notifier).addPages('d1', [
      UploadInput(bytes: Uint8List.fromList([1]), name: 'a.png'),
      UploadInput(bytes: Uint8List.fromList([2]), name: 'b.png'),
    ]);
    await tester.pumpAndSettle();

    expect(fake.pagesByDocument['d1']!.length, 5);
    final uploadState = container.read(uploadControllerProvider);
    expect(uploadState.uploading, false);
    expect(uploadState.done, 2);
  });

  testWidgets('edit action renames the document', (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Renamed Manual',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.documents.first.title, 'Renamed Manual');
  });
}
