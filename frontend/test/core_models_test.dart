import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/core/models.dart';

void main() {
  group('Document', () {
    test('parses from record json', () {
      final doc = Document.fromJson({
        'id': 'd1',
        'title': 'Manual',
        'created': '2026-01-01 00:00:00.000Z',
      });
      expect(doc.id, 'd1');
      expect(doc.title, 'Manual');
    });
  });

  group('SearchResult', () {
    test('parses snake_case fields from /api/search', () {
      final r = SearchResult.fromJson({
        'document_id': 'd1',
        'document_title': 'Manual',
        'page_id': 'p1',
        'page_number': 3,
        'snippet': 'the <em>needle</em> valve',
      });
      expect(r.documentId, 'd1');
      expect(r.documentTitle, 'Manual');
      expect(r.pageId, 'p1');
      expect(r.pageNumber, 3);
      expect(r.snippet, 'the <em>needle</em> valve');
    });

    test('defaults missing fields', () {
      final r = SearchResult.fromJson({});
      expect(r.documentId, '');
      expect(r.pageNumber, 0);
      expect(r.snippet, '');
    });
  });

  group('Page', () {
    test('parses from record json with image url', () {
      final p = Page.fromJson({
        'id': 'p1',
        'document': 'd1',
        'page_number': 2,
        'status': 'completed',
        'image': 'page_abc.png',
        'ocr_text': 'hello',
      });
      expect(p.pageNumber, 2);
      expect(p.status, 'completed');
      expect(p.imageUrl, 'http://localhost:8090/api/files/pages/p1/page_abc.png');
    });
  });
}
