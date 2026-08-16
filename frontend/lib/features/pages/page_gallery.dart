import 'package:flutter/material.dart' hide Page;
import 'package:ocr_search/l10n/app_localizations.dart';

import '../../core/models.dart';
import 'status_tag.dart';

class PageGallery extends StatelessWidget {
  const PageGallery({super.key, required this.pages});

  final List<Page> pages;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)!.noPagesYet),
      );
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
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: page.imageUrl.isEmpty
                    ? const ColoredBox(
                        color: Color(0xFFE0E0E0),
                        child: Icon(Icons.image_outlined, size: 40),
                      )
                    : Image.network(
                        page.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.broken_image_outlined, size: 40),
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
        );
      },
    );
  }
}
