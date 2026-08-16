# OCR Search Phase 3 (FE + BE Improvements) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the six Phase 3 improvements on top of the merged Phase 1 (backend) and Phase 2 (frontend): rename the detail upload button to "Upload Image", add EN/ID localization with an app-bar toggle, make search results image-first, force deterministic OCR (temperature 0, env-configurable), swap in a high-precision OCR system prompt, and add an "Upload from Camera" button.

**Architecture:** Backend-first. The Go side extends `OCRConfig` with `Temperature`, changes the OCR client to send a `system`-role high-precision prompt plus an explicit `temperature` field, and adds an `image UNINDEXED` column to the FTS5 `search_fts` table (drop/recreate migration 003) exposed as `page_image` in `/api/search`. The Flutter side uses standard `gen-l10n` with ARB files and a Riverpod `localeProvider` (initialized from the platform locale, toggled from the explorer app bar), re-renders search result cards with a full-width thumbnail on top, and adds a camera capture button that reuses the existing `uploadControllerProvider`.

**Tech Stack:** Go 1.26 + PocketBase 0.39 + SQLite FTS5; Flutter (Dart SDK ^3.12.2, Flutter 3.44+) + Riverpod 3 + go_router 17 + `flutter_localizations`/`intl` (gen-l10n) + `image_picker`.

---

## Scope Check

The spec explicitly locked "Approach A: one combined plan (single branch/PR covering FE + BE)" during brainstorming, so a single plan is correct here. Tasks are ordered so each produces working, testable software: backend first (Tasks 1-4), then frontend (Tasks 5-11), then the full verification gate (Task 12).

## File Structure

### Backend (`backend/`)

| File | Responsibility |
| --- | --- |
| `internal/config/config.go` | Add `Temperature float64` to `OCRConfig`, parse `OCR_TEMPERATURE` via new `getenvFloat` |
| `internal/config/config_test.go` | Default + override tests for `OCR_TEMPERATURE` |
| `.env.example` (repo root) | Add `OCR_TEMPERATURE=0` |
| `internal/ocr/ocr.go` | `Config.Temperature`, `temperature` JSON field on the request, high-precision system prompt |
| `internal/ocr/ocr_test.go` | Assert system prompt + temperature request shape |
| `internal/migrations/003_search_fts_image.go` | Drop/recreate `search_fts` with `image UNINDEXED` |
| `internal/migrations/migrations_test.go` | Assert `image` column exists |
| `internal/fts/fts.go` | Store `page.GetString("image")` on upsert; expose as `page_image` in search |
| `internal/fts/fts_test.go` | Image round-trip test + `page_image` JSON tag |
| `internal/search/search_test.go` | Assert `page_image` in search results |
| `main.go` | Pass `Temperature` into `ocr.NewClient` |

### Frontend (`frontend/`)

| File | Responsibility |
| --- | --- |
| `pubspec.yaml` | Add `flutter_localizations`, `intl`, `image_picker`; `generate: true` |
| `l10n.yaml` | gen-l10n config (`arb-dir: lib/l10n`, `app_en.arb` template) |
| `lib/l10n/app_en.arb`, `lib/l10n/app_id.arb` | All UI strings in English + Indonesian |
| `lib/core/locale_provider.dart` | `localeProvider` (`Notifier<Locale>`): platform-locale default + `toggle()` |
| `lib/app.dart` | Wire `localizationsDelegates`, `supportedLocales`, `locale` into `MaterialApp.router` |
| `lib/features/documents/explorer_screen.dart` | App-bar EN/ID toggle + i18n strings |
| `lib/features/documents/create_document_dialog.dart` | i18n strings |
| `lib/features/auth/login_screen.dart` | i18n strings |
| `lib/features/documents/document_detail_screen.dart` | Rename button, i18n strings, camera button + capture flow |
| `lib/features/pages/upload_controller.dart` | Add `imagePickerProvider` for test injection |
| `lib/features/pages/page_gallery.dart` | i18n empty-state hint |
| `lib/features/pages/status_tag.dart` | i18n status labels |
| `lib/features/search/search_results_screen.dart` | i18n strings + image-first result cards |
| `lib/core/models.dart` | `SearchResult.pageImage` + URL building |
| `lib/core/api_client.dart` | Pass `baseUrl` into `SearchResult.fromJson` |

### Tests (frontend)

| File | Covers |
| --- | --- |
| `test/locale_provider_test.dart` | Provider default + toggle (new) |
| `test/explorer_test.dart` | Locale toggle flips labels to Indonesian |
| `test/detail_test.dart` | "Upload Image" rename, camera button, camera wiring |
| `test/auth_flow_test.dart` | Indonesian login screen |
| `test/search_test.dart` | Indonesian empty state, image above title |
| `test/core_models_test.dart` | `page_image` -> `pageImage` URL |

---

## Task 1: Backend config — `OCR_TEMPERATURE`

**Files:**
- Modify: `backend/internal/config/config.go`
- Modify: `backend/internal/config/config_test.go`
- Modify: `.env.example`

- [ ] **Step 1: Write the failing test**

In `backend/internal/config/config_test.go`, add the env clearing line and the default assertion inside `TestLoadDefaults`:

```go
func TestLoadDefaults(t *testing.T) {
	t.Setenv("S3_ENDPOINT", "")
	t.Setenv("OCR_API_KEY", "")
	t.Setenv("OCR_MODEL", "")
	t.Setenv("OCR_CONCURRENCY", "")
	t.Setenv("OCR_RETRY_MAX", "")
	t.Setenv("OCR_TIMEOUT", "")
	t.Setenv("OCR_TEMPERATURE", "")
	t.Setenv("GOOGLE_OAUTH_CLIENT_ID", "")
	t.Setenv("GOOGLE_OAUTH_CLIENT_SECRET", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	// ... existing assertions unchanged ...
	if cfg.OCR.Timeout != 120*time.Second {
		t.Errorf("OCR.Timeout = %v, want 120s", cfg.OCR.Timeout)
	}
	if cfg.OCR.Temperature != 0 {
		t.Errorf("OCR.Temperature = %v, want 0 (default)", cfg.OCR.Temperature)
	}
}
```

