# OCR Search Backend Implementation Plan (Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Go + PocketBase backend for the multi-page OCR image document search engine described in [`docs/superpowers/specs/2026-08-09-ocr-search-backend-design.md`](../specs/2026-08-09-ocr-search-backend-design.md).

**Architecture:** A single Go binary embeds PocketBase v0.39.7. The four collections (`allowed_users`, `documents`, `pages`, `ocr_queue`) are defined in Go migrations, plus an FTS5 virtual table (`search_fts`) for full-text search. Go hooks enforce the Google OAuth whitelist, create `ocr_queue` entries on page upload, and keep `search_fts` in sync. A cron worker (every 1 minute) processes queued pages by sending each image to OpenRouter (`/chat/completions`, Gemini vision model) with retry counting and persistent status. A custom `GET /api/search` route queries FTS5 with rank ordering and `<em>`-wrapped snippets. All configuration comes from env vars; tests use `httptest` mocks and in-memory PocketBase test apps.

**Tech Stack:** Go 1.26, `github.com/pocketbase/pocketbase v0.39.7` (embedded), SQLite FTS5 (via modernc), docker compose + MinIO (S3-compatible storage), OpenRouter chat/completions API.

**Spec link:** [design spec](../specs/2026-08-09-ocr-search-backend-design.md)

---

## Repository Layout (target state)

```
item-code/
|-- backend/                      # Go module (module name: ocrsearch/backend)
|   |-- go.mod / go.sum
|   |-- Dockerfile
|   |-- main.go                   # bootstrap: settings, hooks, routes, cron, CLI
|   |-- internal/
|   |   |-- config/               # env parsing + ApplySettings (S3, OAuth, meta)
|   |   |-- migrations/           # collections + FTS5 table (registered via init())
|   |   |-- ocr/                  # OpenRouter chat/completions client
|   |   |-- fts/                  # FTS5 sync (UpsertPage/RefreshDocument) + Search + hooks
|   |   |-- queue/                # page->queue hook + cron worker ProcessBatch
|   |   |-- oauth/                # Google OAuth whitelist hook + IsAllowed
|   |   `-- search/               # GET /api/search route
|-- docker-compose.yml            # backend + minio + minio-init
|-- .env.example
`-- .gitignore
```

Package dependency direction (no cycles): `ocr` -> nothing; `fts` -> core; `queue` -> `fts`, `ocr`; `oauth` -> core; `search` -> `fts`; `config` -> core; `migrations` -> core; `main` -> all.

**Conventions used throughout:**
- `core` = `github.com/pocketbase/pocketbase/core`
- `dbx` = `github.com/pocketbase/dbx`
- Every test that needs collections imports `_ "ocrsearch/backend/internal/migrations"` so the migrations register before `tests.NewTestApp()` runs.
- Git commands run from the repo root unless the step says otherwise; `go` commands run from `backend/`.

---

## Task 0: Scaffold Go Module, Docker Setup, and Placeholder Entrypoint

**Files:**
- Create: `backend/go.mod`, `backend/go.sum`
- Create: `backend/main.go`
- Create: `backend/Dockerfile`
- Create: `docker-compose.yml`, `.env.example`, `.gitignore`

- [ ] **Step 1: Initialize the Go module and pin PocketBase**

Run (network required):

```bash
cd backend
go mod init ocrsearch/backend
go get github.com/pocketbase/pocketbase@v0.39.7
```

Expected: `go: added github.com/pocketbase/pocketbase v0.39.7` (plus transitive deps).

- [ ] **Step 2: Create the minimal entrypoint**

`backend/main.go`:

```go
package main

import (
	"log"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
	"github.com/pocketbase/pocketbase/tools/osutils"
)

func main() {
	app := pocketbase.New()

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		Automigrate: osutils.IsProbablyGoRun(),
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
```

- [ ] **Step 3: Create the Dockerfile**

`backend/Dockerfile`:

```dockerfile
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app/backend .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=build /app/backend .
EXPOSE 8090
ENTRYPOINT ["/app/backend", "serve", "--http=0.0.0.0:8090"]
```

- [ ] **Step 4: Create docker-compose.yml**

`docker-compose.yml`:

```yaml
services:
  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${S3_ACCESS_KEY:-minioadmin}
      MINIO_ROOT_PASSWORD: ${S3_SECRET_KEY:-minioadmin}
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio-data:/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 5s
      timeout: 5s
      retries: 20

  minio-init:
    image: minio/mc
    depends_on:
      minio:
        condition: service_healthy
    environment:
      MC_HOST_local: http://${S3_ACCESS_KEY:-minioadmin}:${S3_SECRET_KEY:-minioadmin}@minio:9000
    entrypoint: ["/bin/sh", "-c", "mc mb --ignore-existing local/pages"]

  backend:
    build:
      context: ./backend
    env_file:
      - .env
    environment:
      PB_DATA_DIR: /pb_data
      S3_ENDPOINT: http://minio:9000
    ports:
      - "8090:8090"
    volumes:
      - pb-data:/pb_data
    depends_on:
      minio:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:8090/api/health"]
      interval: 10s
      timeout: 5s
      retries: 12

volumes:
  minio-data:
  pb-data:
```

- [ ] **Step 5: Create .env.example**

`.env.example`:

```bash
# PocketBase
PB_DATA_DIR=./pb_data
PB_PUBLIC_URL=http://localhost:8090

# S3 / MinIO
S3_ENDPOINT=http://localhost:9000
S3_BUCKET=pages
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_REGION=us-east-1

# OCR (OpenRouter)
OCR_BASE_URL=https://openrouter.ai/api/v1
OCR_API_KEY=sk-or-placeholder
OCR_MODEL=google/gemini-2.5-flash
OCR_CONCURRENCY=5
OCR_RETRY_MAX=3
OCR_TIMEOUT=120s

# Google OAuth (leave empty to disable Google login until real credentials exist)
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
```

- [ ] **Step 6: Create .gitignore**

`.gitignore`:

```gitignore
.env
pb_data/
backend/backend
```

- [ ] **Step 7: Verify it builds and compose config is valid**

Run:

```bash
cd backend
go mod tidy
go build ./...
cd ..
docker compose config >/dev/null
```

Expected: `go build` exits 0 (no output), `docker compose config` exits 0.

- [ ] **Step 8: Commit**

Run from the repo root:

```bash
git add backend/ .env.example .gitignore docker-compose.yml
git commit -m "chore: scaffold ocr search backend module and docker compose"
```

---

## Task 1: Config Package (env parsing + settings application)

**Files:**
- Create: `backend/internal/config/config.go`
- Create: `backend/internal/config/config_test.go`

- [ ] **Step 1: Write the failing test**

`backend/internal/config/config_test.go`:

