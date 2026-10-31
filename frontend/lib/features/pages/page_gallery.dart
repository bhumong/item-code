import 'package:flutter/material.dart' hide Page;

import '../../core/models.dart';
import '../../core/widgets/fullscreen_image_viewer.dart';
import 'status_tag.dart';

class PageGallery extends StatelessWidget {
  const PageGallery({super.key, required this.pages, this.documentTitle});

  final List<Page> pages;

  /// Shown in the fullscreen viewer caption, for example "Manual - page 3".
  final String? documentTitle;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const Center(child: Text('No pages yet. Use Add Pages to upload.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 200,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        final hasImage = page.imageUrl.isNotEmpty;
        final caption = documentTitle == null
            ? 'Page ${page.pageNumber}'
            : '$documentTitle - page ${page.pageNumber}';
        return MouseRegion(
          cursor: hasImage ? SystemMouseCursors.click : MouseCursor.defer,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: hasImage
                  ? () => showFullscreenImage(
                        context,
                        imageUrl: page.imageUrl,
                        caption: caption,
                      )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: hasImage
                        ? Image.network(
                            page.thumbUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.broken_image_outlined,
                              size: 40,
                            ),
                          )
                        : const ColoredBox(
                            color: Color(0xFFE0E0E0),
                            child: Icon(Icons.image_outlined, size: 40),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${page.pageNumber}'),
                        StatusTag(status: page.status),
                      ],
                    ),
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
