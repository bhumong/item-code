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
  });

  final String documentId;
  final String documentTitle;
  final String pageId;
  final int pageNumber;
  final String snippet;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      documentId: json['document_id'] as String? ?? '',
      documentTitle: json['document_title'] as String? ?? '',
      pageId: json['page_id'] as String? ?? '',
      pageNumber: json['page_number'] as int? ?? 0,
      snippet: json['snippet'] as String? ?? '',
    );
  }
}