```go
package config

import (
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/tests"
)

func TestLoadDefaults(t *testing.T) {
	t.Setenv("S3_ENDPOINT", "")
	t.Setenv("OCR_API_KEY", "")
	t.Setenv("OCR_MODEL", "")
	t.Setenv("OCR_CONCURRENCY", "")
	t.Setenv("OCR_RETRY_MAX", "")
	t.Setenv("OCR_TIMEOUT", "")
	t.Setenv("GOOGLE_OAUTH_CLIENT_ID", "")
	t.Setenv("GOOGLE_OAUTH_CLIENT_SECRET", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if cfg.DataDir != "./pb_data" {
		t.Errorf("DataDir = %q, want %q", cfg.DataDir, "./pb_data")
	}
	if cfg.S3.Enabled {
		t.Error("S3.Enabled = true, want false when S3_ENDPOINT unset")
	}
	if cfg.OCR.BaseURL != "https://openrouter.ai/api/v1" {
		t.Errorf("OCR.BaseURL = %q, want default", cfg.OCR.BaseURL)
	}
	if cfg.OCR.Model != "google/gemini-2.5-flash" {
		t.Errorf("OCR.Model = %q, want default", cfg.OCR.Model)
	}
	if cfg.OCR.Concurrency != 5 {
		t.Errorf("OCR.Concurrency = %d, want 5", cfg.OCR.Concurrency)
	}
	if cfg.OCR.RetryMax != 3 {
		t.Errorf("OCR.RetryMax = %d, want 3", cfg.OCR.RetryMax)
	}
	if cfg.OCR.Timeout != 120*time.Second {
		t.Errorf("OCR.Timeout = %v, want 120s", cfg.OCR.Timeout)
	}
}

func TestLoadOverrides(t *testing.T) {
	t.Setenv("PB_DATA_DIR", "/tmp/pb")
	t.Setenv("S3_ENDPOINT", "http://localhost:9000")
	t.Setenv("S3_ACCESS_KEY", "minioadmin")
	t.Setenv("S3_SECRET_KEY", "minioadmin")
	t.Setenv("OCR_API_KEY", "sk-test")
	t.Setenv("OCR_MODEL", "google/gemini-3")
	t.Setenv("OCR_CONCURRENCY", "7")
	t.Setenv("OCR_TIMEOUT", "30s")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if cfg.DataDir != "/tmp/pb" {
		t.Errorf("DataDir = %q, want /tmp/pb", cfg.DataDir)
	}
	if !cfg.S3.Enabled {
		t.Error("S3.Enabled = false, want true when S3_ENDPOINT set")
	}
	if cfg.S3.Endpoint != "http://localhost:9000" {
		t.Errorf("S3.Endpoint = %q", cfg.S3.Endpoint)
	}
	if cfg.S3.Bucket != "pages" {
		t.Errorf("S3.Bucket = %q, want pages", cfg.S3.Bucket)
	}
	if cfg.OCR.APIKey != "sk-test" {
		t.Errorf("OCR.APIKey = %q", cfg.OCR.APIKey)
	}
	if cfg.OCR.Model != "google/gemini-3" {
		t.Errorf("OCR.Model = %q", cfg.OCR.Model)
	}
	if cfg.OCR.Concurrency != 7 {
		t.Errorf("OCR.Concurrency = %d, want 7", cfg.OCR.Concurrency)
	}
	if cfg.OCR.Timeout != 30*time.Second {
		t.Errorf("OCR.Timeout = %v, want 30s", cfg.OCR.Timeout)
	}
}

func TestLoadErrorsWhenS3EnabledWithoutKeys(t *testing.T) {
	t.Setenv("S3_ENDPOINT", "http://localhost:9000")
	t.Setenv("S3_ACCESS_KEY", "")
	if _, err := Load(); err == nil {
		t.Fatal("Load() = nil error, want error when S3 enabled without access key")
	}
}

func TestApplySettings(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	defer app.Cleanup()

	cfg := Config{
		S3: S3Config{
			Enabled:        true,
			Endpoint:       "http://localhost:9000",
			Bucket:         "pages",
			AccessKey:      "minioadmin",
			SecretKey:      "minioadmin",
			Region:         "us-east-1",
			ForcePathStyle: true,
		},
		OAuth: OAuthConfig{
			GoogleClientID:     "client-id",
			GoogleClientSecret: "client-secret",
		},
	}

	if err := ApplySettings(app, cfg); err != nil {
		t.Fatalf("ApplySettings() error: %v", err)
	}

	settings := app.Settings()
	if !settings.S3.Enabled {
		t.Error("settings.S3.Enabled = false, want true")
	}
	if settings.S3.Endpoint != "http://localhost:9000" {
		t.Errorf("settings.S3.Endpoint = %q", settings.S3.Endpoint)
	}
	if settings.S3.AccessKey != "minioadmin" {
		t.Errorf("settings.S3.AccessKey = %q", settings.S3.AccessKey)
	}
	if settings.Meta.AppName != "OCR Search" {
		t.Errorf("settings.Meta.AppName = %q, want OCR Search", settings.Meta.AppName)
	}

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatalf("find users collection: %v", err)
	}
	if !users.OAuth2.Enabled {
		t.Error("users.OAuth2.Enabled = false, want true")
	}
	if len(users.OAuth2.Providers) != 1 {
		t.Fatalf("users.OAuth2.Providers len = %d, want 1", len(users.OAuth2.Providers))
	}
	if users.OAuth2.Providers[0].Name != "google" {
		t.Errorf("provider name = %q, want google", users.OAuth2.Providers[0].Name)
	}
	if users.OAuth2.Providers[0].ClientId != "client-id" {
		t.Errorf("provider clientId = %q", users.OAuth2.Providers[0].ClientId)
	}
}

func TestApplySettingsSkipsOAuthWhenEnvEmpty(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	defer app.Cleanup()

	cfg := Config{}
	if err := ApplySettings(app, cfg); err != nil {
		t.Fatalf("ApplySettings() error: %v", err)
	}

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatalf("find users collection: %v", err)
	}
	if users.OAuth2.Enabled {
		t.Error("users.OAuth2.Enabled = true, want false when no OAuth env set")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
go test ./internal/config/ -v
```

Expected: FAIL — package does not compile (`undefined: Load`, `undefined: ApplySettings`, `undefined: Config`, ...).

- [ ] **Step 3: Write the implementation**

`backend/internal/config/config.go`:

```go
package config

import (
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

type Config struct {
	DataDir string

	S3    S3Config
	OCR   OCRConfig
	OAuth OAuthConfig
}

type S3Config struct {
	Enabled        bool
	Endpoint       string
	Bucket         string
	AccessKey      string
	SecretKey      string
	Region         string
	ForcePathStyle bool
}

type OCRConfig struct {
	BaseURL     string
	APIKey      string
	Model       string
	Concurrency int
	RetryMax    int
	Timeout     time.Duration
}

type OAuthConfig struct {
	GoogleClientID     string
	GoogleClientSecret string
}

func Load() (Config, error) {
	cfg := Config{
		DataDir: getenv("PB_DATA_DIR", "./pb_data"),
		S3: S3Config{
			Enabled:        os.Getenv("S3_ENDPOINT") != "",
			Endpoint:       os.Getenv("S3_ENDPOINT"),
			Bucket:         getenv("S3_BUCKET", "pages"),
			AccessKey:      os.Getenv("S3_ACCESS_KEY"),
			SecretKey:      os.Getenv("S3_SECRET_KEY"),
			Region:         getenv("S3_REGION", "us-east-1"),
			ForcePathStyle: true,
		},
		OCR: OCRConfig{
			BaseURL:     getenv("OCR_BASE_URL", "https://openrouter.ai/api/v1"),
			APIKey:      os.Getenv("OCR_API_KEY"),
			Model:       getenv("OCR_MODEL", "google/gemini-2.5-flash"),
			Concurrency: getenvInt("OCR_CONCURRENCY", 5),
			RetryMax:    getenvInt("OCR_RETRY_MAX", 3),
			Timeout:     getenvDuration("OCR_TIMEOUT", 120*time.Second),
		},
		OAuth: OAuthConfig{
			GoogleClientID:     os.Getenv("GOOGLE_OAUTH_CLIENT_ID"),
			GoogleClientSecret: os.Getenv("GOOGLE_OAUTH_CLIENT_SECRET"),
		},
	}

	if cfg.S3.Enabled && cfg.S3.AccessKey == "" {
		return cfg, fmt.Errorf("S3_ENDPOINT is set but S3_ACCESS_KEY is empty")
	}

	return cfg, nil
}

// ApplySettings persists env-driven PocketBase settings (S3 storage, meta, and
// the Google OAuth2 provider on the users auth collection). It is safe to call
// on every boot because it is idempotent.
func ApplySettings(app core.App, cfg Config) error {
	settings := app.Settings()
	settings.Meta.AppName = "OCR Search"
	settings.Meta.AppURL = getenv("PB_PUBLIC_URL", "http://localhost:8090")

	if cfg.S3.Enabled {
		settings.S3.Enabled = true
		settings.S3.Endpoint = cfg.S3.Endpoint
		settings.S3.Bucket = cfg.S3.Bucket
		settings.S3.Region = cfg.S3.Region
		settings.S3.AccessKey = cfg.S3.AccessKey
		settings.S3.Secret = cfg.S3.SecretKey
		settings.S3.ForcePathStyle = cfg.S3.ForcePathStyle
	} else {
		settings.S3.Enabled = false
	}

	if err := app.Save(settings); err != nil {
		return fmt.Errorf("failed to save settings: %w", err)
	}

	if cfg.OAuth.GoogleClientID != "" && cfg.OAuth.GoogleClientSecret != "" {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return fmt.Errorf("failed to find users collection: %w", err)
		}
		users.OAuth2.Enabled = true
		users.OAuth2.Providers = []core.OAuth2ProviderConfig{{
			Name:         "google",
			ClientId:     cfg.OAuth.GoogleClientID,
			ClientSecret: cfg.OAuth.GoogleClientSecret,
		}}
		if err := app.Save(users); err != nil {
			return fmt.Errorf("failed to save users oauth config: %w", err)
		}
	}

	return nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getenvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func getenvDuration(key string, fallback time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return fallback
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
go test ./internal/config/ -v
```

Expected: `ok ocrsearch/backend/internal/config` with all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/config/
git commit -m "feat: add env-based config loading and settings application"
```

---

## Task 2: Migrations (Collections + FTS5 Table)

**Files:**
- Create: `backend/internal/migrations/001_collections.go`
- Create: `backend/internal/migrations/002_search_fts.go`
- Create: `backend/internal/migrations/migrations_test.go`

- [ ] **Step 1: Write the failing test**

`backend/internal/migrations/migrations_test.go`:

```go
package migrations_test

