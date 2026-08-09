# OCR Search Phase 3 Design (FE + BE Improvements)

**Date:** 2026-08-09
**Status:** Approved
**Parent spec:** [`requirement.md`](../../../requirement.md)

## 1. Purpose & Scope

Phase 3 applies six targeted improvements on top of the merged Phase 1 (backend) and Phase 2 (frontend):

1. Rename the detail-screen upload button from "Add Pages" to "Upload Image".
2. Add English + Indonesian localization (standard Flutter i18n with ARB files, browser-locale auto-detect plus a manual EN/ID toggle).
3. Search results become image-first: a large full-width page thumbnail above the title/page/snippet.
4. Set the OCR request `temperature` to 0 (Gemini 2.5 supports 0-2; 0 = deterministic). Configurable via env, default 0.
5. Replace the OCR prompt with a high-precision OCR system prompt (verbatim transcription rules).
6. Add an "Upload from Camera" button (web camera capture via `image_picker`, desktop falls back to a file dialog).

Decisions locked during brainstorming:

- One combined plan (Approach A): single branch/PR covering FE + BE.
- i18n: `flutter_localizations` + `intl` + ARB files (standard codegen), locale toggled by a Riverpod `localeProvider`.
- Search result layout: full-width image on top, text below (option 1).
- Camera: `image_picker` with `ImageSource.camera` (option 1).
- Temperature: env-configurable, default 0.

## 2. Backend Changes

### 2.1 OCR temperature

- `internal/config`: add `OCR_TEMPERATURE` env var (`float64`, default `0`); add `Temperature float64` to `OCRConfig`; add `.env.example` entry.
- `internal/ocr`: add `Temperature float64` to `Config`; add `temperature` field to `chatCompletionRequest` (`json:"temperature"`); `NewClient` keeps zero value as the default (0).

### 2.2 OCR prompt

- Replace `defaultPrompt` with the high-precision OCR prompt (see below), sent as a `system`-role message; the user message carries only the image.
- The prompt text (exactly):

```
You are a high-precision Optical Character Recognition (OCR) engine. Your sole task is to transcribe all readable text from the provided image exactly as it appears.

## Rules:
1. Transcribe all text verbatim. Preserve original casing, punctuation, spelling, and line breaks.
2. Do NOT convert or format the output into Markdown, JSON, HTML, bullet lists, or tables.
3. Do NOT fix typos, correct grammar, or alter words.
4. Mark illegible or completely cut-off text as [unclear].
5. Output ONLY the raw transcribed text. Do NOT include any introductory or concluding comments, greetings, or meta-explanations.
```

### 2.3 Search results carry the page image

- New migration `003_search_fts_image`: recreate `search_fts` with an added `image UNINDEXED` column (FTS5 virtual tables cannot be altered in place; the migration drops and recreates the table so existing dev DBs upgrade cleanly). Note: existing rows are re-indexed by the sync hooks on the next page update, and the migration itself seeds nothing.
- `internal/fts.UpsertPage`: store `page.GetString("image")` in the `image` column.
- `internal/fts.Search` / `SearchResult`: select and expose `image` as `page_image` in the JSON response.
- Frontend `SearchResult` model gains `pageImage` and builds the file URL the same way the gallery does (`$baseUrl/api/files/pages/$pageId/$pageImage`).

## 3. Frontend Changes

### 3.1 Rename

- Detail screen: "Add Pages" -> "Upload Image"; empty-gallery hint updated ("No pages yet. Use Upload Image.").

### 3.2 Internationalization (EN + ID)

- Dependencies: `flutter_localizations`, `intl`.
- `l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-localization-file: app_localizations.dart`.
- `lib/l10n/app_en.arb` + `app_id.arb` covering all UI strings: login (title, button, toasts), explorer (title, search hint, empty state, FAB tooltip), detail (upload button, camera button, edit, rename dialog, upload progress, empty gallery), search (hint, empty/error, "page N"), status tags (Pending/Processing/Completed/Failed).
- `localeProvider` (`Notifier<Locale>`): initial value from `PlatformDispatcher.instance.locale` (id -> `Locale('id')`, else `Locale('en')`); manual toggle in the explorer app bar (EN | ID).
- `MaterialApp.router`: `localizationsDelegates` (AppLocalizations + global delegates), `supportedLocales: [en, id]`, `locale` from the provider.

### 3.3 Search result layout

- Result card: full-width `Image.network` of the page image URL at the top (reusing the existing error builder), then document title, "page N", and the highlighted snippet below. Tap still opens the document.

### 3.4 Camera upload

- Dependency: `image_picker`.
- Detail screen: a second button next to "Upload Image" (camera icon, label from i18n). Captures a single image via `ImagePicker().pickImage(source: ImageSource.camera)`, converts to `UploadInput`, and uploads through the existing `uploadControllerProvider` (progress + invalidation unchanged).

## 4. Testing Strategy

| Area | Tests |
| --- | --- |
| OCR client | request shape includes `temperature: 0` and the system prompt; temperature serialization (e.g. 0.5) |
| Config | `OCR_TEMPERATURE` default + override |
| FTS | `UpsertPage` stores image; `Search` returns `page_image` |
| FE rename | detail shows "Upload Image" |
| FE i18n | switching locale flips a label to Indonesian |
| FE search layout | result renders image widget above title + snippet |
| FE camera | camera button present and wired to the upload controller (native picker not invoked in tests) |

**Verification gate:** `go test ./...`; `flutter analyze` + `flutter test` + `flutter build web`; live docker E2E (upload -> OCR with new prompt/temperature -> image-first search).

## 5. Out of Scope

- Backend prompt/response schema beyond the above.
- Additional locales beyond EN/ID.
- Native (non-web) camera behavior beyond the browser capture fallback.
