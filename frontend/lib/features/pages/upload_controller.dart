import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'pages_controller.dart';

class UploadInput {
  const UploadInput({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

class UploadState {
  const UploadState({
    this.uploading = false,
    this.done = 0,
    this.total = 0,
    this.error,
  });

  final bool uploading;
  final int done;
  final int total;
  final String? error;

  UploadState copyWith({
    bool? uploading,
    int? done,
    int? total,
    String? error,
  }) {
    return UploadState(
      uploading: uploading ?? this.uploading,
      done: done ?? this.done,
      total: total ?? this.total,
      error: error,
    );
  }
}

class UploadController extends Notifier<UploadState> {
  @override
  UploadState build() => const UploadState();

  Future<void> addPages(String documentId, List<UploadInput> files) async {
    if (files.isEmpty) return;
    final api = ref.read(apiClientProvider);
    final base = ref.read(pagesProvider(documentId)).value?.length ?? 0;

    state = UploadState(uploading: true, done: 0, total: files.length);
    String? lastError;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        await api.uploadPage(documentId, base + i + 1, file.bytes, file.name);
      } catch (_) {
        lastError = 'Failed to upload ${file.name}';
      }
      state = state.copyWith(done: i + 1, error: lastError);
    }
    state = state.copyWith(uploading: false);
    ref.invalidate(pagesProvider(documentId));
  }
}

final uploadControllerProvider =
    NotifierProvider<UploadController, UploadState>(UploadController.new);