import (
	"testing"

	"github.com/pocketbase/pocketbase/tests"

	_ "ocrsearch/backend/internal/migrations"
)

func TestCollectionsCreated(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	defer app.Cleanup()

	for _, name := range []string{"allowed_users", "documents", "pages", "ocr_queue"} {
		if _, err := app.FindCollectionByNameOrId(name); err != nil {
			t.Errorf("collection %q missing: %v", name, err)
		}
	}

	pages, err := app.FindCollectionByNameOrId("pages")
	if err != nil {
		t.Fatal(err)
	}
	for _, fname := range []string{"document", "page_number", "image", "ocr_text", "status"} {
		if pages.Fields.GetByName(fname) == nil {
			t.Errorf("pages field %q missing", fname)
		}
	}

	queue, err := app.FindCollectionByNameOrId("ocr_queue")
	if err != nil {
		t.Fatal(err)
	}
	for _, fname := range []string{"page", "status", "retry_count", "error_log"} {
		if queue.Fields.GetByName(fname) == nil {
			t.Errorf("ocr_queue field %q missing", fname)
		}
	}

	allowed, err := app.FindCollectionByNameOrId("allowed_users")
	if err != nil {
		t.Fatal(err)
	}
	if allowed.Fields.GetByName("email") == nil {
		t.Error("allowed_users email field missing")
	}
}

func TestSearchFTSExists(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	defer app.Cleanup()

	rows, err := app.DB().NewQuery("SELECT count(*) FROM search_fts").Rows()
	if err != nil {
		t.Fatalf("search_fts query error: %v", err)
	}
	defer rows.Close()
	if !rows.Next() {
		t.Fatal("search_fts has no rows")
	}
	var n int
	if err := rows.Scan(&n); err != nil {
		t.Fatalf("scan count: %v", err)
	}
	if n != 0 {
		t.Errorf("search_fts count = %d, want 0", n)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
go test ./internal/migrations/ -v
```

Expected: FAIL — `collection "allowed_users" missing: sql: no rows in result set`.

- [ ] **Step 3: Write the collections migration**

`backend/internal/migrations/001_collections.go`:

```go
package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

func init() {
	migrations.Register(createCollections, deleteCollections)
}

func createCollections(app core.App) error {
	authRule := "@request.auth.id != ''"

	allowedUsers := core.NewBaseCollection("allowed_users")
	allowedUsers.Fields.Add(&core.EmailField{Name: "email", Required: true})
	allowedUsers.AddIndex("idx_allowed_users_email", true, "email", "")
	if err := app.Save(allowedUsers); err != nil {
		return err
	}

	documents := core.NewBaseCollection("documents")
	documents.Fields.Add(&core.TextField{Name: "title", Required: true, Max: 500})
	documents.ListRule = types.Pointer(authRule)
	documents.ViewRule = types.Pointer(authRule)
	documents.CreateRule = types.Pointer(authRule)
	documents.UpdateRule = types.Pointer(authRule)
	documents.DeleteRule = types.Pointer(authRule)
	if err := app.Save(documents); err != nil {
		return err
	}

	pages := core.NewBaseCollection("pages")
	pages.Fields.Add(&core.RelationField{
		Name:          "document",
		CollectionId:  documents.Id,
		MaxSelect:     1,
		Required:      true,
		CascadeDelete: true,
	})
	pages.Fields.Add(&core.NumberField{Name: "page_number", OnlyInt: true, Required: true})
	pages.Fields.Add(&core.FileField{
		Name:      "image",
		Required:  true,
		MaxSelect: 1,
		MimeTypes: []string{"image/jpeg", "image/png", "image/webp", "image/gif"},
	})
	pages.Fields.Add(&core.TextField{Name: "ocr_text"})
	pages.Fields.Add(&core.SelectField{
		Name:      "status",
		Required:  true,
		MaxSelect: 1,
		Values:    []string{"pending", "processing", "completed", "failed"},
	})
	pages.ListRule = types.Pointer(authRule)
	pages.ViewRule = types.Pointer(authRule)
	pages.CreateRule = types.Pointer(authRule)
	pages.UpdateRule = types.Pointer(authRule)
	pages.DeleteRule = types.Pointer(authRule)
	if err := app.Save(pages); err != nil {
		return err
	}

	queue := core.NewBaseCollection("ocr_queue")
	queue.Fields.Add(&core.RelationField{
		Name:          "page",
		CollectionId:  pages.Id,
		MaxSelect:     1,
		Required:      true,
		CascadeDelete: true,
	})
	queue.Fields.Add(&core.SelectField{
		Name:      "status",
		Required:  true,
		MaxSelect: 1,
		Values:    []string{"queued", "in_progress", "completed", "failed"},
	})
	queue.Fields.Add(&core.NumberField{Name: "retry_count", OnlyInt: true})
	queue.Fields.Add(&core.TextField{Name: "error_log"})
	queue.AddIndex("idx_ocr_queue_page", true, "page", "")

	return app.Save(queue)
}

func deleteCollections(app core.App) error {
	for _, name := range []string{"ocr_queue", "pages", "documents", "allowed_users"} {
		col, err := app.FindCollectionByNameOrId(name)
		if err != nil {
			continue
		}
		if err := app.Delete(col); err != nil {
			return err
		}
	}
	return nil
}
```

- [ ] **Step 4: Write the FTS5 migration**

`backend/internal/migrations/002_search_fts.go`:

```go
package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

func init() {
	migrations.Register(createSearchFTS, dropSearchFTS)
}

func createSearchFTS(app core.App) error {
	_, err := app.DB().NewQuery(`
		CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
			title,
			ocr_text,
			page_id UNINDEXED,
			document_id UNINDEXED,
			page_number UNINDEXED
		)
	`).Execute()
	return err
}

func dropSearchFTS(app core.App) error {
	_, err := app.DB().NewQuery(`DROP TABLE IF EXISTS search_fts`).Execute()
	return err
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run:

```bash
go test ./internal/migrations/ -v
```

Expected: `ok ocrsearch/backend/internal/migrations` — both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/migrations/
git commit -m "feat: add collections and FTS5 migrations"
```

---

## Task 3: OCR Client (OpenRouter chat/completions)

**Files:**
- Create: `backend/internal/ocr/ocr.go`
- Create: `backend/internal/ocr/ocr_test.go`

- [ ] **Step 1: Write the failing test**

`backend/internal/ocr/ocr_test.go`:

```go
package ocr

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestExtractTextSuccess(t *testing.T) {
	var gotBody chatCompletionRequest
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer sk-test" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer sk-test")
		}
		if ct := r.Header.Get("Content-Type"); ct != "application/json" {
			t.Errorf("Content-Type = %q, want application/json", ct)
		}
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"Extracted page text"}}]}`))
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "sk-test", Model: "google/gemini-test"})
	text, err := c.ExtractText(context.Background(), []byte("fake-image-bytes"), "image/png")
	if err != nil {
		t.Fatalf("ExtractText() error: %v", err)
	}
	if text != "Extracted page text" {
		t.Errorf("text = %q, want %q", text, "Extracted page text")
	}

	if gotBody.Model != "google/gemini-test" {
		t.Errorf("request model = %q", gotBody.Model)
	}
	if len(gotBody.Messages) != 1 {
		t.Fatalf("messages len = %d, want 1", len(gotBody.Messages))
	}
	msg := gotBody.Messages[0]
	if msg.Role != "user" {
		t.Errorf("role = %q, want user", msg.Role)
	}
	if len(msg.Content) != 2 {
		t.Fatalf("content parts len = %d, want 2", len(msg.Content))
	}
	if msg.Content[0].Type != "text" || msg.Content[0].Text == "" {
		t.Errorf("text part = %+v, want non-empty prompt", msg.Content[0])
	}
	if msg.Content[1].Type != "image_url" || msg.Content[1].ImageURL == nil {
		t.Fatalf("image part = %+v, want image_url", msg.Content[1])
	}
	wantPrefix := "data:image/png;base64,"
	if !strings.HasPrefix(msg.Content[1].ImageURL.URL, wantPrefix) {
		t.Errorf("image url = %q, want prefix %q", msg.Content[1].ImageURL.URL, wantPrefix)
	}
}

func TestExtractTextHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "bad", Model: "m"})
	if _, err := c.ExtractText(context.Background(), []byte("x"), "image/png"); err == nil {
		t.Fatal("ExtractText() = nil error, want error on 401")
	}
}

func TestExtractTextEmptyChoices(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[]}`))
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "k", Model: "m"})
	if _, err := c.ExtractText(context.Background(), []byte("x"), "image/png"); err == nil {
		t.Fatal("ExtractText() = nil error, want error when no choices")
	}
}

