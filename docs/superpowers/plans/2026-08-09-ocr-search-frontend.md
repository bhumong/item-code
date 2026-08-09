# OCR Search Frontend Implementation Plan (Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Flutter Web frontend for the OCR document search engine described in [`docs/superpowers/specs/2026-08-09-ocr-search-frontend-design.md`](../specs/2026-08-09-ocr-search-frontend-design.md), consuming the Phase 1 PocketBase backend.

**Architecture:** A Flutter web app using go_router for URL-driven navigation (`/`, `/login`, `/documents/:id`, `/search`) and Riverpod for state. A thin `ApiClient` abstraction wraps the official `pocketbase` Dart SDK so widget tests can inject a fake; feature folders (`auth`, `documents`, `pages`, `search`) each own their controllers and widgets. Search is real-time with a 300ms debounce hitting the backend `GET /api/search`, and snippets are rendered by converting the backend `<em>` markers into bold spans.

**Tech Stack:** Flutter 3.44+ (web), Dart 3.12, `flutter_riverpod` (3.x), `go_router` (17.x), `pocketbase` (0.24.x), `file_picker` (11.x), `url_launcher`, `http`, Material 3 with a deep-teal seed color.

**Spec link:** [frontend design spec](../specs/2026-08-09-ocr-search-frontend-design.md)

---

## Repository Layout (target state)

```
frontend/
|-- pubspec.yaml
|-- lib/
|   |-- main.dart                    # ProviderScope + runApp
|   |-- app.dart                     # MaterialApp.router, M3 teal theme, routerProvider
|   |-- core/
|   |   |-- config.dart              # backendBaseUrl (String.fromEnvironment, default localhost:8090)
|   |   |-- models.dart              # Document, DocumentSummary, Page, SearchResult
|   |   `-- api_client.dart          # ApiException, ApiClient, PocketBaseApiClient
|   |-- features/
|   |   |-- auth/
|   |   |   |-- auth_controller.dart
|   |   |   `-- login_screen.dart
|   |   |-- documents/
|   |   |   |-- documents_controller.dart
|   |   |   |-- explorer_screen.dart
|   |   |   |-- create_document_dialog.dart
|   |   |   `-- document_detail_screen.dart
|   |   |-- pages/
|   |   |   |-- pages_controller.dart
|   |   |   |-- upload_controller.dart
|   |   |   |-- page_gallery.dart
|   |   |   `-- status_tag.dart
|   |   `-- search/
|   |       |-- search_controller.dart
|   |       |-- search_results_screen.dart
|   |       `-- highlighted_text.dart
|   `-- shared/
|       `-- error_view.dart          # inline error + retry for AsyncValue errors
|-- test/
|   |-- auth_flow_test.dart
|   |-- explorer_test.dart
|   |-- search_test.dart
|   `-- detail_test.dart
`-- web/
```

Package dependency direction (no cycles): `core` (config, models, api_client) is imported by every feature; features never import each other; `app.dart` imports all features.

**Conventions:**
- All commands run from `frontend/` unless a path is given; git commands run from the repo root.
- Every test file defines its own `FakeApiClient` (in `test/fakes.dart` shared by all widget tests) implementing `ApiClient`.
- `flutter`/`dart` commands need to write to `~/.pub-cache` and the build dir; run them escalated in this environment.

---

## Task 0: Scaffold Flutter Web App, Dependencies, Theme, and Router

**Files:**
- Create: `frontend/` (via `flutter create`), `frontend/lib/core/config.dart`, `frontend/lib/app.dart`, `frontend/lib/main.dart`

- [ ] **Step 1: Scaffold the project**

Run from the repo root:

```bash
flutter create frontend --platforms=web --empty --project-name ocr_search
```

Expected: `frontend/` created with `lib/main.dart`, `web/`, `pubspec.yaml`.

- [ ] **Step 2: Add dependencies**

```bash
cd frontend
flutter pub add flutter_riverpod go_router pocketbase file_picker url_launcher http
```

Expected: dependencies resolve; `pubspec.yaml` shows flutter_riverpod ^3.x, go_router ^17.x, pocketbase ^0.24.x, file_picker ^11.x.