Then add the override inside `TestLoadOverrides` (after the existing `t.Setenv` calls and near the other `OCR.*` assertions):

```go
	t.Setenv("OCR_TEMPERATURE", "0.5")

	// ... existing assertions unchanged ...
	if cfg.OCR.Temperature != 0.5 {
		t.Errorf("OCR.Temperature = %v, want 0.5", cfg.OCR.Temperature)
	}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && go test ./internal/config/ -run TestLoad -v`

Expected: FAIL with a compile error such as `cfg.OCR.Temperature undefined (type config.OCRConfig has no field or method Temperature)`.

- [ ] **Step 3: Write the minimal implementation**

In `backend/internal/config/config.go`:

1. Add the field to `OCRConfig` (after `Timeout`):

```go
type OCRConfig struct {
	BaseURL     string
	APIKey      string
	Model       string
	Concurrency int
	RetryMax    int
	Timeout     time.Duration
	Temperature float64
}
```

2. Wire it in `Load()` (after the `Timeout` line):

```go
		OCR: OCRConfig{
			BaseURL:     getenv("OCR_BASE_URL", "https://openrouter.ai/api/v1"),
			APIKey:      os.Getenv("OCR_API_KEY"),
			Model:       getenv("OCR_MODEL", "google/gemini-2.5-flash"),
			Concurrency: getenvInt("OCR_CONCURRENCY", 5),
			RetryMax:    getenvInt("OCR_RETRY_MAX", 3),
			Timeout:     getenvDuration("OCR_TIMEOUT", 120*time.Second),
			Temperature: getenvFloat("OCR_TEMPERATURE", 0),
		},
```

3. Add the helper next to `getenvDuration`:

```go
func getenvFloat(key string, fallback float64) float64 {
	if v := os.Getenv(key); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f
		}
	}
	return fallback
}
```

`strconv` is already imported.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/config/ -v`

Expected: `PASS` for all config tests.

- [ ] **Step 5: Update `.env.example`**

In `.env.example` (repo root), after the `OCR_TIMEOUT=120s` line, add:

```text
OCR_TEMPERATURE=0
```

- [ ] **Step 6: Commit**

```bash
git add backend/internal/config/config.go backend/internal/config/config_test.go .env.example
git commit -m "feat(backend): add OCR_TEMPERATURE env config with default 0"
```

---

## Task 2: Backend OCR client — temperature + high-precision system prompt

**Files:**
- Modify: `backend/internal/ocr/ocr.go`
- Modify: `backend/internal/ocr/ocr_test.go`
- Modify: `backend/main.go`

- [ ] **Step 1: Write the failing tests**

In `backend/internal/ocr/ocr_test.go`, replace the request-shape assertions at the bottom of `TestExtractTextSuccess` (everything from `if gotBody.Model != "google/gemini-test"` through the `wantPrefix` check) with:

```go
	if gotBody.Model != "google/gemini-test" {
		t.Errorf("request model = %q", gotBody.Model)
	}
	if gotBody.Temperature != 0 {
		t.Errorf("request temperature = %v, want 0", gotBody.Temperature)
	}
	if len(gotBody.Messages) != 2 {
		t.Fatalf("messages len = %d, want 2 (system + user)", len(gotBody.Messages))
	}
	sys := gotBody.Messages[0]
	if sys.Role != "system" {
		t.Errorf("messages[0] role = %q, want system", sys.Role)
	}
	if len(sys.Content) != 1 || sys.Content[0].Type != "text" {
		t.Fatalf("system content = %+v, want single text part", sys.Content)
	}
	if !strings.Contains(sys.Content[0].Text, "high-precision Optical Character Recognition") {
		t.Errorf("system prompt missing high-precision intro: %q", sys.Content[0].Text)
	}
	user := gotBody.Messages[1]
	if user.Role != "user" {
		t.Errorf("messages[1] role = %q, want user", user.Role)
	}
	if len(user.Content) != 1 || user.Content[0].Type != "image_url" || user.Content[0].ImageURL == nil {
		t.Fatalf("user content = %+v, want single image_url part", user.Content)
	}
	wantPrefix := "data:image/png;base64,"
	if !strings.HasPrefix(user.Content[0].ImageURL.URL, wantPrefix) {
		t.Errorf("image url = %q, want prefix %q", user.Content[0].ImageURL.URL, wantPrefix)
	}
```

Then add this new test to the same file:

```go
func TestExtractTextSendsTemperature(t *testing.T) {
	var raw map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"ok"}}]}`))
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "k", Model: "m", Temperature: 0.5})
	if _, err := c.ExtractText(context.Background(), []byte("x"), "image/png"); err != nil {
		t.Fatalf("ExtractText() error: %v", err)
	}
	temp, ok := raw["temperature"].(float64)
	if !ok || temp != 0.5 {
		t.Errorf("temperature = %v (%T), want 0.5", raw["temperature"], raw["temperature"])
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/ocr/ -v`

Expected: FAIL — compile error (`chatCompletionRequest has no field Temperature`) and/or assertion failures (1 message instead of 2, user role instead of system).

- [ ] **Step 3: Write the minimal implementation**

In `backend/internal/ocr/ocr.go`:

1. Replace the `defaultPrompt` const with the high-precision prompt (exact text from the spec):

```go
const highPrecisionPrompt = `You are a high-precision Optical Character Recognition (OCR) engine. Your sole task is to transcribe all readable text from the provided image exactly as it appears.

