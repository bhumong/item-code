import 'dart:typed_data';

import 'package:ocr_search/core/api_client.dart';
import 'package:ocr_search/core/models.dart';

class FakeApiClient implements ApiClient {
  String? userEmail;
  int loginErrorCode = 0;
  String loginErrorMessage = 'Your email is not whitelisted';
  final documents = <Document>[];
  final pagesByDocument = <String, List<Page>>{};
  List<SearchResult> searchResults = [];
  int searchCalls = 0;
  int createDocumentCalls = 0;

  /// Filename the stubbed search response reports for each result's page.
  /// Empty keeps whatever imageUrl the result was constructed with.
  String searchImage = '';

  @override
  Future<String?> currentUserEmail() async => userEmail;

  @override
  Future<void> loginWithGoogle() async {
    if (loginErrorCode != 0) {
      throw ApiException(loginErrorCode, loginErrorMessage);
    }
    userEmail = 'bob@gmail.com';
  }

  @override
  Future<void> logout() async {
    userEmail = null;
  }

  @override
  Future<List<Document>> listDocuments() async => List.of(documents);

  @override
  Future<Document> createDocument(String title) async {
    createDocumentCalls++;
    final doc = Document(id: 'd$createDocumentCalls', title: title);
    documents.add(doc);
    return doc;
  }

  @override
  Future<Document> updateDocumentTitle(String id, String title) async {
    final index = documents.indexWhere((d) => d.id == id);
    final updated = Document(id: id, title: title);
    if (index >= 0) documents[index] = updated;
    return updated;
  }

  @override
  Future<int> countPages(String documentId) async {
    return pagesByDocument[documentId]?.length ?? 0;
  }

  @override
  Future<List<Page>> listPages(String documentId) async {
    return List.of(pagesByDocument[documentId] ?? const []);
  }

  @override
  Future<void> uploadPage(
    String documentId,
    int pageNumber,
    Uint8List bytes,
    String filename,
  ) async {
    final page = Page(
      id: 'p$pageNumber',
      documentId: documentId,
      pageNumber: pageNumber,
      status: 'pending',
      imageUrl: '',
    );
    pagesByDocument.putIfAbsent(documentId, () => []).add(page);
  }

  @override
  Future<List<SearchResult>> search(String query) async {
    searchCalls++;
    if (searchImage.isEmpty) return List.of(searchResults);
    return searchResults
        .map((r) => SearchResult(
              documentId: r.documentId,
              documentTitle: r.documentTitle,
              pageId: r.pageId,
              pageNumber: r.pageNumber,
              snippet: r.snippet,
              imageUrl: 'http://localhost:8090/api/files/pages/'
                  '${r.pageId}/$searchImage',
            ))
        .toList();
  }
}
