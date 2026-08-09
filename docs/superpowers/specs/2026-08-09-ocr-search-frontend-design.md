# OCR Search Frontend Design (Phase 2)

**Date:** 2026-08-09
**Status:** Approved
**Parent spec:** [`requirement.md`](../../../requirement.md)

## 1. Purpose & Scope

Phase 2 builds the **Flutter Web** frontend for the OCR document search engine, consuming the Phase 1 backend (Go + PocketBase, now merged into `main`). The app provides: Google sign-in (whitelisted), a document explorer, per-document page galleries with OCR status tags and batch image upload, and real-time full-text search with highlighted snippets.

Decisions locked during brainstorming:

1. **Riverpod** for state management (AsyncNotifier/Notifier pattern).
2. **go_router** with real web URLs (`/`, `/login`, `/documents/:id`, `/search`).
3. **Real-time debounced search** (~300ms) from the global header, backed by `GET /api/search`.
4. **Material 3** with a deep-teal seed color, light theme.
5. **Official `pocketbase` Dart SDK** for REST, Google OAuth, file URLs, and token persistence.
6. Verification: **widget tests with a mocked PocketBase client** + `flutter build web`; manual click-through documented.

## 2. Architecture

```
                        Flutter Web app (frontend/)
                              |
              +---------------+----------------+
              |            go_router          |
              |   /             -> Explorer   |
              |   /login        -> Login      |
              |   /documents/:id -> Detail    |
              |   /search       -> Results    |
              +---------------+----------------+
                              |
                    Riverpod providers
              +---------------+----------------+
              |  pbProvider (PocketBase SDK)   |
              |  authControllerProvider        |
              |  documentsProvider (+pageCount)|
              |  searchControllerProvider      |
              |  pagesProvider(documentId)     |
              |  uploadControllerProvider      |
              +---------------+----------------+
                              |
                    PocketBase REST API
            (backend at http://localhost:8090)
```

## 3. Project Layout

```
frontend/
|-- pubspec.yaml
|-- lib/
|   |-- main.dart                    # ProviderScope + runApp
|   |-- app.dart                     # MaterialApp.router, M3 teal theme, router
|   |-- core/
|   |   |-- config.dart              # backend base URL (default http://localhost:8090)
|   |   `-- pb_provider.dart         # PocketBase client provider
|   |-- features/
|   |   |-- auth/
|   |   |   |-- auth_controller.dart
|   |   |   `-- login_screen.dart
|   |   |-- documents/
|   |   |   |-- document_models.dart # Document, DocumentSummary, Page, SearchResult
|   |   |   |-- documents_controller.dart
|   |   |   |-- explorer_screen.dart
|   |   |   |-- create_document_dialog.dart
|   |   |   `-- document_detail_screen.dart
|   |   |-- pages/
|   |   |   |-- pages_controller.dart
|   |   |   |-- page_gallery.dart
|   |   |   `-- status_tag.dart
|   |   `-- search/
|   |       |-- search_controller.dart
|   |       `-- search_results_screen.dart
|   `-- shared/
|       |-- error_toast.dart
|       `-- highlighted_text.dart    # <em> markers -> bold spans
|-- test/
|   |-- auth_flow_test.dart
|   |-- explorer_test.dart
|   |-- search_test.dart
|   `-- detail_test.dart
`-- web/
```

## 4. Screens & Flows

### 4.1 Login

```
+-----------------------------+
|                             |
|        [ OCR Search ]       |
|                             |
|   +---------------------+   |
|   |  Sign in with Google |   |
|   +---------------------+   |
|                             |
|   toast: "Your email is     |
|    not whitelisted"         |
+-----------------------------+
```

Auth guard via router redirect: unauthenticated -> `/login`; already-authed (token in localStorage) -> skip to explorer. `pb.authWithOAuth2('google')`; on 403 (whitelist hook) show the toast and stay.

### 4.2 Document Explorer

