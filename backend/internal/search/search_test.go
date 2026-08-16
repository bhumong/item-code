package search

import (
	"encoding/base64"
	"errors"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
	"github.com/pocketbase/pocketbase/tools/filesystem"

	_ "ocrsearch/backend/internal/migrations"
	"ocrsearch/backend/internal/fts"
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
	file, err := filesystem.NewFileFromBytes(pngBytes, "page.png")
	if err != nil {
		t.Fatalf("NewFileFromBytes: %v", err)
	}
	page.Set("image", file)
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
	if results[0].PageImage != page.GetString("image") {
		t.Errorf("PageImage = %q, want %q", results[0].PageImage, page.GetString("image"))
	}
}
