import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ocr_search/l10n/app_localizations.dart';

import '../auth/auth_controller.dart';
import '../pages/page_gallery.dart';
import '../pages/pages_controller.dart';
import '../pages/upload_controller.dart';
import 'documents_controller.dart';

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  Future<void> _pickAndUpload() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final inputs = result.files
        .where((f) => f.bytes != null)
        .map((f) => UploadInput(bytes: f.bytes!, name: f.name))
        .toList();
    await ref
        .read(uploadControllerProvider.notifier)
        .addPages(widget.documentId, inputs);
  }

  Future<void> _rename() async {
    final documents = ref.read(documentsProvider).value ?? const [];
    final current = documents
        .where((s) => s.document.id == widget.documentId)
        .firstOrNull;
    final controller = TextEditingController(text: current?.document.title ?? '');
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.renameDocument),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.titleLabel),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    final title = newTitle?.trim();
    if (title == null || title.isEmpty) return;
    await ref
        .read(apiClientProvider)
        .updateDocumentTitle(widget.documentId, title);
    ref.invalidate(documentsProvider);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(pagesProvider(widget.documentId));
    final upload = ref.watch(uploadControllerProvider);
    final documents = ref.watch(documentsProvider).value ?? const [];
    final l10n = AppLocalizations.of(context)!;
    final title = documents
            .where((s) => s.document.id == widget.documentId)
            .firstOrNull
            ?.document
            .title ??
        l10n.documentTitle;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(onPressed: () => context.go('/')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: l10n.editTitle,
            onPressed: _rename,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: upload.uploading ? null : _pickAndUpload,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(l10n.uploadImage),
                ),
                const SizedBox(width: 16),
                if (upload.uploading)
                  Text(l10n.uploadingProgress(upload.done, upload.total)),
              ],
            ),
          ),
          if (upload.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                upload.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: pages.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  Center(child: Text(l10n.failedToLoadPages('$error'))),
              data: (items) => PageGallery(pages: items),
            ),
          ),
        ],
      ),
    );
  }
}
