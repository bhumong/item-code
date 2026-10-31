/// PocketBase only generates thumbnails for sizes declared on the file field
/// (see `backend/internal/migrations/003_page_thumbs.go`). The `t` suffix
/// crops to the exact viewbox from the top, which matches the `BoxFit.cover`
/// used by the list tiles.
const _galleryThumbSize = '360x360t';
const _searchThumbSize = '100x120t';

String _thumbUrl(String imageUrl, String size) =>
    imageUrl.isEmpty ? '' : '$imageUrl?thumb=$size';

class Document {
  const Document({required this.id, required this.title});

  final String id;
  final String title;

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }
}

class DocumentSummary {
  const DocumentSummary({required this.document, required this.pageCount});

  final Document document;
  final int pageCount;
}

class Page {
  const Page({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.status,
    required this.imageUrl,
    this.ocrText,
  });

  final String id;
  final String documentId;
  final int pageNumber;
  final String status;
  final String imageUrl;
  final String? ocrText;

  /// Cropped server-side thumbnail for the document page gallery.
  String get thumbUrl => _thumbUrl(imageUrl, _galleryThumbSize);

  factory Page.fromJson(
    Map<String, dynamic> json, {
    String baseUrl = 'http://localhost:8090',
  }) {
    final id = json['id'] as String? ?? '';
    final filename = json['image'] as String? ?? '';
    return Page(
      id: id,
      documentId: json['document'] as String? ?? '',
      pageNumber: json['page_number'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      imageUrl: filename.isEmpty ? '' : '$baseUrl/api/files/pages/$id/$filename',
      ocrText: json['ocr_text'] as String?,
    );
  }
}

class SearchResult {
  const SearchResult({
    required this.documentId,
    required this.documentTitle,
    required this.pageId,
    required this.pageNumber,
    required this.snippet,
    this.imageUrl = '',
  });

  final String documentId;
  final String documentTitle;
  final String pageId;
  final int pageNumber;
  final String snippet;
  final String imageUrl;

  /// Cropped server-side thumbnail for the search results list.
  String get thumbUrl => _thumbUrl(imageUrl, _searchThumbSize);

  factory SearchResult.fromJson(
    Map<String, dynamic> json, {
    String baseUrl = 'http://localhost:8090',
  }) {
    final pageId = json['page_id'] as String? ?? '';
    final filename = json['image'] as String? ?? '';
    return SearchResult(
      documentId: json['document_id'] as String? ?? '',
      documentTitle: json['document_title'] as String? ?? '',
      pageId: pageId,
      pageNumber: json['page_number'] as int? ?? 0,
      snippet: json['snippet'] as String? ?? '',
      imageUrl:
          filename.isEmpty ? '' : '$baseUrl/api/files/pages/$pageId/$filename',
    );
  }
}
