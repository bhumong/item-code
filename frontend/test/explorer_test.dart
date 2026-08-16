import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/models.dart';
import 'package:ocr_search/features/auth/auth_controller.dart';

import 'fakes.dart';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

FakeApiClient seededFake() {
  final fake = FakeApiClient()..userEmail = 'bob@gmail.com';
  fake.documents.addAll([
    const Document(id: 'd1', title: 'Manual'),
    const Document(id: 'd2', title: 'Receipts'),
  ]);
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
      status: 'pending',
      imageUrl: '',
    ),
  ];
  return fake;
}

void main() {
  testWidgets('lists documents with page counts', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();

    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('2 pages'), findsOneWidget);
    expect(find.text('0 pages'), findsOneWidget);
  });

  testWidgets('create dialog adds a document and refreshes', (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New Document'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Tax 2025',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(fake.createDocumentCalls, 1);
    expect(find.text('Tax 2025'), findsOneWidget);
  });

  testWidgets('search field navigates to /search', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Search...'), findsOneWidget);
  });

  testWidgets('locale toggle flips explorer labels to Indonesian',
      (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ID'));
    await tester.pumpAndSettle();

    expect(find.text('Cari dokumen...'), findsOneWidget);
  });
}
