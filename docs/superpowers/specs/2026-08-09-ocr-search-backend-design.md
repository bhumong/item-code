# OCR Search Backend Design (Phase 1)

**Date:** 2026-08-09
**Status:** Approved
**Parent spec:** [`requirement.md`](../../../requirement.md)

## 1. Purpose & Scope

This spec covers **Phase 1: the Go + PocketBase backend** of the multi-page OCR image document search engine. The Flutter Web frontend is Phase 2 and is explicitly out of scope here; the backend must expose the PocketBase REST API surface the frontend will consume.

Decisions locked during brainstorming:

1. Backend-first sequencing; frontend is a separate sub-project with its own spec/plan.
2. **Embedded Go binary** (Approach A): `main.go` embeds PocketBase; collections are Go migrations; hooks, cron worker, and search route are Go.
3. **OCR provider: OpenRouter** (`https://openrouter.ai/api/v1`), OpenAI-compatible `/chat/completions`, default model a Gemini vision model (env-configurable). DeepSeek's hosted API does not accept image input, so the spec's literal DeepSeek endpoint is replaced while keeping the exact request shape.
4. **Local environment: Docker Compose** with the Go backend + MinIO (S3-compatible storage).
5. **Search: SQLite FTS5** virtual table (`search_fts`) kept in sync by Go hooks; a custom `GET /api/search` route.
6. **Verification: placeholders + mocked tests.** All secrets come from env vars with a committed `.env.example`. The OCR client is tested with `httptest`; live end-to-end runs only when the user supplies a real key.

## 2. Architecture

```
                        Flutter Web  (Phase 2, later)
                              |  HTTPS / PocketBase REST
                              v
   +------------------------------------------------------------+
   |              Go binary embedding PocketBase                |
   |                                                            |
   |  /api/search (FTS5)      hooks: OAuth whitelist,           |
   |  collections CRUD        page -> queue                     |
   |  cron worker (every 1 min)                                 |
   |                                                            |
   |  SQLite data.db                S3 filesystem driver        |
   |   . 4 collections          ----------------------->        |
   |   . FTS5 search_fts                                    +---v-----------+
   |                                                       |  MinIO (S3)    |
   +--------------------------------------------------------+  page images   |
              |                                               +---------------+
              |  POST /api/v1/chat/completions
              |  (OpenRouter, Gemini vision model)
              v
        OpenRouter API
```

## 3. Repo Layout

