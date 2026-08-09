import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../auth/auth_controller.dart';

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String value) => state = value;
}

final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

class SearchResultsController extends AsyncNotifier<List<SearchResult>> {
  Timer? _debounce;

  @override
  Future<List<SearchResult>> build() async {
    ref.onDispose(() => _debounce?.cancel());
    final query = ref.watch(searchQueryProvider);
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return ref.read(apiClientProvider).search(trimmed);
  }

  void updateQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).update(value);
    });
  }

}

final searchResultsProvider =
    AsyncNotifierProvider<SearchResultsController, List<SearchResult>>(
  SearchResultsController.new,
);