## Rules:
1. Transcribe all text verbatim. Preserve original casing, punctuation, spelling, and line breaks.
2. Do NOT convert or format the output into Markdown, JSON, HTML, bullet lists, or tables.
3. Do NOT fix typos, correct grammar, or alter words.
4. Mark illegible or completely cut-off text as [unclear].
5. Output ONLY the raw transcribed text. Do NOT include any introductory or concluding comments, greetings, or meta-explanations.`
```

2. Add `Temperature` to `Config`:

```go
type Config struct {
	BaseURL     string
	APIKey      string
	Model       string
	Timeout     time.Duration
	Temperature float64
}
```

3. Add the JSON field to the request struct (no `omitempty` — an explicit `temperature: 0` must be serialized):

```go
type chatCompletionRequest struct {
	Model       string    `json:"model"`
	Temperature float64   `json:"temperature"`
	Messages    []Message `json:"messages"`
}
```

4. Add a matching `temperature float64` field to the `Client` struct and set it in `NewClient` (e.g. `temperature: cfg.Temperature`), then reference `c.temperature` in the request body.

5. Rebuild the request body in `ExtractText`:

```go
	reqBody := chatCompletionRequest{
		Model:       c.model,
		Temperature: c.Temperature,
		Messages: []Message{
			{Role: "system", Content: []ContentPart{{Type: "text", Text: highPrecisionPrompt}}},
			{Role: "user", Content: []ContentPart{
				{
					Type: "image_url",
					ImageURL: &ImageURL{
						URL: fmt.Sprintf("data:%s;base64,%s", mime, base64.StdEncoding.EncodeToString(imageData)),
					},
				},
			}},
		},
	}
```

5. In `backend/main.go`, pass the temperature through:

```go
	client := ocr.NewClient(ocr.Config{
		BaseURL:     cfg.OCR.BaseURL,
		APIKey:      cfg.OCR.APIKey,
		Model:       cfg.OCR.Model,
		Timeout:     cfg.OCR.Timeout,
		Temperature: cfg.OCR.Temperature,
	})
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/ocr/ -v`