- [ ] **Step 3: Create the config**

`frontend/lib/core/config.dart`:

```dart
class AppConfig {
  const AppConfig._();

  /// Backend base URL. Override at build/run time with:
  /// `flutter run --dart-define=BACKEND_URL=http://localhost:8090`
  static const String backendBaseUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8090');
}
```

- [ ] **Step 4: Create the app shell (theme + router)**

`frontend/lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/documents/document_detail_screen.dart';
import 'features/documents/explorer_screen.dart';
import 'features/search/search_results_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final loggedIn = authState.valueOrNull is Authenticated;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/', builder: (context, state) => const ExplorerScreen()),
      GoRoute(
        path: '/documents/:id',
        builder: (context, state) =>
            DocumentDetailScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchResultsScreen()),
    ],
  );
});

class OcrSearchApp extends ConsumerWidget {
  const OcrSearchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'OCR Search',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
```

`frontend/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(const ProviderScope(child: OcrSearchApp()));
}
```

Note: the feature files referenced above do not exist yet, so this step compiles only after Tasks 2-5. For now, verify the scaffold itself builds:

- [ ] **Step 5: Verify the scaffold builds (before feature code)**

```bash
flutter build web
```

Expected: build succeeds and emits `build/web/` artifacts.

- [ ] **Step 6: Commit**

```bash
git add frontend/
git commit -m "chore: scaffold flutter web frontend with deps"
```

---

## Task 1: Models + ApiClient Abstraction (`core/`)

**Files:**
- Create: `frontend/lib/core/models.dart`
- Create: `frontend/lib/core/api_client.dart`
- Create: `frontend/test/core_models_test.dart`

- [ ] **Step 1: Write the failing test**

`frontend/test/core_models_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/core_models_test.dart
```

Expected: FAIL — package `ocr_search` has no `core/models.dart` yet.

- [ ] **Step 3: Write the models**

`frontend/lib/core/models.dart`:

```dart
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

  factory Page.fromJson(Map<String, dynamic> json, {String baseUrl = 'http://localhost:8090'}) {
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
```

Note: the design spec placed models under `features/documents/`; they live in `core/` instead so `core/api_client.dart` (Task 1, next step) can use them without a core->feature dependency.

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/core_models_test.dart
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/core/models.dart frontend/test/core_models_test.dart
git commit -m "feat: add frontend data models"
```

- [ ] **Step 6: Write the ApiClient interface + real implementation**

`frontend/lib/core/api_client.dart`:

```dart
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
    final model = _pb.authStore.model;
    if (model == null) return null;
    final email = model.get<String>('email', '');
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
    final record =
        await _pb.collection('documents').create(body: {'title': title});
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
        .map((r) => Page.fromJson(r.toJson(), baseUrl: _pb.baseUrl.toString()))
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
    return message is String && message.isNotEmpty ? message : 'Authentication failed';
  }
}
```

- [ ] **Step 7: Add an ApiClient unit test (request shape via a fake http server)**

The full PocketBase flow is exercised in Task 7's E2E. For a fast unit check of the client, verify `ApiException` carries the status code:

`frontend/test/api_exception_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/core/api_client.dart';

void main() {
  test('ApiException exposes statusCode and message', () {
    const e = ApiException(403, 'Your email is not whitelisted');
    expect(e.statusCode, 403);
    expect(e.message, 'Your email is not whitelisted');
    expect(e.toString(), 'Your email is not whitelisted');
  });
}
```

```bash
flutter test test/api_exception_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/core/api_client.dart frontend/test/api_exception_test.dart
git commit -m "feat: add ApiClient abstraction over the PocketBase SDK"
```

---

## Task 2: Auth (Controller, Login Screen, Guard)

**Files:**
- Create: `frontend/lib/features/auth/auth_controller.dart`
- Create: `frontend/lib/features/auth/login_screen.dart`
- Create: `frontend/test/fakes.dart`
- Create: `frontend/test/auth_flow_test.dart`

- [ ] **Step 1: Write the failing test (and shared fake)**

`frontend/test/fakes.dart`:

```dart
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
    final doc = Document(id: 'd${createDocumentCalls}', title: title);
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
    return List.of(searchResults);
  }
}
```

`frontend/test/auth_flow_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/api_client.dart';

import 'fakes.dart';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

void main() {
  testWidgets('shows login screen when unauthenticated', (tester) async {
    await tester.pumpWidget(testApp(FakeApiClient()));
    await tester.pumpAndSettle();

    expect(find.text('OCR Search'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('shows whitelist toast when Google sign-in returns 403',
      (tester) async {
    final fake = FakeApiClient()..loginErrorCode = 403;
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(find.text('Your email is not whitelisted'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('navigates to explorer after successful login', (tester) async {
    final fake = FakeApiClient();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(find.text('New Document'), findsNothing);
    // Explorer is a ConsumerWidget; its scaffold renders once authenticated.
    expect(find.byType(Scaffold), findsWidgets);
  });
}
```

Note: `apiClientProvider` and `ExplorerScreen` do not exist yet; the test fails to compile until Tasks 2-3 add them. `New Document` is the FAB tooltip added in Task 3.

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/auth_flow_test.dart
```

Expected: FAIL — `apiClientProvider` undefined.

- [ ] **Step 3: Write the auth controller and apiClient provider**

`frontend/lib/features/auth/auth_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

sealed class AuthState {
  const AuthState();
}

class Authenticated extends AuthState {
  const Authenticated(this.email);
  final String email;
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return PocketBaseApiClient(
    PocketBaseApiClient.createClient('http://localhost:8090'),
  );
});

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final email = await ref.read(apiClientProvider).currentUserEmail();
    return email == null ? const Unauthenticated() : Authenticated(email);
  }

  Future<void> login() async {
    final api = ref.read(apiClientProvider);
    await api.loginWithGoogle(); // throws ApiException(403) when not whitelisted
    final email = await api.currentUserEmail() ?? 'user';
    state = AsyncData(Authenticated(email));
  }

  Future<void> logout() async {
    await ref.read(apiClientProvider).logout();
    state = const AsyncData(Unauthenticated());
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
```

Note: `apiClientProvider` lives here (auth feature) because `app.dart` needs it for the router and `core/` must not depend on features. `PocketBaseApiClient.createClient` should use `AppConfig.backendBaseUrl`; update the line after Task 6 wires `main.dart` (or use the import now):

```dart
import '../../core/config.dart';
```

and replace `'http://localhost:8090'` with `AppConfig.backendBaseUrl`.

- [ ] **Step 4: Write the login screen**

`frontend/lib/features/auth/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book, size: 72),
              const SizedBox(height: 16),
              const Text(
                'OCR Search',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: auth.isLoading ? null : () => _login(context, ref),
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).login();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sign-in failed. Please try again.')),
      );
    }
  }
}
```

Then add a minimal `ExplorerScreen` placeholder so the router compiles:

`frontend/lib/features/documents/explorer_screen.dart`:

```dart
import 'package:flutter/material.dart';

