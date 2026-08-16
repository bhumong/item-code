import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocr_search/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.newDocument),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.titleLabel),
        onSubmitted: (_) => _create(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => _create(context),
          child: Text(l10n.create),
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
