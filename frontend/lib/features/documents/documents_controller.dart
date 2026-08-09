import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../auth/auth_controller.dart';

class DocumentsController extends AsyncNotifier<List<DocumentSummary>> {
  @override
  Future<List<DocumentSummary>> build() async {
    final api = ref.read(apiClientProvider);
    final docs = await api.listDocuments();
    final summaries = <DocumentSummary>[];
    for (final doc in docs) {
      final count = await api.countPages(doc.id);
      summaries.add(DocumentSummary(document: doc, pageCount: count));
    }
    return summaries;
  }

  Future<void> createDocument(String title) async {
    await ref.read(apiClientProvider).createDocument(title);
    ref.invalidateSelf();
  }
}

final documentsProvider =
    AsyncNotifierProvider<DocumentsController, List<DocumentSummary>>(
  DocumentsController.new,
);