func TestExtractTextTimeout(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(300 * time.Millisecond)
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "k", Model: "m", Timeout: 50 * time.Millisecond})
	if _, err := c.ExtractText(context.Background(), []byte("x"), "image/png"); err == nil {
		t.Fatal("ExtractText() = nil error, want timeout error")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
go test ./internal/ocr/ -v
```

Expected: FAIL — package does not compile (`undefined: Config`, `undefined: NewClient`, `undefined: chatCompletionRequest`, `undefined: ExtractText`).

- [ ] **Step 3: Write the implementation**

`backend/internal/ocr/ocr.go`:

```go
package ocr

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const defaultPrompt = "Extract all legible text from this image accurately."

type Config struct {
	BaseURL string
	APIKey  string
	Model   string
	Timeout time.Duration
}

type Client struct {
	baseURL string
	apiKey  string
	model   string
	http    *http.Client
}

type ContentPart struct {
	Type     string    `json:"type"`
	Text     string    `json:"text,omitempty"`
	ImageURL *ImageURL `json:"image_url,omitempty"`
}

type ImageURL struct {
	URL string `json:"url"`
}

type Message struct {
	Role    string        `json:"role"`
	Content []ContentPart `json:"content"`
}

type chatCompletionRequest struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
}

type chatCompletionResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

func NewClient(cfg Config) *Client {
	if cfg.BaseURL == "" {
		cfg.BaseURL = "https://openrouter.ai/api/v1"
	}
	if cfg.Model == "" {
		cfg.Model = "google/gemini-2.5-flash"
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 120 * time.Second
	}
	return &Client{
		baseURL: strings.TrimRight(cfg.BaseURL, "/"),
		apiKey:  cfg.APIKey,
		model:   cfg.Model,
		http:    &http.Client{Timeout: cfg.Timeout},
	}
}