Expected: `PASS` for all OCR client tests, including `TestExtractTextSendsTemperature`.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/ocr/ocr.go backend/internal/ocr/ocr_test.go backend/main.go
git commit -m "feat(backend): deterministic OCR temperature and high-precision system prompt"
```

---

## Task 3: Backend migration 003 — `search_fts` image column

**Files:**
- Create: `backend/internal/migrations/003_search_fts_image.go`
- Modify: `backend/internal/migrations/migrations_test.go`

- [ ] **Step 1: Write the failing test**

Add to `backend/internal/migrations/migrations_test.go`:

```go
func TestSearchFTSHasImageColumn(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	defer app.Cleanup()

	// A SELECT on the image column fails if the column is missing.
	rows, err := app.DB().NewQuery("SELECT image FROM search_fts LIMIT 1").Rows()
	if err != nil {
		t.Fatalf("search_fts image column query error: %v", err)
	}
	rows.Close()
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && go test ./internal/migrations/ -run TestSearchFTSHasImageColumn -v`

Expected: FAIL with `no such column: image`.

- [ ] **Step 3: Write the minimal implementation**

Create `backend/internal/migrations/003_search_fts_image.go`:

```go
package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

func init() {
	migrations.Register(createSearchFTSWithImage, dropSearchFTSWithImage)
}

// FTS5 virtual tables cannot be altered in place, so this drops and recreates
// search_fts with an added UNINDEXED image column. Existing rows are
// re-indexed by the sync hooks on the next page update; nothing is seeded.
func createSearchFTSWithImage(app core.App) error {
	if _, err := app.DB().NewQuery(`DROP TABLE IF EXISTS search_fts`).Execute(); err != nil {
		return err
	}
	_, err := app.DB().NewQuery(`
		CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
			title,
			ocr_text,
			page_id UNINDEXED,
			document_id UNINDEXED,
			page_number UNINDEXED,
			image UNINDEXED
		)
	`).Execute()
	return err
}

func dropSearchFTSWithImage(app core.App) error {
	_, err := app.DB().NewQuery(`DROP TABLE IF EXISTS search_fts`).Execute()
	return err
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/migrations/ -v`

Expected: `PASS` for all migration tests (the new column query succeeds; existing `TestSearchFTSExists` still passes because 003 recreates the table).

- [ ] **Step 5: Commit**

```bash
git add backend/internal/migrations/003_search_fts_image.go backend/internal/migrations/migrations_test.go
git commit -m "feat(backend): recreate search_fts with image column (migration 003)"
```

---

## Task 4: Backend FTS — store and expose the page image

**Files:**
- Modify: `backend/internal/fts/fts.go`
- Modify: `backend/internal/fts/fts_test.go`
- Modify: `backend/internal/search/search_test.go`

- [ ] **Step 1: Write the failing tests**

In `backend/internal/fts/fts_test.go`:

1. Add `"page_image"` to the expected JSON keys in `TestSearchResultJSONTags`:

```go
	for _, key := range []string{`"document_id"`, `"document_title"`, `"page_id"`, `"page_number"`, `"snippet"`, `"page_image"`} {
```

2. Add a new round-trip test:

```go
func TestUpsertPageStoresImage(t *testing.T) {
	app := newTestApp(t)

	doc := createDocument(t, app, "Manual")
	page := createPage(t, app, doc.Id, 1, "needle text")
	if err := UpsertPage(app, page); err != nil {
		t.Fatalf("UpsertPage() error: %v", err)
	}

	results, err := Search(app, "needle", 10)
	if err != nil {
		t.Fatalf("Search() error: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("results len = %d, want 1", len(results))
	}
	if results[0].PageImage != page.GetString("image") {
		t.Errorf("PageImage = %q, want %q (stored filename)", results[0].PageImage, page.GetString("image"))
	}
}
```

In `backend/internal/search/search_test.go`, inside `TestRunSearchReturnsMatches`, after the `PageNumber` assertion add:

```go
	if results[0].PageImage != page.GetString("image") {
		t.Errorf("PageImage = %q, want %q", results[0].PageImage, page.GetString("image"))
	}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/fts/ ./internal/search/`

Expected: FAIL — compile error (`SearchResult has no field or method PageImage`).

- [ ] **Step 3: Write the minimal implementation**

In `backend/internal/fts/fts.go`:

1. Add the field to `SearchResult`:

```go
type SearchResult struct {
	DocumentID    string `db:"document_id" json:"document_id"`
	DocumentTitle string `db:"title" json:"document_title"`
	PageID        string `db:"page_id" json:"page_id"`
	PageNumber    int    `db:"page_number" json:"page_number"`
	Snippet       string `db:"snippet" json:"snippet"`
	PageImage     string `db:"page_image" json:"page_image"`
}
```

2. Store the image filename in `UpsertPage`:

```go
	pageID := page.Id
	docID := doc.Id
	title := doc.GetString("title")
	ocrText := page.GetString("ocr_text")
	pageNumber := page.GetInt("page_number")
	image := page.GetString("image")

	return app.RunInTransaction(func(txApp core.App) error {
		if _, err := txApp.DB().NewQuery(`DELETE FROM search_fts WHERE page_id = {:page_id}`).
			Bind(dbx.Params{"page_id": pageID}).Execute(); err != nil {
			return err
		}
		_, err := txApp.DB().NewQuery(`
			INSERT INTO search_fts(title, ocr_text, page_id, document_id, page_number, image)
			VALUES ({:title}, {:ocr_text}, {:page_id}, {:document_id}, {:page_number}, {:image})
		`).Bind(dbx.Params{
			"title":       title,
			"ocr_text":    ocrText,
			"page_id":     pageID,
			"document_id": docID,
			"page_number": pageNumber,
			"image":       image,
		}).Execute()
		return err
	})
```

3. Select the image in `Search`:

```go
	err := app.DB().NewQuery(`
		SELECT document_id, title, page_id, page_number, image AS page_image,
		       highlight(search_fts, 1, '<em>', '</em>') AS snippet
		FROM search_fts
		WHERE search_fts MATCH {:q}
		ORDER BY rank
		LIMIT {:limit}
	`).Bind(dbx.Params{
		"q":     SanitizeQuery(q),
		"limit": limit,
	}).All(&results)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./...`

Expected: `PASS` / `ok` for every backend package.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/fts/fts.go backend/internal/fts/fts_test.go backend/internal/search/search_test.go
git commit -m "feat(backend): expose page image in search results"
```

---

## Task 5: Frontend i18n scaffolding — deps, l10n.yaml, ARB files

**Files:**
- Modify: `frontend/pubspec.yaml`
- Create: `frontend/l10n.yaml`
- Create: `frontend/lib/l10n/app_en.arb`
- Create: `frontend/lib/l10n/app_id.arb`

- [ ] **Step 1: Add the dependencies and `generate: true`**

In `frontend/pubspec.yaml`, add `flutter_localizations` and `intl` to dependencies and `generate: true` under `flutter`:

```yaml
dependencies:
  file_picker: ^11.0.3
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_riverpod: ^3.4.2
  go_router: ^17.4.0
  http: ^1.6.0
  intl: ^0.20.2
  pocketbase: ^0.24.0+1
  url_launcher: ^6.3.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
  generate: true
```

If `intl: ^0.20.2` conflicts with the version pinned by your `flutter_localizations`, run `flutter pub add intl` and let pub resolve the SDK-compatible version.

- [ ] **Step 2: Create `l10n.yaml`**

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

- [ ] **Step 3: Create `lib/l10n/app_en.arb`** (exact content)

```json
{
  "@@locale": "en",
  "appTitle": "OCR Search",
  "signInWithGoogle": "Sign in with Google",
  "signInFailed": "Sign-in failed. Please try again.",
  "searchDocumentsHint": "Search documents...",
  "noDocumentsYet": "No documents yet. Tap + to create one.",
  "newDocument": "New Document",
  "pageCount": "{count} {count, plural, =1{page} other{pages}}",
  "@pageCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "failedToLoadDocuments": "Failed to load documents: {error}",
  "@failedToLoadDocuments": {
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
  "documentTitle": "Document",
  "editTitle": "Edit title",
  "uploadImage": "Upload Image",
  "uploadFromCamera": "Upload from Camera",
  "uploadingProgress": "Uploading {done}/{total}...",
  "@uploadingProgress": {
    "placeholders": {
      "done": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "failedToLoadPages": "Failed to load pages: {error}",
  "@failedToLoadPages": {
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
  "noPagesYet": "No pages yet. Use Upload Image.",
  "renameDocument": "Rename Document",
  "titleLabel": "Title",
  "cancel": "Cancel",
  "save": "Save",
  "create": "Create",
  "statusPending": "Pending",
  "statusProcessing": "Processing",
  "statusCompleted": "Completed",
  "statusFailed": "Failed",
  "searchHint": "Search...",
  "searchFailed": "Search failed: {error}",
  "@searchFailed": {
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
  "noResults": "No results. Try different terms.",
  "resultTitle": "{title} - page {page}",
  "@resultTitle": {
    "placeholders": {
      "title": {
        "type": "String"
      },
      "page": {
        "type": "int"
      }
    }
  }
}
```

- [ ] **Step 4: Create `lib/l10n/app_id.arb`** (exact content)

```json
{
  "@@locale": "id",
  "appTitle": "Pencarian OCR",
  "signInWithGoogle": "Masuk dengan Google",
  "signInFailed": "Gagal masuk. Silakan coba lagi.",
  "searchDocumentsHint": "Cari dokumen...",
  "noDocumentsYet": "Belum ada dokumen. Ketuk + untuk membuat.",
  "newDocument": "Dokumen Baru",
  "pageCount": "{count} {count, plural, =1{halaman} other{halaman}}",
  "@pageCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "failedToLoadDocuments": "Gagal memuat dokumen: {error}",
  "@failedToLoadDocuments": {
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
  "documentTitle": "Dokumen",
  "editTitle": "Ubah judul",
  "uploadImage": "Unggah Gambar",
  "uploadFromCamera": "Unggah dari Kamera",
  "uploadingProgress": "Mengunggah {done}/{total}...",
  "@uploadingProgress": {
    "placeholders": {
      "done": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "failedToLoadPages": "Gagal memuat halaman: {error}",
  "@failedToLoadPages": {
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
  "noPagesYet": "Belum ada halaman. Gunakan Unggah Gambar.",
  "renameDocument": "Ubah Nama Dokumen",
  "titleLabel": "Judul",
  "cancel": "Batal",
  "save": "Simpan",
  "create": "Buat",
  "statusPending": "Menunggu",
  "statusProcessing": "Diproses",
  "statusCompleted": "Selesai",
  "statusFailed": "Gagal",
  "searchHint": "Cari...",
  "searchFailed": "Pencarian gagal: {error}",
  "@searchFailed": {
    "placeholders": {
      "error": {
        "type": "String"
      }
    }
  },
  "noResults": "Tidak ada hasil. Coba kata lain.",
  "resultTitle": "{title} - halaman {page}",
  "@resultTitle": {
    "placeholders": {
      "title": {
        "type": "String"
      },
      "page": {
        "type": "int"
      }
    }
  }
}
```

- [ ] **Step 5: Verify generation**

Run: `cd frontend && flutter pub get && flutter gen-l10n`

Expected: both exit 0, no errors. Generated files land in `lib/l10n/` (`app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_id.dart`) and ARE committed. Import path: `package:ocr_search/l10n/app_localizations.dart` (not the synthetic package). The `pageCount` message must include the leading `{count}` placeholder, otherwise gen-l10n renders only the plural word ("pages" instead of "2 pages").

Run: `cd frontend && flutter analyze`

Expected: `No issues found!` (no usages yet, so nothing to flag).

- [ ] **Step 6: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock frontend/l10n.yaml frontend/lib/l10n/
git commit -m "chore(frontend): scaffold gen-l10n with en and id ARB files"
```

---

## Task 6: Frontend locale provider + app wiring + explorer toggle & i18n

**Files:**
- Create: `frontend/lib/core/locale_provider.dart`
- Modify: `frontend/lib/app.dart`
- Modify: `frontend/lib/features/documents/explorer_screen.dart`
- Modify: `frontend/lib/features/documents/create_document_dialog.dart`
- Test: `frontend/test/locale_provider_test.dart`
- Test: `frontend/test/explorer_test.dart`

- [ ] **Step 1: Write the failing provider test**

Create `frontend/test/locale_provider_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_search/core/locale_provider.dart';

void main() {
  test('defaults to en when the platform locale is not id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('toggle flips between en and id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(localeProvider.notifier).toggle();
    expect(container.read(localeProvider), const Locale('id'));
    container.read(localeProvider.notifier).toggle();
    expect(container.read(localeProvider), const Locale('en'));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && flutter test test/locale_provider_test.dart`

Expected: FAIL — `Error: Error when reading 'lib/core/locale_provider.dart': No such file or directory` (the import cannot be resolved).

- [ ] **Step 3: Create the provider and wire the app**

Create `frontend/lib/core/locale_provider.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    final device = PlatformDispatcher.instance.locale;
    return device.languageCode == 'id' ? const Locale('id') : const Locale('en');
  }

  void toggle() {
    state =
        state.languageCode == 'en' ? const Locale('id') : const Locale('en');
  }
}

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
```

In `frontend/lib/app.dart`, add the localization wiring to `OcrSearchApp.build`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/locale_provider.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/documents/document_detail_screen.dart';
import 'features/documents/explorer_screen.dart';
import 'features/search/search_results_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // ... unchanged ...
});

class OcrSearchApp extends ConsumerWidget {
  const OcrSearchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'OCR Search',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 4: Run the provider test to verify it passes**

Run: `cd frontend && flutter test test/locale_provider_test.dart`

Expected: PASS.

- [ ] **Step 5: Write the failing toggle test**

In `frontend/test/explorer_test.dart`, add:

```dart
  testWidgets('locale toggle flips explorer labels to Indonesian',
      (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ID'));
    await tester.pumpAndSettle();

    expect(find.text('Cari dokumen...'), findsOneWidget);
  });
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `cd frontend && flutter test test/explorer_test.dart`

Expected: FAIL — `no widget found` for `find.text('ID')` (no toggle yet) or the search hint is still English.

- [ ] **Step 7: Implement the explorer toggle and i18n**

Replace the whole `frontend/lib/features/documents/explorer_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/locale_provider.dart';
import '../../core/models.dart';
import 'create_document_dialog.dart';
import 'documents_controller.dart';

class ExplorerScreen extends ConsumerWidget {
  const ExplorerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          TextButton(
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            child: Text(
              ref.watch(localeProvider).languageCode == 'en' ? 'ID' : 'EN',
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchDocumentsHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
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
        tooltip: l10n.newDocument,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const CreateDocumentDialog(),
        ),
        child: const Icon(Icons.add),
      ),
      body: docs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(l10n.failedToLoadDocuments('$error'))),
        data: (summaries) => summaries.isEmpty
            ? Center(child: Text(l10n.noDocumentsYet))
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
    final l10n = AppLocalizations.of(context)!;
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
                    l10n.pageCount(summary.pageCount),
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

In `frontend/lib/features/documents/create_document_dialog.dart`, localize the strings:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.newDocument),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.titleLabel),
        onSubmitted: (_) => _create(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => _create(context),
          child: Text(l10n.create),
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

- [ ] **Step 8: Run the explorer tests to verify they pass**

Run: `cd frontend && flutter test test/explorer_test.dart`

Expected: PASS for all explorer tests, including the new Indonesian toggle test. (The existing tests still expect English by default, e.g. `2 pages`, `Create`, and the toggle is the only new widget.)

- [ ] **Step 9: Commit**

```bash
git add frontend/lib/core/locale_provider.dart frontend/lib/app.dart frontend/lib/features/documents/explorer_screen.dart frontend/lib/features/documents/create_document_dialog.dart frontend/test/locale_provider_test.dart frontend/test/explorer_test.dart
git commit -m "feat(frontend): add locale provider, EN/ID toggle, and explorer i18n"
```

---

## Task 7: Frontend detail screen — rename upload button + i18n

**Files:**
- Modify: `frontend/lib/features/documents/document_detail_screen.dart`
- Modify: `frontend/lib/features/pages/page_gallery.dart`
- Modify: `frontend/lib/features/pages/status_tag.dart`
- Test: `frontend/test/detail_test.dart`

- [ ] **Step 1: Update the failing tests**

In `frontend/test/detail_test.dart`, change the button assertion in the first test:

```dart
    expect(find.text('Upload Image'), findsOneWidget);
```

The second test (`uploading pages increments progress and refreshes gallery`) also locates the button via `tester.element(find.text('Add Pages'))` — update that reference to `find.text('Upload Image')` as well.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && flutter test test/detail_test.dart`

Expected: FAIL — `no widget found` for `find.text('Upload Image')` (button still says "Add Pages").

- [ ] **Step 3: Implement the rename and i18n**

Replace `frontend/lib/features/pages/status_tag.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = switch (status) {
      'completed' => (l10n.statusCompleted, Colors.green),
      'processing' => (l10n.statusProcessing, Colors.amber),
      'failed' => (l10n.statusFailed, Colors.red),
      _ => (l10n.statusPending, Colors.grey),
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

In `frontend/lib/features/pages/page_gallery.dart`, add the import and localize the empty state:

```dart
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/models.dart';
import 'status_tag.dart';
```

```dart
    if (pages.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)!.noPagesYet),
      );
    }
```

Replace `frontend/lib/features/documents/document_detail_screen.dart` with:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
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
    final result = await FilePicker.pickFiles(
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
    final documents = ref.read(documentsProvider).value ?? const [];
    final current = documents
        .where((s) => s.document.id == widget.documentId)
        .firstOrNull;
    final controller = TextEditingController(text: current?.document.title ?? '');
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.renameDocument),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.titleLabel),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    final title = newTitle?.trim();
    if (title == null || title.isEmpty) return;
    await ref
        .read(apiClientProvider)
        .updateDocumentTitle(widget.documentId, title);
    ref.invalidate(documentsProvider);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(pagesProvider(widget.documentId));
    final upload = ref.watch(uploadControllerProvider);
    final documents = ref.watch(documentsProvider).value ?? const [];
    final l10n = AppLocalizations.of(context)!;
    final title = documents
            .where((s) => s.document.id == widget.documentId)
            .firstOrNull
            ?.document
            .title ??
        l10n.documentTitle;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(onPressed: () => context.go('/')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: l10n.editTitle,
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
                  label: Text(l10n.uploadImage),
                ),
                const SizedBox(width: 16),
                if (upload.uploading)
                  Text(l10n.uploadingProgress(upload.done, upload.total)),
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
                  Center(child: Text(l10n.failedToLoadPages('$error'))),
              data: (items) => PageGallery(pages: items),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && flutter test test/detail_test.dart`

Expected: PASS for all detail tests (`Upload Image`, status tags `Completed`/`Processing`/`Failed`, rename, upload progress).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/features/documents/document_detail_screen.dart frontend/lib/features/pages/page_gallery.dart frontend/lib/features/pages/status_tag.dart frontend/test/detail_test.dart
git commit -m "feat(frontend): rename upload button and localize detail screen"
```

---

## Task 8: Frontend login + search screen i18n

**Files:**
- Modify: `frontend/lib/features/auth/login_screen.dart`
- Modify: `frontend/lib/features/search/search_results_screen.dart`
- Test: `frontend/test/auth_flow_test.dart`
- Test: `frontend/test/search_test.dart`

- [ ] **Step 1: Write the failing tests**

Add an `IndonesianLocale` test helper to `frontend/test/fakes.dart`:

```dart
import 'dart:ui';

import 'package:ocr_search/core/locale_provider.dart';

/// Forces the app locale to Indonesian in widget tests.
class IndonesianLocale extends LocaleNotifier {
  @override
  Locale build() => const Locale('id');
}
```

In `frontend/test/auth_flow_test.dart`, add `import 'package:ocr_search/core/locale_provider.dart';` at the top and add the test:

```dart
  testWidgets('login screen uses Indonesian when locale is id', (tester) async {
    final fake = FakeApiClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(fake),
        localeProvider.overrideWith(IndonesianLocale.new),
      ],
      child: const OcrSearchApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Masuk dengan Google'), findsOneWidget);
  });
