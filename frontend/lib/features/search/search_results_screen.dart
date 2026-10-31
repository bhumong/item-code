import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/widgets/fullscreen_image_viewer.dart';
import 'highlighted_text.dart';
import 'search_controller.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key});

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  final _controller = TextEditingController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final initialQuery =
        GoRouterState.of(context).uri.queryParameters['q'] ?? '';
    _controller.text = initialQuery;
    if (initialQuery.isNotEmpty) {
      // Initial query from the URL bypasses the debounce, but the provider
      // update must happen after the current frame finishes building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(searchQueryProvider.notifier).update(initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search...'),
          onChanged: (value) =>
              ref.read(searchResultsProvider.notifier).updateQuery(value),
        ),
      ),
      body: results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text('Search failed: $error')),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No results. Try different terms.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _ResultTile(result: items[index]),
              ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: _ResultThumbnail(
          result: result,
          onTap: result.imageUrl.isEmpty
              ? null
              : () => showFullscreenImage(
                    context,
                    imageUrl: result.imageUrl,
                    caption:
                        '${result.documentTitle} - page ${result.pageNumber}',
                  ),
        ),
        title: Text('${result.documentTitle} - page ${result.pageNumber}'),
        subtitle: HighlightedText(
          text: result.snippet,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        onTap: () => context.go('/documents/${result.documentId}'),
      ),
    );
  }
}

class _ResultThumbnail extends StatelessWidget {
  const _ResultThumbnail({required this.result, this.onTap});

  final SearchResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (result.imageUrl.isEmpty) {
      return const Icon(Icons.description_outlined, size: 40);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            result.thumbUrl,
            width: 48,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image_outlined, size: 40),
          ),
        ),
      ),
    );
  }
}
