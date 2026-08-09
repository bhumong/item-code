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
	page, _ = app.FindRecordById("pages", page.Id)
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
	_, _ = seedPageWithImage(t, app)

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