func (c *Client) ExtractText(ctx context.Context, imageData []byte, mime string) (string, error) {
	if mime == "" {
		mime = http.DetectContentType(imageData)
	}

	reqBody := chatCompletionRequest{
		Model: c.model,
		Messages: []Message{{
			Role: "user",
			Content: []ContentPart{
				{Type: "text", Text: defaultPrompt},
				{
					Type: "image_url",
					ImageURL: &ImageURL{
						URL: fmt.Sprintf("data:%s;base64,%s", mime, base64.StdEncoding.EncodeToString(imageData)),
					},
				},
			},
		}},
	}

	payload, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/chat/completions", bytes.NewReader(payload))
	if err != nil {
		return "", fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("ocr provider returned status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var out chatCompletionResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}
	if len(out.Choices) == 0 {
		return "", fmt.Errorf("ocr provider returned no choices")
	}

	return out.Choices[0].Message.Content, nil
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
go test ./internal/ocr/ -v
```

Expected: `ok ocrsearch/backend/internal/ocr` — all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/ocr/
git commit -m "feat: add OpenRouter OCR chat completions client"
```

---

## Task 4: FTS5 Search + Sync Hooks (`internal/fts`)

**Files:**
- Create: `backend/internal/fts/fts.go`
- Create: `backend/internal/fts/fts_test.go`

- [ ] **Step 1: Write the failing test**

`backend/internal/fts/fts_test.go`:

```go
package fts

import (
	"strings"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"

	_ "ocrsearch/backend/internal/migrations"
)

func newTestApp(t *testing.T) *tests.TestApp {
	t.Helper()
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	t.Cleanup(app.Cleanup)
	return app
}

func createDocument(t *testing.T, app core.App, title string) *core.Record {
	t.Helper()
	col, err := app.FindCollectionByNameOrId("documents")
	if err != nil {
		t.Fatal(err)
	}
	doc := core.NewRecord(col)
	doc.Set("title", title)
	if err := app.Save(doc); err != nil {
		t.Fatalf("save document: %v", err)
	}
	return doc
}

func createPage(t *testing.T, app core.App, docID string, pageNumber int, ocrText string) *core.Record {
	t.Helper()
	col, err := app.FindCollectionByNameOrId("pages")
	if err != nil {
		t.Fatal(err)
	}
	page := core.NewRecord(col)
	page.Set("document", docID)
	page.Set("page_number", pageNumber)
	page.Set("status", "pending")
	page.Set("ocr_text", ocrText)
	if err := app.Save(page); err != nil {
		t.Fatalf("save page: %v", err)
	}
	return page
}

func TestUpsertPageAndSearch(t *testing.T) {
	app := newTestApp(t)

	doc := createDocument(t, app, "Operation Manual")
	page := createPage(t, app, doc.Id, 3, "The needle valve regulates fuel flow.")

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
	r := results[0]
	if r.PageID != page.Id {
		t.Errorf("PageID = %q, want %q", r.PageID, page.Id)
	}
	if r.DocumentID != doc.Id {
		t.Errorf("DocumentID = %q, want %q", r.DocumentID, doc.Id)
	}
	if r.DocumentTitle != "Operation Manual" {
		t.Errorf("DocumentTitle = %q", r.DocumentTitle)
	}
	if r.PageNumber != 3 {
		t.Errorf("PageNumber = %d, want 3", r.PageNumber)
	}
	if !strings.Contains(r.Snippet, "<em>needle</em>") {
		t.Errorf("snippet = %q, want <em>needle</em> marker", r.Snippet)
	}
}

func TestSearchMatchesDocumentTitle(t *testing.T) {
	app := newTestApp(t)

	doc := createDocument(t, app, "Quarterly Report 2026")
	page := createPage(t, app, doc.Id, 1, "")
	if err := UpsertPage(app, page); err != nil {
		t.Fatalf("UpsertPage() error: %v", err)
	}

	results, err := Search(app, "quarterly", 10)
	if err != nil {
		t.Fatalf("Search() error: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("results len = %d, want 1 (title match)", len(results))
	}
	if results[0].DocumentTitle != "Quarterly Report 2026" {
		t.Errorf("DocumentTitle = %q", results[0].DocumentTitle)
	}
}

func TestSearchNoMatch(t *testing.T) {
	app := newTestApp(t)

	doc := createDocument(t, app, "Manual")
	page := createPage(t, app, doc.Id, 1, "nothing relevant here")
	if err := UpsertPage(app, page); err != nil {
		t.Fatalf("UpsertPage() error: %v", err)
	}

	results, err := Search(app, "zzzqqq", 10)
	if err != nil {
		t.Fatalf("Search() error: %v", err)
	}
	if len(results) != 0 {
		t.Errorf("results len = %d, want 0", len(results))
	}
}

func TestSearchSpecialCharacters(t *testing.T) {
	app := newTestApp(t)

	doc := createDocument(t, app, "Receipts")
	page := createPage(t, app, doc.Id, 1, `Total: $1,234.56 - "paid" (incl. tax)`)
	if err := UpsertPage(app, page); err != nil {
		t.Fatalf("UpsertPage() error: %v", err)
	}

	// A quote-heavy query must not produce an FTS5 syntax error.
	results, err := Search(app, `"paid"`, 10)
	if err != nil {
		t.Fatalf("Search() error: %v", err)
	}
	if len(results) != 1 {
		t.Errorf("results len = %d, want 1", len(results))
	}
}

func TestSanitizeQuery(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"hello world", `"hello" AND "world"`},
		{"it's fine", `"it's" AND "fine"`},
		{`say "hi"`, `"say" AND """hi"""`},
		{"", ""},
	}
	for _, c := range cases {
		if got := SanitizeQuery(c.in); got != c.want {
			t.Errorf("SanitizeQuery(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestRefreshDocument(t *testing.T) {
	app := newTestApp(t)

	doc := createDocument(t, app, "Old Title")
	page := createPage(t, app, doc.Id, 1, "common text")
	if err := UpsertPage(app, page); err != nil {
		t.Fatalf("UpsertPage() error: %v", err)
	}

	doc.Set("title", "New Title")
	if err := app.Save(doc); err != nil {
		t.Fatalf("save document: %v", err)
	}
	if err := RefreshDocument(app, doc); err != nil {
		t.Fatalf("RefreshDocument() error: %v", err)
	}

	results, err := Search(app, "newtitle", 10)
	if err != nil {
		t.Fatalf("Search() error: %v", err)
	}
	if len(results) != 1 || results[0].DocumentTitle != "New Title" {
		t.Errorf("results = %+v, want 1 result with New Title", results)
	}
}

func TestDeletePageRemovesFTSRow(t *testing.T) {
	app := newTestApp(t)

	doc := createDocument(t, app, "Manual")
	page := createPage(t, app, doc.Id, 1, "needle text")
	if err := UpsertPage(app, page); err != nil {
		t.Fatalf("UpsertPage() error: %v", err)
	}

	RegisterHooks(app)
	if err := app.Delete(page); err != nil {
		t.Fatalf("delete page: %v", err)
	}

	results, err := Search(app, "needle", 10)
	if err != nil {
		t.Fatalf("Search() error: %v", err)
	}
	if len(results) != 0 {
		t.Errorf("results len = %d, want 0 after page delete", len(results))
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
go test ./internal/fts/ -v
```

Expected: FAIL — package does not compile (`undefined: UpsertPage`, `undefined: Search`, ...).

- [ ] **Step 3: Write the implementation**

`backend/internal/fts/fts.go`:

```go
package fts

import (
	"fmt"
	"strings"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

const defaultLimit = 50

type SearchResult struct {
	DocumentID    string `db:"document_id"`
	DocumentTitle string `db:"title"`
	PageID        string `db:"page_id"`
	PageNumber    int    `db:"page_number"`
	Snippet       string `db:"snippet"`
}

// UpsertPage replaces the search_fts row for a single page, embedding its
// parent document title so title-only matches are searchable too.
func UpsertPage(app core.App, page *core.Record) error {
	doc, err := app.FindRecordById("documents", page.GetString("document"))
	if err != nil {
		return fmt.Errorf("load document for page %s: %w", page.Id, err)
	}

	pageID := page.Id
	docID := doc.Id
	title := doc.GetString("title")
	ocrText := page.GetString("ocr_text")
	pageNumber := page.GetInt("page_number")

	return app.RunInTransaction(func(txApp core.App) error {
		if _, err := txApp.DB().NewQuery(`DELETE FROM search_fts WHERE page_id = {:page_id}`).
			Bind(dbx.Params{"page_id": pageID}).Execute(); err != nil {
			return err
		}
		_, err := txApp.DB().NewQuery(`
			INSERT INTO search_fts(title, ocr_text, page_id, document_id, page_number)
			VALUES ({:title}, {:ocr_text}, {:page_id}, {:document_id}, {:page_number})
		`).Bind(dbx.Params{
			"title":       title,
			"ocr_text":    ocrText,
			"page_id":     pageID,
			"document_id": docID,
			"page_number": pageNumber,
		}).Execute()
		return err
	})
}

// RefreshDocument re-indexes all pages of a document (used when the title changes).
func RefreshDocument(app core.App, doc *core.Record) error {
	pages, err := app.FindRecordsByFilter(
		"pages",
		"document = {:document}",
		"-page_number",
		0,
		0,
		dbx.Params{"document": doc.Id},
	)
	if err != nil {
		return err
	}
	for _, page := range pages {
		if err := UpsertPage(app, page); err != nil {
			return err
		}
	}
	return nil
}

// SanitizeQuery quotes every whitespace-separated term so FTS5 special
// characters cannot cause syntax errors or be abused as operators.
func SanitizeQuery(q string) string {
	terms := strings.Fields(q)
	for i, term := range terms {
		terms[i] = `"` + strings.ReplaceAll(term, `"`, `""`) + `"`
	}
	return strings.Join(terms, " AND ")
}

// Search runs a full-text query against search_fts ordered by FTS5 rank.
// Snippets wrap matches in <em>...</em> for frontend highlighting.
func Search(app core.App, q string, limit int) ([]SearchResult, error) {
	if limit <= 0 {
		limit = defaultLimit
	}

	results := []SearchResult{}
	err := app.DB().NewQuery(`
		SELECT document_id, title, page_id, page_number,
		       snippet(search_fts, 1, '<em>', '</em>', ' ... ') AS snippet
		FROM search_fts
		WHERE search_fts MATCH {:q}
		ORDER BY rank
		LIMIT {:limit}
	`).Bind(dbx.Params{
		"q":     SanitizeQuery(q),
		"limit": limit,
	}).All(&results)
	return results, err
}

// RegisterHooks keeps search_fts in sync with page/document changes.
func RegisterHooks(app core.App) {
	app.OnRecordAfterCreateSuccess("pages").BindFunc(func(e *core.RecordEvent) error {
		return UpsertPage(e.App, e.Record)
	})
	app.OnRecordAfterUpdateSuccess("pages").BindFunc(func(e *core.RecordEvent) error {
		return UpsertPage(e.App, e.Record)
	})
	app.OnRecordAfterDeleteSuccess("pages").BindFunc(func(e *core.RecordEvent) error {
		_, err := e.App.DB().NewQuery(`DELETE FROM search_fts WHERE page_id = {:page_id}`).
			Bind(dbx.Params{"page_id": e.Record.Id}).Execute()
		return err
	})
	app.OnRecordAfterUpdateSuccess("documents").BindFunc(func(e *core.RecordEvent) error {
		return RefreshDocument(e.App, e.Record)
	})
	app.OnRecordAfterDeleteSuccess("documents").BindFunc(func(e *core.RecordEvent) error {
		_, err := e.App.DB().NewQuery(`DELETE FROM search_fts WHERE document_id = {:document_id}`).
			Bind(dbx.Params{"document_id": e.Record.Id}).Execute()
		return err
	})
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
go test ./internal/fts/ -v
```

Expected: `ok ocrsearch/backend/internal/fts` — all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/fts/
git commit -m "feat: add FTS5 search and record sync hooks"
```

---

## Task 5: Persistent OCR Queue + Cron Worker (`internal/queue`)

**Files:**
- Create: `backend/internal/queue/queue.go`
- Create: `backend/internal/queue/queue_test.go`

- [ ] **Step 1: Write the failing test**

`backend/internal/queue/queue_test.go`:

```go
package queue

import (
	"context"
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
	"github.com/pocketbase/pocketbase/tools/filesystem"

	_ "ocrsearch/backend/internal/migrations"
	"ocrsearch/backend/internal/fts"
	"ocrsearch/backend/internal/ocr"
)

// pngBytes is a 1x1 transparent PNG used to satisfy the pages.image MIME check.
var pngBytes = func() []byte {
	b, err := base64.StdEncoding.DecodeString(
		"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
	)
	if err != nil {
		panic(err)
	}
	return b
}()

func newTestApp(t *testing.T) *tests.TestApp {
	t.Helper()
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	t.Cleanup(app.Cleanup)
	return app
}

func seedPageWithImage(t *testing.T, app core.App) (*core.Record, *core.Record) {
	t.Helper()

	docCol, err := app.FindCollectionByNameOrId("documents")
	if err != nil {
		t.Fatal(err)
	}
	doc := core.NewRecord(docCol)
	doc.Set("title", "Seed Manual")
	if err := app.Save(doc); err != nil {
		t.Fatalf("save document: %v", err)
	}

	pageCol, err := app.FindCollectionByNameOrId("pages")
	if err != nil {
		t.Fatal(err)
	}
	page := core.NewRecord(pageCol)
	page.Set("document", doc.Id)
	page.Set("page_number", 1)
	page.Set("status", "pending")

	file, err := filesystem.NewFileFromBytes(pngBytes, "page.png")
	if err != nil {
		t.Fatalf("NewFileFromBytes: %v", err)
	}
	page.Set("image", file)
	if err := app.Save(page); err != nil {
		t.Fatalf("save page: %v", err)
	}

	return doc, page
}

func findQueueEntry(t *testing.T, app core.App, pageID string) *core.Record {
	t.Helper()
	entries, err := app.FindRecordsByFilter("ocr_queue", "page = {:page}", "", 1, 0, dbx.Params{"page": pageID})
	if err != nil {
		t.Fatalf("find queue entry: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("queue entries len = %d, want 1", len(entries))
	}
	return entries[0]
}

func TestPageCreateCreatesQueueEntry(t *testing.T) {
	app := newTestApp(t)
	RegisterHooks(app)
	fts.RegisterHooks(app)

	_, page := seedPageWithImage(t, app)

	entry := findQueueEntry(t, app, page.Id)
	if entry.GetString("status") != "queued" {
		t.Errorf("queue status = %q, want queued", entry.GetString("status"))
	}
	if entry.GetString("page") != page.Id {
		t.Errorf("queue page = %q, want %q", entry.GetString("page"), page.Id)
	}
}

func TestProcessBatchSuccess(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"Extracted page text"}}]}`))
	}))
	defer srv.Close()

	app := newTestApp(t)
	RegisterHooks(app)
	fts.RegisterHooks(app)

	_, page := seedPageWithImage(t, app)

	client := ocr.NewClient(ocr.Config{BaseURL: srv.URL, APIKey: "k", Model: "m"})
	if err := ProcessBatch(context.Background(), app, client, ProcessOptions{Concurrency: 5, RetryMax: 3}); err != nil {
		t.Fatalf("ProcessBatch() error: %v", err)
	}

	page, err := app.FindRecordById("pages", page.Id)
	if err != nil {
		t.Fatalf("reload page: %v", err)
	}
	if page.GetString("ocr_text") != "Extracted page text" {
		t.Errorf("ocr_text = %q", page.GetString("ocr_text"))
	}
	if page.GetString("status") != "completed" {
		t.Errorf("page status = %q, want completed", page.GetString("status"))
	}

	entry := findQueueEntry(t, app, page.Id)
	if entry.GetString("status") != "completed" {
		t.Errorf("queue status = %q, want completed", entry.GetString("status"))
	}
}

func TestProcessBatchRetriesThenFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	defer srv.Close()

	app := newTestApp(t)
	RegisterHooks(app)
	fts.RegisterHooks(app)

	_, page := seedPageWithImage(t, app)
	client := ocr.NewClient(ocr.Config{BaseURL: srv.URL, APIKey: "k", Model: "m"})
	opts := ProcessOptions{Concurrency: 5, RetryMax: 2}

	// First pass: transient failure -> back to queued with retry_count 1.
	if err := ProcessBatch(context.Background(), app, client, opts); err != nil {
		t.Fatalf("ProcessBatch() error: %v", err)
	}
	entry := findQueueEntry(t, app, page.Id)
	if entry.GetString("status") != "queued" {
		t.Errorf("queue status = %q, want queued after retry", entry.GetString("status"))
	}
	if entry.GetInt("retry_count") != 1 {
		t.Errorf("retry_count = %d, want 1", entry.GetInt("retry_count"))
	}
	if entry.GetString("error_log") == "" {
		t.Error("error_log empty after failure")
	}
	page, _ := app.FindRecordById("pages", page.Id)
	if page.GetString("status") != "pending" {
		t.Errorf("page status = %q, want pending after retry", page.GetString("status"))
	}

	// Second pass: retry_count reaches max -> failed.
	if err := ProcessBatch(context.Background(), app, client, opts); err != nil {
		t.Fatalf("ProcessBatch() error: %v", err)
	}
	entry = findQueueEntry(t, app, page.Id)
	if entry.GetString("status") != "failed" {
		t.Errorf("queue status = %q, want failed", entry.GetString("status"))
	}
	if entry.GetInt("retry_count") != 2 {
		t.Errorf("retry_count = %d, want 2", entry.GetInt("retry_count"))
	}
	page, _ = app.FindRecordById("pages", page.Id)
	if page.GetString("status") != "failed" {
		t.Errorf("page status = %q, want failed", page.GetString("status"))
	}
}

func TestProcessBatchRequestPayload(t *testing.T) {
	var gotAuth string
	var gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		b, _ := io.ReadAll(r.Body)
		gotBody = string(b)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"ok"}}]}`))
	}))
	defer srv.Close()

	app := newTestApp(t)
	RegisterHooks(app)
	fts.RegisterHooks(app)
	_, page := seedPageWithImage(t, app)

	client := ocr.NewClient(ocr.Config{BaseURL: srv.URL, APIKey: "sk-worker", Model: "google/gemini-test"})
	if err := ProcessBatch(context.Background(), app, client, ProcessOptions{Concurrency: 5, RetryMax: 3}); err != nil {
		t.Fatalf("ProcessBatch() error: %v", err)
	}

	if gotAuth != "Bearer sk-worker" {
		t.Errorf("Authorization = %q, want Bearer sk-worker", gotAuth)
	}
	if !strings.Contains(gotBody, "data:image/png;base64,") {
		t.Errorf("request body missing data URL image: %s", gotBody)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
go test ./internal/queue/ -v
```

Expected: FAIL — package does not compile (`undefined: RegisterHooks`, `undefined: ProcessBatch`, `undefined: ProcessOptions`).

- [ ] **Step 3: Write the implementation**

`backend/internal/queue/queue.go`:

```go
package queue

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"

	"ocrsearch/backend/internal/fts"
	"ocrsearch/backend/internal/ocr"
)

const (
	StatusQueued     = "queued"
	StatusInProgress = "in_progress"
	StatusCompleted  = "completed"
	StatusFailed     = "failed"
)

type ProcessOptions struct {
	Concurrency int
	RetryMax    int
}

// RegisterHooks wires page/queue lifecycle hooks.
func RegisterHooks(app core.App) {
	// On page creation: enqueue an OCR task (and index the page in FTS).
	app.OnRecordAfterCreateSuccess("pages").BindFunc(func(e *core.RecordEvent) error {
		if err := CreateQueueEntry(e.App, e.Record); err != nil {
			return err
		}
		return fts.UpsertPage(e.App, e.Record)
	})

	// Apply spec defaults when records are created through the REST API.
	app.OnRecordCreateRequest("pages").BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Record.GetString("status") == "" {
			e.Record.Set("status", "pending")
		}
		return e.Next()
	})
	app.OnRecordCreateRequest("ocr_queue").BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Record.GetString("status") == "" {
			e.Record.Set("status", StatusQueued)
		}
		return e.Next()
	})
}

func CreateQueueEntry(app core.App, page *core.Record) error {
	collection, err := app.FindCollectionByNameOrId("ocr_queue")
	if err != nil {
		return err
	}
	entry := core.NewRecord(collection)
	entry.Set("page", page.Id)
	entry.Set("status", StatusQueued)
	entry.Set("retry_count", 0)
	return app.Save(entry)
}

// ProcessBatch processes up to opts.Concurrency queued items (oldest first).
func ProcessBatch(ctx context.Context, app core.App, client *ocr.Client, opts ProcessOptions) error {
	if opts.Concurrency <= 0 {
		opts.Concurrency = 5
	}
	if opts.RetryMax <= 0 {
		opts.RetryMax = 3
	}

	items, err := app.FindRecordsByFilter(
		"ocr_queue",
		"status = {:status}",
		"created",
		opts.Concurrency,
		0,
		dbx.Params{"status": StatusQueued},
	)
	if err != nil {
		return fmt.Errorf("fetch queued items: %w", err)
	}

	for _, item := range items {
		if err := processItem(ctx, app, client, item, opts.RetryMax); err != nil {
			log.Printf("queue: failed to process item %s: %v", item.Id, err)
		}
	}
	return nil
}

func processItem(ctx context.Context, app core.App, client *ocr.Client, item *core.Record, retryMax int) error {
	page, err := app.FindRecordById("pages", item.GetString("page"))
	if err != nil {
		return fmt.Errorf("load page: %w", err)
	}

	if err := app.RunInTransaction(func(txApp core.App) error {
		item.Set("status", StatusInProgress)
		page.Set("status", "processing")
		if err := txApp.Save(item); err != nil {
			return err
		}
		return txApp.Save(page)
	}); err != nil {
		return fmt.Errorf("mark in progress: %w", err)
	}

	text, err := extractPageText(ctx, app, page, client)
	if err != nil {
		return handleFailure(app, item, page, err, retryMax)
	}

	return app.RunInTransaction(func(txApp core.App) error {
		page.Set("ocr_text", text)
		page.Set("status", "completed")
		item.Set("status", StatusCompleted)
		item.Set("error_log", "")
		if err := txApp.Save(page); err != nil {
			return err
		}
		return txApp.Save(item)
	})
}

func extractPageText(ctx context.Context, app core.App, page *core.Record, client *ocr.Client) (string, error) {
	filename := page.GetString("image")
	if filename == "" {
		return "", fmt.Errorf("page %s has no image file", page.Id)
	}

	fsys, err := app.NewFilesystem()
	if err != nil {
		return "", fmt.Errorf("init filesystem: %w", err)
	}
	defer fsys.Close()

	r, err := fsys.GetReader(page.BaseFilesPath() + "/" + filename)
	if err != nil {
		return "", fmt.Errorf("read page image: %w", err)
	}
	defer r.Close()

	data, err := io.ReadAll(r)
	if err != nil {
		return "", fmt.Errorf("read page image bytes: %w", err)
	}

	return client.ExtractText(ctx, data, http.DetectContentType(data))
}

func handleFailure(app core.App, item *core.Record, page *core.Record, ocrErr error, retryMax int) error {
	retries := item.GetInt("retry_count") + 1

	err := app.RunInTransaction(func(txApp core.App) error {
		item.Set("retry_count", retries)
		item.Set("error_log", ocrErr.Error())
		if retries >= retryMax {
			item.Set("status", StatusFailed)
			page.Set("status", "failed")
		} else {
			item.Set("status", StatusQueued)
			page.Set("status", "pending")
		}
		if err := txApp.Save(item); err != nil {
			return err
		}
		return txApp.Save(page)
	})
	if err != nil {
		return fmt.Errorf("record failure state: %w", err)
	}
	return nil
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
go test ./internal/queue/ -v
```

