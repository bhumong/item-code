import 'package:flutter/material.dart';

/// Renders text containing `<em>...</em>` markers with the matches bold.
class HighlightedText extends StatelessWidget {
  const HighlightedText({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final parts = text.split('<em>');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      final closeIndex = part.indexOf('</em>');
      if (i > 0 && closeIndex >= 0) {
        spans.add(
          TextSpan(
            text: part.substring(0, closeIndex),
            style: style?.copyWith(fontWeight: FontWeight.bold),
          ),
        );
        final rest = part.substring(closeIndex + '</em>'.length);
        if (rest.isNotEmpty) {
          spans.add(TextSpan(text: rest, style: style));
        }
      } else {
        spans.add(TextSpan(text: part, style: style));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
