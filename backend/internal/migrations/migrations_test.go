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
	for _, fname := range []string{"document", "page_number", "image", "ocr_text", "status", "created", "updated"} {
		if pages.Fields.GetByName(fname) == nil {
			t.Errorf("pages field %q missing", fname)
		}
	}

	queue, err := app.FindCollectionByNameOrId("ocr_queue")
	if err != nil {
		t.Fatal(err)
	}
	for _, fname := range []string{"page", "status", "retry_count", "error_log", "created", "updated"} {
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
