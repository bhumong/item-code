import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows [imageUrl] across the whole viewport with a close button at the
/// bottom. This is an in-app viewer, not the browser's full-screen mode.
/// Tapping the dark area around the image or pressing Escape dismisses it.
Future<void> showFullscreenImage(
  BuildContext context, {
  required String imageUrl,
  String? caption,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => FullscreenImageView(imageUrl: imageUrl, caption: caption),
  );
}

class FullscreenImageView extends StatelessWidget {
  const FullscreenImageView({super.key, required this.imageUrl, this.caption});

  final String imageUrl;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();

    return Dialog(
      insetPadding: EdgeInsets.zero,
      // Square corners: the default rounded shape would let the underlying
      // page show through now that the dialog fills the whole viewport.
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      backgroundColor: Colors.black,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): close,
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Column(
              children: [
                if (caption != null && caption!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      caption!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                Expanded(
                  child: GestureDetector(
                    // Tap anywhere in the letterboxed area to dismiss. The
                    // modal barrier never sees the tap because the dialog
                    // covers the whole viewport.
                    behavior: HitTestBehavior.opaque,
                    onTap: close,
                    child: Center(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const CircularProgressIndicator(
                                color: Colors.white),
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.broken_image_outlined,
                                size: 64, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FilledButton.icon(
                    onPressed: close,
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
