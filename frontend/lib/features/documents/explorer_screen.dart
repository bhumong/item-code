import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ocr_search/l10n/app_localizations.dart';

import '../../core/locale_provider.dart';
import '../../core/models.dart';
import 'create_document_dialog.dart';
import 'documents_controller.dart';

class ExplorerScreen extends ConsumerWidget {
  const ExplorerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          TextButton(
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            child: Text(
              ref.watch(localeProvider).languageCode == 'en' ? 'ID' : 'EN',
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchDocumentsHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (value) {
                final q = value.trim();
                if (q.isEmpty) return;
                context.go('/search?q=$q');
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.newDocument,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const CreateDocumentDialog(),
        ),
        child: const Icon(Icons.add),
      ),
      body: docs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(l10n.failedToLoadDocuments('$error'))),
        data: (summaries) => summaries.isEmpty
            ? Center(child: Text(l10n.noDocumentsYet))
            : _DocumentGrid(summaries: summaries),
      ),
    );
  }
}

class _DocumentGrid extends StatelessWidget {
  const _DocumentGrid({required this.summaries});

  final List<DocumentSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 150,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go('/documents/${summary.document.id}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.description_outlined, size: 40),
                  const Spacer(),
                  Text(
                    summary.document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    l10n.pageCount(summary.pageCount),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
