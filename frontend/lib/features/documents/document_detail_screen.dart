import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      builder: (context) => AlertDialog(
        title: const Text('Rename Document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
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
    final title = documents
            .where((s) => s.document.id == widget.documentId)
            .firstOrNull
            ?.document
            .title ??
        'Document';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(onPressed: () => context.go('/')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit title',
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
                  label: const Text('Add Pages'),
                ),
                const SizedBox(width: 16),
                if (upload.uploading)
                  Text('Uploading ${upload.done}/${upload.total}...'),
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
                  Center(child: Text('Failed to load pages: $error')),
              data: (items) => PageGallery(pages: items),
            ),
          ),
        ],
      ),
    );
  }
}
