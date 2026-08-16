import 'dart:typed_data';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/models.dart';
import 'package:ocr_search/features/auth/auth_controller.dart';
import 'package:ocr_search/features/pages/upload_controller.dart';

import 'fakes.dart';

class FakeImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'camera.png');
  }
}

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
    expect(find.text('Upload Image'), findsOneWidget);
  });

  testWidgets('uploading pages increments progress and refreshes gallery',
      (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.text('Upload Image')),
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

  testWidgets('detail shows camera upload button', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.text('Upload from Camera'), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
  });

  testWidgets('camera capture uploads a page through the controller',
      (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(fake),
        imagePickerProvider.overrideWithValue(FakeImagePicker()),
      ],
      child: const OcrSearchApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload from Camera'));
    await tester.pumpAndSettle();

    expect(fake.pagesByDocument['d1']!.length, 4);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Manual')),
      listen: false,
    );
    final uploadState = container.read(uploadControllerProvider);
    expect(uploadState.uploading, false);
    expect(uploadState.done, 1);
  });
}