```
+----------------------------------------+
| [ Search documents...      ]  [ ... ]  |  fixed header
+----------------------------------------+
| +---------+ +---------+ +---------+    |
| | Manual  | | Receipts| | Tax2025 |    |  card grid, wraps on mobile
| | 12 pages| | 4 pages | | 1 page  |    |  title + page count
| +---------+ +---------+ +---------+    |
|                              (+)       |  FAB -> create dialog
+----------------------------------------+
```

- Header search input: debounced navigation to `/search?q=...`.
- Cards open `/documents/:id`; page counts come from the pages API `totalItems`.
- FAB opens a title dialog, then refreshes the list.

### 4.3 Document Detail & Page Management

```
+----------------------------------------+
| <  Manual            [ edit ]  [ ... ] |  header w/ edit action
+----------------------------------------+
| [ + Add Pages ]                        |  batch multi-image picker
+----------------------------------------+
| +------+ +------+ +------+             |
| |  p1  | |  p2  | |  p3  |             |  responsive multi-column
| | [img]| | [img]| | [img]|             |  gallery + thumbnails
| |  done| |  proc| |  fail|             |  status tags w/ colors
| +------+ +------+ +------+             |
+----------------------------------------+
```

- Add Pages -> `file_picker` multi-select -> sequential upload with per-file progress. Backend creates `ocr_queue` entries; statuses refresh after upload.
- Edit -> rename dialog.
- Status tags: `pending` (grey), `processing` (amber), `completed` (green), `failed` (red).

### 4.4 Search Results

```
+----------------------------------------+
| <  [ needle                ]           |  real-time search bar
+----------------------------------------+
|  Manual - page 3                       |
|  +----+  "The needle valve regulates.."|  thumbnail + highlighted
|  +----+                                |  snippet (em -> bold span)
|  Receipts - page 1                     |
|  +----+  "needle thread co. invoice.." |
|  +----+                                |
+----------------------------------------+
```

- Debounced fetch to `/api/search` (300ms).
- Results parse the backend's `<em>...</em>` markers into bold spans via `highlighted_text.dart`.
- Tapping a result opens the document.

## 5. Providers & State

| Provider | Type | Purpose |
| --- | --- | --- |
| `pbProvider` | Provider | PocketBase client from `core/config.dart` |
| `authControllerProvider` | AsyncNotifier | auth state; `login()`/`logout()`; surfaces whitelist 403 |
| `documentsProvider` | AsyncNotifier | `List<DocumentSummary>` (doc + pageCount) |
| `searchQueryProvider` | Notifier | current query text |
| `searchResultsProvider` | AsyncNotifier | debounce 300ms -> `GET /api/search` |
| `pagesProvider(documentId)` | AsyncNotifier.family | pages sorted by page_number |
| `uploadControllerProvider` | Notifier | upload progress; `addPages(docId, files)` |

## 6. API Integration

- Standard CRUD via the SDK; auth token rides along automatically.
- `/api/search` via `pb.send('/api/search', method: 'GET', query: {'q': q})`.
- Thumbnails via `pb.files.getURL(page, 'image')`.
- Page counts via pages list `totalItems`.
- CORS: PocketBase ships permissive CORS by default; verified during E2E.

## 7. Error Handling

- OAuth 403 -> toast "Your email is not whitelisted", stay on login.
- Network/load failures -> AsyncNotifier error states render inline retry.
- Batch upload: per-file failures toast and continue; progress shown per file.

## 8. Testing Strategy

- Widget tests with a mocked PocketBase client injected via `ProviderScope(overrides:)`:
  - login gating + whitelist toast
  - explorer list/counts
  - search snippet highlighting
  - detail status tags
- `flutter test` + `flutter build web` as the automated gate.
- Manual click-through against the docker backend documented in the plan.

## 9. Out of Scope

- Backend changes (Phase 1, merged).
- Deployment/hosting of the built web app.
- Dark mode / accessibility theming beyond M3 defaults.

