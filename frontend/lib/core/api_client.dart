import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

abstract class ApiClient {
  Future<String?> currentUserEmail();
  Future<void> loginWithGoogle();
  Future<void> logout();
  Future<List<Document>> listDocuments();
  Future<Document> createDocument(String title);
  Future<Document> updateDocumentTitle(String id, String title);
  Future<int> countPages(String documentId);
  Future<List<Page>> listPages(String documentId);
  Future<void> uploadPage(
    String documentId,
    int pageNumber,
    Uint8List bytes,
    String filename,
  );
  Future<List<SearchResult>> search(String query);
}

class PocketBaseApiClient implements ApiClient {
  PocketBaseApiClient(this._pb);

  final PocketBase _pb;

  static PocketBase createClient(String baseUrl) => PocketBase(baseUrl);

  @override
  Future<String?> currentUserEmail() async {
    if (!_pb.authStore.isValid) return null;
    final record = _pb.authStore.record;
    if (record == null) return null;
    final email = record.get<String>('email', '');
    return email.isEmpty ? null : email;
  }

  @override
  Future<void> loginWithGoogle() async {
    try {
      await _pb.collection('users').authWithOAuth2('google', (url) async {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      });
    } on ClientException catch (e) {
      throw ApiException(e.statusCode, _errorMessage(e));
    }
  }

  @override
  Future<void> logout() async {
    _pb.authStore.clear();
  }

  @override
  Future<List<Document>> listDocuments() async {
    final records = await _pb.collection('documents').getFullList(sort: '-created');
    return records.map((r) => Document.fromJson(r.toJson())).toList();
  }

  @override
  Future<Document> createDocument(String title) async {
    final record = await _pb.collection('documents').create(body: {'title': title});
    return Document.fromJson(record.toJson());
  }

  @override
  Future<Document> updateDocumentTitle(String id, String title) async {
    final record =
        await _pb.collection('documents').update(id, body: {'title': title});
    return Document.fromJson(record.toJson());
  }

  @override
  Future<int> countPages(String documentId) async {
    final result = await _pb.collection('pages').getList(
          page: 1,
          perPage: 1,
          filter: "document = '$documentId'",
          skipTotal: false,
        );
    return result.totalItems;
  }

  @override
  Future<List<Page>> listPages(String documentId) async {
    final records = await _pb.collection('pages').getFullList(
          filter: "document = '$documentId'",
          sort: 'page_number',
        );
    return records
        .map((r) => Page.fromJson(r.toJson(), baseUrl: _pb.baseURL.toString()))
        .toList();
  }

  @override
  Future<void> uploadPage(
    String documentId,
    int pageNumber,
    Uint8List bytes,
    String filename,
  ) async {
    await _pb.collection('pages').create(
          body: {
            'document': documentId,
            'page_number': pageNumber,
            'status': 'pending',
          },
          files: [
            http.MultipartFile.fromBytes('image', bytes, filename: filename),
          ],
        );
  }

  @override
  Future<List<SearchResult>> search(String query) async {
    final data = await _pb.send('/api/search', query: {'q': query});
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(SearchResult.fromJson)
        .toList();
  }

  String _errorMessage(ClientException e) {
    final message = e.response['message'];
    return message is String && message.isNotEmpty
        ? message
        : 'Authentication failed';
  }
}
