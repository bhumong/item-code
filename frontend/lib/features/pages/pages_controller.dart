import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../auth/auth_controller.dart';

final pagesProvider = FutureProvider.family<List<Page>, String>(
  (ref, documentId) => ref.read(apiClientProvider).listPages(documentId),
);