```
item-code/
|-- backend/                  # Go module, Phase 1
|   |-- main.go               # bootstrap: migrations, hooks, cron, routes
|   |-- internal/
|   |   |-- oauth/            # Google OAuth whitelist hook
|   |   |-- queue/            # page->queue hook + cron worker
|   |   |-- ocr/              # OpenRouter client (env-configurable)
|   |   |-- search/           # FTS5-backed /api/search route
|   |   `-- migrations/       # collection schemas + FTS5 virtual table
|   `-- *_test.go             # Go tests: mocked HTTP + in-memory DB
|-- docker-compose.yml        # backend + minio
`-- .env.example
```

## 4. Data Schema

### 4.1 Collections (exactly as parent spec)

`allowed_users`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | Record ID | Primary Key |
| `email` | Email | Unique, Required |

`documents`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | Record ID | Primary Key |
| `title` | Text | Required |
| `created` | DateTime | Auto-set |
| `updated` | DateTime | Auto-set |

`pages`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | Record ID | Primary Key |
| `document` | Relation | Required, -> `documents.id` |
| `page_number` | Number | Required |
| `image` | File | Required, single file -> S3 |
| `ocr_text` | Text | Optional |
| `status` | Select | Default `pending`; `pending`/`processing`/`completed`/`failed` |
| `created` | DateTime | Auto-set |
| `updated` | DateTime | Auto-set |

`ocr_queue`

| Field | Type | Rules |
| --- | --- | --- |
| `id` | Record ID | Primary Key |
| `page` | Relation | Required, Unique, -> `pages.id` |
| `status` | Select | Default `queued`; `queued`/`in_progress`/`completed`/`failed` |
| `retry_count` | Number | Default 0 |
| `error_log` | Text | Optional |
| `created` | DateTime | Auto-set |
| `updated` | DateTime | Auto-set |

### 4.2 FTS5 Virtual Table (additive)

Created in a migration:

```sql
CREATE VIRTUAL TABLE search_fts USING fts5(
  title,
  ocr_text,
  page_id UNINDEXED,
  document_id UNINDEXED,
  page_number UNINDEXED
);
```

**Search semantics:** one row per page, with the parent document title embedded. Documents with zero pages are not searchable (explicit decision). Rows are kept in sync by hooks (see 5.3), not by DB triggers.

## 5. Backend Components

### 5.1 Bootstrap (`main.go`)

`pocketbase.NewWithConfig(...)`; registers in order: migrations, hooks, cron job, custom route. Reads all config from env vars (see 6).

### 5.2 OAuth Whitelist Hook

`OnRecordAuthWithOAuth2Request`: extract email from provider claims; query `allowed_users` by email; if missing, abort auth with a 403 error; otherwise allow.

### 5.3 Record Hooks

| Hook | Effect |
| --- | --- |
| `OnRecordAfterCreateSuccess("pages")` | Insert `ocr_queue` row (`page` = new id, `status` = `queued`); insert `search_fts` row |
| `OnRecordAfterUpdateSuccess("pages")` | Upsert `search_fts` row (ocr_text change) |
| `OnRecordAfterUpdateSuccess("documents")` | Refresh `search_fts` rows for its pages (title change) |

### 5.4 Cron Worker

Native PocketBase cron, `*/1 * * * *`:

1. Fetch up to `OCR_CONCURRENCY` rows from `ocr_queue` where `status = "queued"`, oldest first.
2. Per item: set `ocr_queue.status = "in_progress"`, `pages.status = "processing"`.
3. Read the page image bytes from S3 via the PocketBase file API.
4. `POST {OCR_BASE_URL}/chat/completions` with an OpenAI-compatible body:
   - `model` = `OCR_MODEL`
   - user message: `{ type: "text", text: "Extract all legible text from this image accurately." }` plus `{ type: "image_url", image_url: { url: "data:<mime>;base64,<bytes>" } }`
5. Success: save `choices[0].message.content` to `pages.ocr_text`; `pages.status = "completed"`; `ocr_queue.status = "completed"`.
6. Transient error/timeout: `retry_count++`; `ocr_queue.status` back to `"queued"`; `pages.status` back to `"pending"`; write error detail to `error_log`.
7. Final failure (`retry_count >= OCR_RETRY_MAX`): `ocr_queue.status = "failed"`; `pages.status = "failed"`; `error_log` set.

HTTP client timeout configurable (default 120s) so slow vision calls cannot wedge a tick.

### 5.5 Search Route

`GET /api/search?q=<terms>`:

1. Sanitize query: quote FTS5 special characters term-by-term.
2. `SELECT page_id, document_id, page_number, title, snippet(search_fts, ...) FROM search_fts WHERE search_fts MATCH ? ORDER BY rank LIMIT 50`.
3. Return JSON: `[{ document_id, document_title, page_id, page_number, snippet }]`; `snippet()` wraps matches in `<em>…</em>` for frontend highlighting.

## 6. Configuration (`.env.example`, all placeholders)

| Variable | Default | Purpose |
| --- | --- | --- |
| `PB_DATA_DIR` | `./pb_data` | SQLite + S3 mount |
| `S3_ENDPOINT` | `http://minio:9000` | MinIO endpoint |
| `S3_BUCKET` | `pages` | Bucket name |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | placeholder | MinIO credentials |
| `S3_REGION` | `us-east-1` | Region |
| `OCR_BASE_URL` | `https://openrouter.ai/api/v1` | OpenRouter base |
| `OCR_API_KEY` | placeholder | OpenRouter key |
| `OCR_MODEL` | `google/gemini-2.5-flash` | Vision model |
| `OCR_CONCURRENCY` | `5` | Items per cron tick |
| `OCR_RETRY_MAX` | `3` | Retries before `failed` |
| `OCR_TIMEOUT` | `120s` | HTTP timeout per call |
| `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` | placeholder | Google OAuth |

## 7. Testing Strategy

| Area | Approach |
| --- | --- |
| OCR client | `httptest` mock server: request payload shape, success parsing, 4xx/5xx, timeout |
| Hooks | In-memory PocketBase: page create -> queue row; whitelist allow/deny |
| Cron worker | Mocked OCR client + in-memory DB: success, retry, final-failure paths |
| Search | Seeded FTS5 rows: match, no-match, special-character queries |
| Live check | docker-compose: placeholder key fails gracefully into `error_log`; real key completes end to end |

## 8. Out of Scope (Phase 2)

- Flutter Web frontend (login, explorer, gallery, search UI)
- Deployment/hosting concerns beyond local docker-compose