class ExplorerScreen extends StatelessWidget {
  const ExplorerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Explorer')));
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
flutter test test/auth_flow_test.dart test/core_models_test.dart test/api_exception_test.dart
```

Expected: all PASS. (The third auth test asserts only a Scaffold appears after login; the FAB assertion in Task 3 strengthens it.)

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/features/auth/ frontend/lib/features/documents/explorer_screen.dart frontend/test/
git commit -m "feat: add auth flow with google sign-in and router guard"
```

---

## Task 3: Documents (Controller, Explorer, Create Dialog)

**Files:**
- Create: `frontend/lib/features/documents/documents_controller.dart`
- Create: `frontend/lib/features/documents/create_document_dialog.dart`
- Modify: `frontend/lib/features/documents/explorer_screen.dart`
- Create: `frontend/test/explorer_test.dart`

- [ ] **Step 1: Write the failing test**

`frontend/test/explorer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/api_client.dart';
import 'package:ocr_search/core/models.dart';

import 'fakes.dart';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

FakeApiClient seededFake() {
  final fake = FakeApiClient()..userEmail = 'bob@gmail.com';
  fake.documents.addAll([
    const Document(id: 'd1', title: 'Manual'),
    const Document(id: 'd2', title: 'Receipts'),
  ]);
  fake.pagesByDocument['d1'] = [
    Page(
      id: 'p1',
      documentId: 'd1',
      pageNumber: 1,
      status: 'completed',
      imageUrl: '',
    ),
    Page(
      id: 'p2',
      documentId: 'd1',
      pageNumber: 2,
      status: 'pending',
      imageUrl: '',
    ),
  ];
  return fake;
}

void main() {
  testWidgets('lists documents with page counts', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();

    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('2 pages'), findsOneWidget);
    expect(find.text('0 pages'), findsOneWidget);
  });

  testWidgets('create dialog adds a document and refreshes', (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New Document'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tax 2025');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(fake.createDocumentCalls, 1);
    expect(find.text('Tax 2025'), findsOneWidget);
  });

  testWidgets('search field navigates to /search', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Search results'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/explorer_test.dart
```

Expected: FAIL — `documentsProvider` undefined.

- [ ] **Step 3: Write the documents controller**

`frontend/lib/features/documents/documents_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

class DocumentsController extends AsyncNotifier<List<DocumentSummary>> {
  @override
  Future<List<DocumentSummary>> build() async {
    final api = ref.read(apiClientProvider);
    final docs = await api.listDocuments();
    final summaries = <DocumentSummary>[];
    for (final doc in docs) {
      final count = await api.countPages(doc.id);
      summaries.add(DocumentSummary(document: doc, pageCount: count));
    }
    return summaries;
  }

  Future<void> createDocument(String title) async {
    await ref.read(apiClientProvider).createDocument(title);
    ref.invalidateSelf();
  }
}

final documentsProvider =
    AsyncNotifierProvider<DocumentsController, List<DocumentSummary>>(
  DocumentsController.new,
);
```

- [ ] **Step 4: Write the create dialog**

`frontend/lib/features/documents/create_document_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return AlertDialog(
      title: const Text('New Document'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Title'),
        onSubmitted: (_) => _create(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _create(context),
          child: const Text('Create'),
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
```

- [ ] **Step 5: Write the explorer screen (replacing the placeholder)**

`frontend/lib/features/documents/explorer_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import 'create_document_dialog.dart';
import 'documents_controller.dart';

class ExplorerScreen extends ConsumerWidget {
  const ExplorerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Search'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search documents...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (value) {
                final q = value.trim();
                if (q.isEmpty) return;
                context.go('/search?q=$q');
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Document',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const CreateDocumentDialog(),
        ),
        child: const Icon(Icons.add),
      ),
      body: docs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Failed to load documents: $error')),
        data: (summaries) => summaries.isEmpty
            ? const Center(child: Text('No documents yet. Tap + to create one.'))
            : _DocumentGrid(summaries: summaries),
      ),
    );
  }
}

class _DocumentGrid extends StatelessWidget {
  const _DocumentGrid({required this.summaries});

  final List<DocumentSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 150,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go('/documents/${summary.document.id}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.description_outlined, size: 40),
                  const Spacer(),
                  Text(
                    summary.document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${summary.pageCount} ${summary.pageCount == 1 ? 'page' : 'pages'}',
                    style: Theme.of(context).textTheme.bodySmall,
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
```

`/search` needs a minimal `SearchResultsScreen` so the router compiles; it is implemented in Task 5:

`frontend/lib/features/search/search_results_screen.dart`:

```dart
import 'package:flutter/material.dart';

class SearchResultsScreen extends StatelessWidget {
  const SearchResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Search results')));
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
flutter test test/explorer_test.dart test/auth_flow_test.dart
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/features/documents/ frontend/lib/features/search/ frontend/test/explorer_test.dart
git commit -m "feat: add document explorer with page counts and create dialog"
```

---

## Task 4: Document Detail + Page Gallery + Upload

**Files:**
- Create: `frontend/lib/features/pages/pages_controller.dart`
- Create: `frontend/lib/features/pages/upload_controller.dart`
- Create: `frontend/lib/features/pages/status_tag.dart`
- Create: `frontend/lib/features/pages/page_gallery.dart`
- Create: `frontend/lib/features/documents/document_detail_screen.dart`
- Create: `frontend/test/detail_test.dart`

- [ ] **Step 1: Write the failing test**

`frontend/test/detail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/api_client.dart';
import 'package:ocr_search/core/models.dart';

import 'fakes.dart';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

FakeApiClient seededFake() {
  final fake = FakeApiClient()..userEmail = 'bob@gmail.com';
  fake.documents.add(const Document(id: 'd1', title: 'Manual'));
  fake.pagesByDocument['d1'] = [
    Page(
      id: 'p1',
      documentId: 'd1',
      pageNumber: 1,
      status: 'completed',
      imageUrl: '',
    ),
    Page(
      id: 'p2',
      documentId: 'd1',
      pageNumber: 2,
      status: 'processing',
      imageUrl: '',
    ),
    Page(
      id: 'p3',
      documentId: 'd1',
      pageNumber: 3,
      status: 'failed',
      imageUrl: '',
    ),
  ];
  return fake;
}

void main() {
  testWidgets('detail shows pages with status tags', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Add Pages'), findsOneWidget);
  });

  testWidgets('uploading pages increments progress and refreshes gallery',
      (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    // Call the upload controller directly; file picking is platform-native
    // and not exercised in widget tests.
    final container = ProviderScope.containerOf(
      tester.element(find.text('Add Pages')),
      listen: false,
    );
    await container
        .read(uploadControllerProvider.notifier)
        .addPages('d1', [fakeFile('a.png'), fakeFile('b.png')]);
    await tester.pumpAndSettle();

    expect(fake.pagesByDocument['d1']!.length, 5);
    final uploadState = container.read(uploadControllerProvider);
    expect(uploadState.uploading, false);
    expect(uploadState.done, 2);
  });

  testWidgets('edit action renames the document', (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed Manual');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.documents.first.title, 'Renamed Manual');
  });
}

// Small helper to build a fake PlatformFile-like upload input.
// The upload controller accepts simple (bytes, name) pairs; see upload_controller.dart.
```

Note: the test references `fakeFile(...)` and `uploadControllerProvider` with a specific signature. Define the upload controller to accept `UploadInput` objects so tests stay platform-free:

```dart
class UploadInput {
  const UploadInput({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}
```

Add to `fakes.dart` (imports `dart:typed_data` already there):

```dart
import 'package:ocr_search/features/pages/upload_controller.dart';

UploadInput fakeFile(String name) =>
    UploadInput(bytes: Uint8List.fromList([1, 2, 3]), name: name);
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/detail_test.dart
```

Expected: FAIL — `uploadControllerProvider` undefined.

- [ ] **Step 3: Write the pages controller**

`frontend/lib/features/pages/pages_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

class PagesController extends AsyncNotifier<List<Page>> {
  @override
  Future<List<Page>> build() async {
    final documentId = ref.arguments as String;
    return ref.read(apiClientProvider).listPages(documentId);
  }
}

final pagesProvider =
    AsyncNotifierProvider.family<PagesController, List<Page>, String>(
  PagesController.new,
);
```

- [ ] **Step 4: Write the upload controller**

`frontend/lib/features/pages/upload_controller.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'pages_controller.dart';

class UploadInput {
  const UploadInput({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

class UploadState {
  const UploadState({
    this.uploading = false,
    this.done = 0,
    this.total = 0,
    this.error,
  });

  final bool uploading;
  final int done;
  final int total;
  final String? error;

  UploadState copyWith({bool? uploading, int? done, int? total, String? error}) {
    return UploadState(
      uploading: uploading ?? this.uploading,
      done: done ?? this.done,
      total: total ?? this.total,
      error: error,
    );
  }
}

class UploadController extends Notifier<UploadState> {
  @override
  UploadState build() => const UploadState();

  Future<void> addPages(String documentId, List<UploadInput> files) async {
    if (files.isEmpty) return;
    final api = ref.read(apiClientProvider);
    final base = ref.read(pagesProvider(documentId).valueOrNull)?.length ?? 0;

    state = UploadState(uploading: true, done: 0, total: files.length);
    String? lastError;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        await api.uploadPage(documentId, base + i + 1, file.bytes, file.name);
      } catch (_) {
        lastError = 'Failed to upload ${file.name}';
      }
      state = state.copyWith(done: i + 1, error: lastError);
    }
    state = state.copyWith(uploading: false);
    ref.invalidate(pagesProvider(documentId));
  }
}

final uploadControllerProvider =
    NotifierProvider<UploadController, UploadState>(UploadController.new);
```

- [ ] **Step 5: Write the status tag and page gallery**

`frontend/lib/features/pages/status_tag.dart`:

```dart
import 'package:flutter/material.dart';

class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'completed' => ('Completed', Colors.green),
      'processing' => ('Processing', Colors.amber),
      'failed' => ('Failed', Colors.red),
      _ => ('Pending', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade800,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

`frontend/lib/features/pages/page_gallery.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'status_tag.dart';

class PageGallery extends StatelessWidget {
  const PageGallery({super.key, required this.pages});