Expected: `ok ocrsearch/backend/internal/queue` — all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/queue/
git commit -m "feat: add persistent OCR queue worker with retry semantics"
```

---

## Task 6: OAuth Whitelist Hook (`internal/oauth`)

**Files:**
- Create: `backend/internal/oauth/oauth.go`
- Create: `backend/internal/oauth/oauth_test.go`

The whitelist decision logic is a plain, testable function (`IsAllowed`); the hook is a thin binder around it (the full OAuth flow is exercised in the docker E2E, Task 9).

- [ ] **Step 1: Write the failing test**

`backend/internal/oauth/oauth_test.go`:

```go
package oauth

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"

	_ "ocrsearch/backend/internal/migrations"
)

func newTestApp(t *testing.T) *tests.TestApp {
	t.Helper()
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	t.Cleanup(app.Cleanup)
	return app
}

func seedAllowedUser(t *testing.T, app core.App, email string) {
	t.Helper()
	col, err := app.FindCollectionByNameOrId("allowed_users")
	if err != nil {
		t.Fatal(err)
	}
	rec := core.NewRecord(col)
	rec.Set("email", email)
	if err := app.Save(rec); err != nil {
		t.Fatalf("save allowed_user: %v", err)
	}
}

func TestIsAllowedTrue(t *testing.T) {
	app := newTestApp(t)
	seedAllowedUser(t, app, "bob@gmail.com")

	allowed, err := IsAllowed(app, "bob@gmail.com")
	if err != nil {
		t.Fatalf("IsAllowed() error: %v", err)
	}
	if !allowed {
		t.Error("IsAllowed() = false, want true for whitelisted email")
	}
}

func TestIsAllowedFalse(t *testing.T) {
	app := newTestApp(t)
	seedAllowedUser(t, app, "bob@gmail.com")

	allowed, err := IsAllowed(app, "mallory@gmail.com")
	if err != nil {
		t.Fatalf("IsAllowed() error: %v", err)
	}
	if allowed {
		t.Error("IsAllowed() = true, want false for non-whitelisted email")
	}
}

func TestIsAllowedEmptyEmail(t *testing.T) {
	app := newTestApp(t)

	allowed, err := IsAllowed(app, "")
	if err != nil {
		t.Fatalf("IsAllowed() error: %v", err)
	}
	if allowed {
		t.Error("IsAllowed() = true for empty email, want false")
	}
}

