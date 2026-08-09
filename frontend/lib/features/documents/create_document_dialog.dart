import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'documents_controller.dart';

class CreateDocumentDialog extends ConsumerStatefulWidget {
  const CreateDocumentDialog({super.key});

  @override
  ConsumerState<CreateDocumentDialog> createState() =>
      _CreateDocumentDialogState();
}

class _CreateDocumentDialogState extends ConsumerState<CreateDocumentDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Document'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Title'),
        onSubmitted: (_) => _create(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _create(context),
          child: const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    await ref.read(documentsProvider.notifier).createDocument(title);
    if (context.mounted) Navigator.of(context).pop();
  }
}