```

In `frontend/test/search_test.dart`, add `import 'package:ocr_search/core/locale_provider.dart';` at the top plus the test:

```dart
  testWidgets('search screen uses Indonesian when locale is id', (tester) async {
    final fake = FakeApiClient()..userEmail = 'bob@gmail.com';
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(fake),
        localeProvider.overrideWith(IndonesianLocale.new),
      ],
      child: const OcrSearchApp(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada hasil. Coba kata lain.'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && flutter test test/auth_flow_test.dart test/search_test.dart`

Expected: FAIL — login still shows `Sign in with Google`, search still shows `No results. Try different terms.`

- [ ] **Step 3: Implement the i18n**

Replace `frontend/lib/features/auth/login_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book, size: 72),
              const SizedBox(height: 16),
              Text(
                l10n.appTitle,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: auth.isLoading ? null : () => _login(context, ref),
                icon: const Icon(Icons.login),
                label: Text(l10n.signInWithGoogle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(authControllerProvider.notifier).login();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.signInFailed)));
    }
  }
}
```

In `frontend/lib/features/search/search_results_screen.dart`, localize the app bar hint, error, and empty state. Add the import at the top:

```dart
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
```

Inside `_SearchResultsScreenState.build`:

```dart
    final results = ref.watch(searchResultsProvider);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.searchHint),
          onChanged: (value) =>
              ref.read(searchResultsProvider.notifier).updateQuery(value),
        ),
      ),
      body: results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(l10n.searchFailed('$error'))),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noResults))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _ResultTile(result: items[index]),
              ),
      ),
    );
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && flutter test test/auth_flow_test.dart test/search_test.dart`

Expected: PASS for both files (English defaults still render the same strings the existing tests assert).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/features/auth/login_screen.dart frontend/lib/features/search/search_results_screen.dart frontend/test/auth_flow_test.dart frontend/test/search_test.dart
git commit -m "feat(frontend): localize login and search screens"
```

---

## Task 9: Frontend `SearchResult.pageImage` model + client

**Files:**
- Modify: `frontend/lib/core/models.dart`
- Modify: `frontend/lib/core/api_client.dart`
- Test: `frontend/test/core_models_test.dart`

- [ ] **Step 1: Update the failing tests**

In `frontend/test/core_models_test.dart`, update the `SearchResult` group:

```dart
  group('SearchResult', () {
    test('parses snake_case fields from /api/search', () {
      final r = SearchResult.fromJson({
        'document_id': 'd1',
        'document_title': 'Manual',
        'page_id': 'p1',
        'page_number': 3,
        'page_image': 'page_abc.png',
        'snippet': 'the <em>needle</em> valve',
      });
      expect(r.documentId, 'd1');
      expect(r.documentTitle, 'Manual');
      expect(r.pageId, 'p1');
      expect(r.pageNumber, 3);
      expect(r.snippet, 'the <em>needle</em> valve');
      expect(
        r.pageImage,
        'http://localhost:8090/api/files/pages/p1/page_abc.png',
      );
    });

    test('defaults missing fields', () {
      final r = SearchResult.fromJson({});
      expect(r.documentId, '');
      expect(r.pageNumber, 0);
      expect(r.snippet, '');
      expect(r.pageImage, '');
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && flutter test test/core_models_test.dart`

Expected: FAIL — compile error (`SearchResult has no field named pageImage`).

- [ ] **Step 3: Implement the model and client changes**

In `frontend/lib/core/models.dart`, replace the `SearchResult` class:

```dart
class SearchResult {
  const SearchResult({
    required this.documentId,
    required this.documentTitle,
    required this.pageId,
    required this.pageNumber,
    required this.snippet,
    this.pageImage = '',
  });

  final String documentId;
  final String documentTitle;
  final String pageId;
  final int pageNumber;
  final String snippet;
  final String pageImage;

  factory SearchResult.fromJson(
    Map<String, dynamic> json, {
    String baseUrl = 'http://localhost:8090',
  }) {
    final pageId = json['page_id'] as String? ?? '';
    final filename = json['page_image'] as String? ?? '';
    return SearchResult(
      documentId: json['document_id'] as String? ?? '',
      documentTitle: json['document_title'] as String? ?? '',
      pageId: pageId,
      pageNumber: json['page_number'] as int? ?? 0,
      snippet: json['snippet'] as String? ?? '',
      pageImage: filename.isEmpty
          ? ''
          : '$baseUrl/api/files/pages/$pageId/$filename',
    );
  }
}
```

In `frontend/lib/core/api_client.dart`, pass the base URL through in `search`:

```dart
  @override
  Future<List<SearchResult>> search(String query) async {
    final data = await _pb.send('/api/search', query: {'q': query});
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map((json) =>
            SearchResult.fromJson(json, baseUrl: _pb.baseURL.toString()))
        .toList();
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && flutter test test/core_models_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/core/models.dart frontend/lib/core/api_client.dart frontend/test/core_models_test.dart
git commit -m "feat(frontend): expose page image on search results"
```

---

## Task 10: Frontend image-first search result cards

**Files:**
- Modify: `frontend/lib/features/search/search_results_screen.dart`
- Test: `frontend/test/search_test.dart`

- [ ] **Step 1: Update the failing test**

In `frontend/test/search_test.dart`, update the first test's fixture and assertions:

```dart
    final fake = FakeApiClient()
      ..userEmail = 'bob@gmail.com'
      ..searchResults = [
        const SearchResult(
          documentId: 'd1',
          documentTitle: 'Manual',
          pageId: 'p1',
          pageNumber: 3,
          snippet: 'the <em>needle</em> valve regulates flow',
          pageImage: 'http://localhost:8090/api/files/pages/p1/page_abc.png',
        ),
      ];
    // ... navigation unchanged ...
    expect(find.text('Manual - page 3'), findsOneWidget);
    expect(find.textContaining('valve regulates flow'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    final imageTop = tester.getTopLeft(find.byType(Image)).dy;
    final titleTop = tester.getTopLeft(find.text('Manual - page 3')).dy;
    expect(imageTop, lessThan(titleTop));
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && flutter test test/search_test.dart`

Expected: FAIL — `find.byType(Image)` finds no widget (result tiles only render an icon).

- [ ] **Step 3: Implement the image-first tile**

In `frontend/lib/features/search/search_results_screen.dart`, replace the `_ResultTile` class:

```dart
class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/documents/${result.documentId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result.pageImage.isNotEmpty)
              Image.network(
                result.pageImage,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox(
                  height: 200,
                  child: Icon(Icons.broken_image_outlined, size: 40),
                ),
              )
            else
              const SizedBox(
                height: 120,
                child: Icon(Icons.image_outlined, size: 40),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.resultTitle(result.documentTitle, result.pageNumber),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  HighlightedText(
                    text: result.snippet,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd frontend && flutter test test/search_test.dart`

Expected: PASS for both search tests (the image renders above the title; the Indonesian empty-state test from Task 8 still passes).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/features/search/search_results_screen.dart frontend/test/search_test.dart
git commit -m "feat(frontend): image-first search result cards"
```

---

## Task 11: Frontend camera capture upload

**Files:**
- Modify: `frontend/pubspec.yaml`
- Modify: `frontend/lib/features/pages/upload_controller.dart`
- Modify: `frontend/lib/features/documents/document_detail_screen.dart`
- Test: `frontend/test/detail_test.dart`

- [ ] **Step 1: Add the `image_picker` dependency**

In `frontend/pubspec.yaml`, add to dependencies:

```yaml
  image_picker: ^1.2.0
```

Run: `cd frontend && flutter pub get`

Expected: exit 0 (network access to pub.dev required the first time).

- [ ] **Step 2: Write the failing tests**

In `frontend/test/detail_test.dart`, add the import and a fake picker:

```dart
import 'package:image_picker/image_picker.dart';
```

```dart
class FakeImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'camera.png');
  }
}
```

Then add two tests inside `main()`:

```dart
  testWidgets('detail shows camera upload button', (tester) async {
    await tester.pumpWidget(testApp(seededFake()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.text('Upload from Camera'), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
  });

  testWidgets('camera capture uploads a page through the controller',
      (tester) async {
    final fake = seededFake();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(fake),
        imagePickerProvider.overrideWithValue(FakeImagePicker()),
      ],
      child: const OcrSearchApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload from Camera'));
    await tester.pumpAndSettle();

    expect(fake.pagesByDocument['d1']!.length, 4);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Manual')),
      listen: false,
    );
    final uploadState = container.read(uploadControllerProvider);
    expect(uploadState.uploading, false);
    expect(uploadState.done, 1);
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd frontend && flutter test test/detail_test.dart`

Expected: FAIL — compile error (`imagePickerProvider is not defined`) and no "Upload from Camera" button.

- [ ] **Step 4: Implement the provider and the camera flow**

In `frontend/lib/features/pages/upload_controller.dart`, add the import and the injectable provider at the top:

```dart
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'pages_controller.dart';

/// Injectable so widget tests can substitute a fake picker.
final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());
```

In `frontend/lib/features/documents/document_detail_screen.dart`, add the import and the capture method:

```dart
import 'package:image_picker/image_picker.dart';
```

```dart
  Future<void> _captureAndUpload() async {
    final file = await ref.read(imagePickerProvider).pickImage(
          source: ImageSource.camera,
          maxWidth: 4096,
          maxHeight: 4096,
          imageQuality: 92,
        );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref
        .read(uploadControllerProvider.notifier)
        .addPages(widget.documentId, [
      UploadInput(bytes: bytes, name: file.name),
    ]);
  }
```

Then add the camera button next to "Upload Image" in the `Row`:

```dart
                FilledButton.icon(
                  onPressed: upload.uploading ? null : _pickAndUpload,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(l10n.uploadImage),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: upload.uploading ? null : _captureAndUpload,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(l10n.uploadFromCamera),
                ),
                const SizedBox(width: 16),
                if (upload.uploading)
                  Text(l10n.uploadingProgress(upload.done, upload.total)),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd frontend && flutter test test/detail_test.dart`

Expected: PASS for all detail tests (button present; fake picker path uploads one page and completes the controller).

- [ ] **Step 6: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock frontend/lib/features/pages/upload_controller.dart frontend/lib/features/documents/document_detail_screen.dart frontend/test/detail_test.dart
git commit -m "feat(frontend): add camera capture upload button"
```

---

## Task 12: Full verification gate

**Files:** none (verification only; commit only if fixes are needed)

- [ ] **Step 1: Backend tests**

Run: `cd backend && go test ./...`

Expected: `ok` for every package (`config`, `ocr`, `fts`, `queue`, `search`, `oauth`, `migrations`).

- [ ] **Step 2: Frontend static analysis**

Run: `cd frontend && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Frontend tests**

Run: `cd frontend && flutter test`

Expected: all tests pass (auth flow, explorer, search, detail, models, api exception, locale provider).

- [ ] **Step 4: Web build**

Run: `cd frontend && flutter build web`

Expected: build completes with no errors.

- [ ] **Step 5: Live docker E2E (optional — requires a real `OCR_API_KEY`)**

1. Put a real key in `.env` (`OCR_API_KEY=sk-or-...`).
2. Run `docker compose up -d --build` and open `http://localhost:8090`.
3. Log in with a whitelisted Google account, create a document, upload a page image (and try the camera button).
4. Run `docker compose exec backend ./backend ocr-worker` (or wait up to 1 minute for the cron tick) and confirm the page status flips to `Completed`.
5. Run a search for a word on the page and confirm the result card shows a full-width thumbnail above the title/snippet.
6. Toggle EN/ID in the explorer app bar and confirm labels flip.

- [ ] **Step 6: Commit any fixes produced by the verification run**

```bash
git add -A
git commit -m "fix: verification gate fixes"
```

If verification was clean and nothing changed, skip this step.