func TestIsAllowedExactMatch(t *testing.T) {
	app := newTestApp(t)
	seedAllowedUser(t, app, "bob@gmail.com")

	allowed, err := IsAllowed(app, "Bob@gmail.com")
	if err != nil {
		t.Fatalf("IsAllowed() error: %v", err)
	}
	if allowed {
		t.Error("IsAllowed() = true for differently-cased email, want false (exact match)")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
go test ./internal/oauth/ -v
```

Expected: FAIL — package does not compile (`undefined: IsAllowed`).

- [ ] **Step 3: Write the implementation**

`backend/internal/oauth/oauth.go`:

```go
package oauth

import (
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// IsAllowed reports whether email is present in the allowed_users whitelist.
func IsAllowed(app core.App, email string) (bool, error) {
	if email == "" {
		return false, nil
	}
	records, err := app.FindRecordsByFilter(
		"allowed_users",
		"email = {:email}",
		"",
		1,
		0,
		dbx.Params{"email": email},
	)
	if err != nil {
		return false, err
	}
	return len(records) > 0, nil
}

// RegisterHooks binds the Google OAuth whitelist check. Non-whitelisted
// emails abort authentication with a 403.
func RegisterHooks(app core.App) {
	app.OnRecordAuthWithOAuth2Request("users").BindFunc(func(e *core.RecordAuthWithOAuth2RequestEvent) error {
		if e.OAuth2User == nil || e.OAuth2User.Email == "" {
			return e.ForbiddenError("Email is not whitelisted", nil)
		}
		allowed, err := IsAllowed(e.App, e.OAuth2User.Email)
		if err != nil {
			return e.InternalServerError("Failed to verify whitelist", err)
		}
		if !allowed {
			return e.ForbiddenError("Your email is not whitelisted", nil)
		}
		return e.Next()
	})
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
go test ./internal/oauth/ -v
```

Expected: `ok ocrsearch/backend/internal/oauth` — all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/oauth/
git commit -m "feat: add OAuth whitelist check for google sign-in"
```

---

## Task 7: Search Route (`internal/search`)

**Files:**
- Create: `backend/internal/search/search.go`
- Create: `backend/internal/search/search_test.go`

- [ ] **Step 1: Write the failing test**

`backend/internal/search/search_test.go`:

```go
package search

import (
	"errors"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"

	_ "ocrsearch/backend/internal/migrations"
	"ocrsearch/backend/internal/fts"
)

func newTestApp(t *testing.T) *tests.TestApp {
	t.Helper()
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	t.Cleanup(app.Cleanup)
	return app
}

func TestRunSearchMissingQuery(t *testing.T) {
	app := newTestApp(t)

	_, err := RunSearch(app, "   ")
	if !errors.Is(err, ErrMissingQuery) {
		t.Fatalf("RunSearch() error = %v, want ErrMissingQuery", err)
	}
}

func TestRunSearchReturnsMatches(t *testing.T) {
	app := newTestApp(t)

	docCol, err := app.FindCollectionByNameOrId("documents")
	if err != nil {
		t.Fatal(err)
	}
	doc := core.NewRecord(docCol)
	doc.Set("title", "Lease Agreement")
	if err := app.Save(doc); err != nil {
		t.Fatal(err)
	}

	pageCol, err := app.FindCollectionByNameOrId("pages")
	if err != nil {
		t.Fatal(err)
	}
	page := core.NewRecord(pageCol)
	page.Set("document", doc.Id)
	page.Set("page_number", 2)
	page.Set("status", "completed")
	page.Set("ocr_text", "The tenant shall pay rent monthly.")
	if err := app.Save(page); err != nil {
		t.Fatal(err)
	}
	if err := fts.UpsertPage(app, page); err != nil {
		t.Fatalf("UpsertPage: %v", err)
	}

	results, err := RunSearch(app, "tenant")
	if err != nil {
		t.Fatalf("RunSearch() error: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("results len = %d, want 1", len(results))
	}
	if results[0].DocumentTitle != "Lease Agreement" {
		t.Errorf("DocumentTitle = %q", results[0].DocumentTitle)
	}
	if results[0].PageNumber != 2 {
		t.Errorf("PageNumber = %d, want 2", results[0].PageNumber)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
go test ./internal/search/ -v
```

Expected: FAIL — package does not compile (`undefined: ErrMissingQuery`, `undefined: RunSearch`).

- [ ] **Step 3: Write the implementation**

`backend/internal/search/search.go`:

```go
package search

import (
	"errors"
	"strings"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"

	"ocrsearch/backend/internal/fts"
)

var ErrMissingQuery = errors.New("missing q parameter")

// RunSearch executes the search logic shared by the HTTP handler and tests.
func RunSearch(app core.App, q string) ([]fts.SearchResult, error) {
	q = strings.TrimSpace(q)
	if q == "" {
		return nil, ErrMissingQuery
	}
	return fts.Search(app, q, 50)
}

// RegisterRoutes mounts GET /api/search behind auth.
func RegisterRoutes(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/search", func(e *core.RequestEvent) error {
			results, err := RunSearch(e.App, e.Request.URL.Query().Get("q"))
			if err != nil {
				if errors.Is(err, ErrMissingQuery) {
					return e.BadRequestError(err.Error(), nil)
				}
				return e.InternalServerError("search failed", err)
			}
			return e.JSON(200, results)
		}).Bind(apis.RequireAuth())
		return e.Next()
	})
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
go test ./internal/search/ -v
```

Expected: `ok ocrsearch/backend/internal/search` — both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/search/
git commit -m "feat: add /api/search route backed by FTS5"
```

---

## Task 8: Wire Everything in `main.go`

**Files:**
- Modify: `backend/main.go`

- [ ] **Step 1: Replace main.go with the full wiring**

`backend/main.go`:

```go
package main

import (
	"context"
	"log"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
	"github.com/pocketbase/pocketbase/tools/osutils"
	"github.com/spf13/cobra"

	"ocrsearch/backend/internal/config"
	"ocrsearch/backend/internal/fts"
	"ocrsearch/backend/internal/migrations"
	"ocrsearch/backend/internal/oauth"
	"ocrsearch/backend/internal/ocr"
	"ocrsearch/backend/internal/queue"
	"ocrsearch/backend/internal/search"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	app := pocketbase.New()

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		Automigrate: osutils.IsProbablyGoRun(),
	})

	app.OnBootstrap().BindFunc(func(e *core.BootstrapEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		return config.ApplySettings(e.App, cfg)
	})

	fts.RegisterHooks(app)
	queue.RegisterHooks(app)
	oauth.RegisterHooks(app)
	search.RegisterRoutes(app)

	client := ocr.NewClient(ocr.Config{
		BaseURL: cfg.OCR.BaseURL,
		APIKey:  cfg.OCR.APIKey,
		Model:   cfg.OCR.Model,
		Timeout: cfg.OCR.Timeout,
	})
	opts := queue.ProcessOptions{
		Concurrency: cfg.OCR.Concurrency,
		RetryMax:    cfg.OCR.RetryMax,
	}

	app.Cron().MustAdd("ocr-worker", "*/1 * * * *", func() {
		if err := queue.ProcessBatch(context.Background(), app, client, opts); err != nil {
			log.Printf("ocr worker error: %v", err)
		}
	})

	app.RootCmd.AddCommand(&cobra.Command{
		Use:   "ocr-worker",
		Short: "Run a single OCR batch pass",
		Run: func(cmd *cobra.Command, args []string) {
			if err := queue.ProcessBatch(cmd.Context(), app, client, opts); err != nil {
				log.Fatal(err)
			}
		},
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
```

- [ ] **Step 2: Build, vet, and run the full suite**

Run:

```bash
go mod tidy
go build ./...
go vet ./...
go test ./...
```

Expected: build and vet exit 0 with no output; `go test ./...` prints `ok` for every package:

```
ok  	ocrsearch/backend/internal/config
ok  	ocrsearch/backend/internal/fts
ok  	ocrsearch/backend/internal/migrations
ok  	ocrsearch/backend/internal/oauth
ok  	ocrsearch/backend/internal/ocr
ok  	ocrsearch/backend/internal/queue
ok  	ocrsearch/backend/internal/search
```

- [ ] **Step 3: Verify the binary boots locally (without docker)**

Run (S3 stays disabled because no S3_ENDPOINT is set):

```bash
timeout 20 go run . serve --http=127.0.0.1:8090
```

Expected: PocketBase logs show migrations applying (creating the collections), then the server listens on `127.0.0.1:8090`; the `timeout` kills it after 20s (exit 124 is expected).

- [ ] **Step 4: Verify the ocr-worker CLI command runs**

Run:

```bash
go run . ocr-worker
```

Expected: exits 0 with no queued items on a fresh DB.

- [ ] **Step 5: Commit**

```bash
git add backend/main.go
git commit -m "feat: wire backend entrypoint with hooks, cron worker, and search route"
```

---

## Task 9: Docker Compose End-to-End Verification

**Files:** none (verification only; commit only if fixes are needed)

Prerequisite: Docker is installed (verified in Task 0) and `jq` is available on the host for the JSON queries below (`sudo apt install jq` or equivalent).

- [ ] **Step 1: Create the local env file**

```bash
cp .env.example .env
```

`OCR_API_KEY` stays the placeholder `sk-or-placeholder`; Google OAuth stays empty.

- [ ] **Step 2: Build and start the stack**

```bash
docker compose up --build -d
docker compose ps
```

Expected: `minio` and `backend` show `Up` and `healthy`; `minio-init` exits 0 after creating the `pages` bucket.

- [ ] **Step 3: Create a superuser and an allowed user**

```bash
docker compose exec backend /app/backend superuser create admin@example.com 1234567890
```

Expected: `The superuser was successfully created.` Then grab an admin token and seed the whitelist:

```bash
ADMIN_TOKEN=$(curl -s -X POST http://localhost:8090/api/collections/_superusers/auth-with-password \
  -H 'Content-Type: application/json' \
  -d '{"identity":"admin@example.com","password":"1234567890"}' | jq -r .token)
curl -s -X POST http://localhost:8090/api/collections/allowed_users/records \
  -H "Authorization: Admin $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"email":"me@gmail.com"}' | jq .email
```

Expected: `"me@gmail.com"`.

- [ ] **Step 4: Create a document, upload a page, and confirm the queue entry**

Create a small test PNG first, then upload:

```bash
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' | base64 -d > /tmp/page.png
DOC_ID=$(curl -s -X POST http://localhost:8090/api/collections/documents/records \
  -H "Authorization: Admin $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Test Manual"}' | jq -r .id)
PAGE_ID=$(curl -s -X POST http://localhost:8090/api/collections/pages/records \
  -H "Authorization: Admin $ADMIN_TOKEN" \
  -F "document=$DOC_ID" \
  -F 'page_number=1' \
  -F 'status=pending' \
  -F 'image=@/tmp/page.png;type=image/png' | jq -r .id)
curl -s "http://localhost:8090/api/collections/ocr_queue/records?page=$PAGE_ID" \
  -H "Authorization: Admin $ADMIN_TOKEN" | jq '.items[0].status'
```

Expected: page created, and the queue query prints `"queued"`.

- [ ] **Step 5: Run one worker pass and verify graceful failure with placeholder key**

```bash
docker compose exec backend /app/backend ocr-worker
curl -s "http://localhost:8090/api/collections/pages/records?page=$PAGE_ID" \
  -H "Authorization: Admin $ADMIN_TOKEN" | jq '.items[0] | {status, ocr_text, id}'
curl -s "http://localhost:8090/api/collections/ocr_queue/records?page=$PAGE_ID" \
  -H "Authorization: Admin $ADMIN_TOKEN" | jq '.items[0] | {status, retry_count, error_log}'
```

Expected: the page image is read from MinIO, the OpenRouter call fails with a 401 (placeholder key), `retry_count` is 1, queue status is `queued` again, page status is `pending`, and `error_log` contains the provider error.

- [ ] **Step 6: Verify search route behavior (error and empty result)**

```bash
curl -s "http://localhost:8090/api/search?q=" -H "Authorization: Admin $ADMIN_TOKEN" | jq .message
curl -s "http://localhost:8090/api/search?q=nothingmatches" -H "Authorization: Admin $ADMIN_TOKEN" | jq .
```

Expected: empty `q` returns `"missing q parameter"`; a no-match query returns `[]`.

- [ ] **Step 7: Optional live OCR check (only if a real OpenRouter key is available)**

1. Put the real key in `.env` (`OCR_API_KEY=sk-or-real-key`).
2. `docker compose up -d --force-recreate backend`
3. Re-upload a page, run `docker compose exec backend /app/backend ocr-worker`, then confirm `ocr_text` is populated and both statuses are `completed`.

- [ ] **Step 8: Stop the stack (keep data volume for later)**

```bash
docker compose down
```

- [ ] **Step 9: Commit any fixes from the E2E run**

```bash
git add -A
git commit -m "fix: adjustments found during docker e2e verification"
```

Only commit if files actually changed.

---

## Self-Review Notes

**Spec coverage:**

| Spec requirement | Task |
| --- | --- |
| `allowed_users` / `documents` / `pages` / `ocr_queue` collections | Task 2 |
| FTS5 `search_fts` (additive) | Task 2 |
| Embedded Go binary (Approach A) | Tasks 0 + 8 |
| Env-driven config with `.env.example` placeholders | Tasks 0 + 1 |
| Google OAuth whitelist hook (403 on non-whitelisted) | Task 6 |
| Page upload -> `ocr_queue` entry hook | Task 5 |
| `status` / `retry_count` spec defaults | Task 5 |
| Cron worker `*/1 * * * *`, up to N items, S3 read, OpenRouter call, retry -> `failed` after `OCR_RETRY_MAX` | Tasks 5 + 8 |
| `GET /api/search` with FTS5 rank + `<em>` snippets, auth-protected | Tasks 4 + 7 |
| Docker Compose + MinIO S3 storage | Task 0 |
| Mocked-test verification strategy | Tasks 1-7; live check Task 9 |
| `ocr-worker` single-pass CLI for deterministic E2E | Task 8 |
| Delete cleanup of stale FTS rows | Task 4 (design refinement) |
| Docker E2E verification | Task 9 |

**No placeholders:** every code step contains complete, compilable code.

**Type consistency:** `ProcessOptions{Concurrency, RetryMax}` is the single options type used by `ProcessBatch` and `main.go`; `ocr.Config` is the single client config type; `fts.SearchResult` is the single result type shared by `fts.Search`, `search.RunSearch`, and the JSON response.