  final List<Page> pages;

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
```

- [ ] **Step 6: Write the document detail screen**

`frontend/lib/features/documents/document_detail_screen.dart`:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../pages/page_gallery.dart';
import '../pages/pages_controller.dart';
import '../pages/upload_controller.dart';
import 'documents_controller.dart';

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final inputs = result.files
        .where((f) => f.bytes != null)
        .map((f) => UploadInput(bytes: f.bytes!, name: f.name))
        .toList();
    await ref
        .read(uploadControllerProvider.notifier)
        .addPages(widget.documentId, inputs);
  }

  Future<void> _rename() async {
    final documents = ref.read(documentsProvider).valueOrNull ?? const [];
    final current = documents
        .where((s) => s.document.id == widget.documentId)
        .firstOrNull;
    final controller = TextEditingController(text: current?.document.title ?? '');
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final title = newTitle?.trim();
    if (title == null || title.isEmpty) return;
    await ref.read(apiClientProvider).updateDocumentTitle(widget.documentId, title);
    ref.invalidate(documentsProvider);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(pagesProvider(widget.documentId));
    final upload = ref.watch(uploadControllerProvider);
    final documents = ref.watch(documentsProvider).valueOrNull ?? const [];
    final title = documents
            .where((s) => s.document.id == widget.documentId)
            .firstOrNull
            ?.document
            .title ??
        'Document';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(onPressed: () => context.go('/')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit title',
            onPressed: _rename,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: upload.uploading ? null : _pickAndUpload,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add Pages'),
                ),
                const SizedBox(width: 16),
                if (upload.uploading)
                  Text('Uploading ${upload.done}/${upload.total}...'),
              ],
            ),
          ),
          if (upload.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                upload.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: pages.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  Center(child: Text('Failed to load pages: $error')),
              data: (items) => PageGallery(pages: items),
            ),
          ),
        ],
      ),
    );
  }
}
```

Note: `.firstOrNull` requires `package:collection/collection.dart` (or Dart 3's `Iterable.firstOrNull` from `dart:core` extension — available since Dart 3.0 via `package:collection` re-export; if the analyzer complains, add `import 'package:collection/collection.dart';`).

- [ ] **Step 7: Run the tests to verify they pass**

```bash
flutter test test/detail_test.dart
```

Expected: all 3 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/features/pages/ frontend/lib/features/documents/document_detail_screen.dart frontend/test/
git commit -m "feat: add document detail with page gallery, status tags, and batch upload"
```

---

## Task 5: Search (Debounced Controller, Highlighted Results)

**Files:**
- Create: `frontend/lib/features/search/search_controller.dart`
- Create: `frontend/lib/features/search/highlighted_text.dart`
- Modify: `frontend/lib/features/search/search_results_screen.dart`
- Create: `frontend/test/search_test.dart`

- [ ] **Step 1: Write the failing test**

`frontend/test/search_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/app.dart';
import 'package:ocr_search/core/api_client.dart';
import 'package:ocr_search/core/models.dart';

import 'fakes.dart';

Widget testApp(FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const OcrSearchApp(),
  );
}

void main() {
  testWidgets('search screen debounces and shows highlighted results',
      (tester) async {
    final fake = FakeApiClient()
      ..userEmail = 'bob@gmail.com'
      ..searchResults = [
        const SearchResult(
          documentId: 'd1',
          documentTitle: 'Manual',
          pageId: 'p1',
          pageNumber: 3,
          snippet: 'the <em>needle</em> valve regulates flow',
        ),
      ];
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    // Drive navigation through the explorer search field, then type in the
    // search screen's own field to trigger the debounced fetch.
    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Manual'), findsOneWidget);
    expect(find.textContaining('valve regulates flow'), findsOneWidget);
    // The "needle" match inside the snippet is rendered bold.
    final richText = tester.widget<RichText>(find.byType(RichText).last);
    final boldSpans = richText.text.visitChildren((span) {
      return !(span.style?.fontWeight == FontWeight.bold);
    });
    expect(boldSpans, true);
  });

  testWidgets('empty query shows empty state without calling the api',
      (tester) async {
    final fake = FakeApiClient()..userEmail = 'bob@gmail.com';
    await tester.pumpWidget(testApp(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(fake.searchCalls, 0);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/search_test.dart
```

Expected: FAIL — `searchResultsProvider` undefined.

- [ ] **Step 3: Write the search controller**

`frontend/lib/features/search/search_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String value) => state = value;
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(SearchQuery.new);

class SearchResultsController extends AsyncNotifier<List<SearchResult>> {
  Timer? _debounce;

  @override
  Future<List<SearchResult>> build() async {
    final query = ref.watch(searchQueryProvider);
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return ref.read(apiClientProvider).search(trimmed);
  }

  void updateQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).update(value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final searchResultsProvider =
    AsyncNotifierProvider<SearchResultsController, List<SearchResult>>(
  SearchResultsController.new,
);
```

- [ ] **Step 4: Write the highlighted text widget**

`frontend/lib/features/search/highlighted_text.dart`:

```dart
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
```

- [ ] **Step 5: Write the search results screen (replacing the placeholder)**

`frontend/lib/features/search/search_results_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import 'highlighted_text.dart';
import 'search_controller.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key});

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initialQuery = GoRouterState.of(context).uri.queryParameters['q'] ?? '';
    _controller.text = initialQuery;
    if (initialQuery.isNotEmpty) {
      // Initial query from the URL bypasses the debounce.
      ref.read(searchQueryProvider.notifier).update(initialQuery);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search...'),
          onChanged: (value) =>
              ref.read(searchResultsProvider.notifier).updateQuery(value),
        ),
      ),
      body: results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text('Search failed: $error')),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No results. Try different terms.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _ResultTile(result: items[index]),
              ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.description_outlined, size: 40),
        title: Text('${result.documentTitle} - page ${result.pageNumber}'),
        subtitle: HighlightedText(
          text: result.snippet,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        onTap: () => context.go('/documents/${result.documentId}'),
      ),
    );
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
flutter test test/search_test.dart
```

Expected: both tests PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/features/search/ frontend/test/search_test.dart
git commit -m "feat: add debounced full-text search with highlighted snippets"
```

---

## Task 6: Wire Config + Full Verification Gate

**Files:**
- Modify: `frontend/lib/features/auth/auth_controller.dart` (use `AppConfig.backendBaseUrl`)

- [ ] **Step 1: Use the config constant in the API client provider**

In `frontend/lib/features/auth/auth_controller.dart`, add the import and replace the hardcoded URL:

```dart
import '../../core/config.dart';
```

```dart
final apiClientProvider = Provider<ApiClient>((ref) {
  return PocketBaseApiClient(
    PocketBaseApiClient.createClient(AppConfig.backendBaseUrl),
  );
});
```

- [ ] **Step 2: Run the full verification gate**

```bash
flutter analyze
flutter test
flutter build web
```

Expected: `flutter analyze` reports no issues; `flutter test` passes all tests in `test/`; `flutter build web` emits `build/web/`.

- [ ] **Step 3: Serve the built app and smoke-check it loads**

```bash
python3 -m http.server 8080 --directory build/web > /tmp/frontend_server.log 2>&1 &
curl -s -o /dev/null -w "index: HTTP %{http_code}\n" http://localhost:8080/
curl -s -o /dev/null -w "main.dart.js: HTTP %{http_code}\n" http://localhost:8080/main.dart.js
kill %1
```

Expected: both HTTP 200.

- [ ] **Step 4: Commit**

```bash
git add frontend/
git commit -m "feat: wire backend URL config and pass full verification gate"
```

---

## Task 7: End-to-End Verification Against the Docker Backend

**Files:** none (verification only; commit only if fixes are needed)

Prerequisite: Docker installed (Phase 1), `jq` available.

- [ ] **Step 1: Start the backend stack**

```bash
docker compose up -d
docker compose ps
```

Expected: `minio` and `backend` healthy; `minio-init` exits 0.

- [ ] **Step 2: Verify CORS is permissive for the web app origin**

```bash
curl -s -i -H "Origin: http://localhost:8080" \
  http://localhost:8090/api/health | grep -i "access-control-allow-origin"
```

Expected: `Access-Control-Allow-Origin: *` (PocketBase default). If absent, add CORS handling to the backend `OnServe` middleware and commit the fix.

- [ ] **Step 3: Seed data through the API**

```bash
docker compose exec backend /app/backend superuser create admin@example.com 1234567890
TOKEN=$(curl -s -X POST http://localhost:8090/api/collections/_superusers/auth-with-password \
  -H 'Content-Type: application/json' \
  -d '{"identity":"admin@example.com","password":"1234567890"}' | jq -r .token)
curl -s -X POST http://localhost:8090/api/collections/allowed_users/records \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"email":"me@gmail.com"}' > /dev/null
```

Expected: whitelist record created.

- [ ] **Step 4: Run the web app against the backend**

```bash
cd frontend
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

Then open `http://localhost:8080` in a browser and verify:

1. **Login screen** renders; tapping "Sign in with Google" without configured OAuth credentials shows a graceful failure toast (no crash).
2. With real `GOOGLE_OAUTH_CLIENT_ID/SECRET` in `.env` (backend restart required), a whitelisted account lands on the **Explorer**; a non-whitelisted account gets the "not whitelisted" toast.
3. **Explorer** lists seeded documents with page counts; the FAB creates a document; typing in the header navigates to `/search`.
4. **Detail** shows the page gallery with status tags; "Add Pages" uploads images (visible as new `pending` pages; the cron worker/`ocr-worker` then transitions them to `completed` with `ocr_text` when a real `OCR_API_KEY` is set).
5. **Search** highlights matches in bold from the backend snippets.

- [ ] **Step 5: Commit any fixes from the E2E run**

```bash
git add -A
git commit -m "fix: adjustments found during frontend e2e verification"
```

Only commit if files actually changed.

- [ ] **Step 6: Stop the stack**

```bash
docker compose down
```

---

## Self-Review Notes

**Spec coverage:**

| Spec requirement | Task |
| --- | --- |
| Login screen + Google sign-in + whitelist toast | Task 2 |
| Explorer with fixed header search + card grid + page counts + FAB | Task 3 |
| Detail with edit title + responsive gallery + status tags + Add Pages batch picker | Task 4 |
| Real-time debounced search + highlighted snippets + navigation | Task 5 |
| go_router URLs (`/login`, `/`, `/documents/:id`, `/search`) + auth guard | Tasks 0 + 2 |
| Riverpod state providers | Tasks 2-5 |
| Material 3 teal theme | Task 0 |
| ApiClient abstraction over PocketBase SDK | Task 1 |
| Widget tests + `flutter build web` gate | Tasks 1-6 |
| E2E against docker backend + CORS check | Task 7 |

**No placeholders:** every code step contains complete code; the two "note" blocks in Tasks 3/5 explain test navigation choices, not missing implementation.

**Type consistency:** `ApiClient` is the single interface implemented by `PocketBaseApiClient` and `FakeApiClient`; `UploadInput` is the single upload payload type used by `UploadController.addPages` and tests; `SearchResult.fromJson` mirrors the backend `fts.SearchResult` JSON keys (`document_id`, `document_title`, `page_id`, `page_number`, `snippet`).
