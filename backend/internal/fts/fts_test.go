package fts

import (
	"encoding/base64"
	"strings"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
	"github.com/pocketbase/pocketbase/tools/filesystem"

	_ "ocrsearch/backend/internal/migrations"
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
	file, err := filesystem.NewFileFromBytes(pngBytes, "page.png")
	if err != nil {
		t.Fatalf("NewFileFromBytes: %v", err)
	}
	page.Set("image", file)
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

	// FTS5 tokenizes "New Title" into "new" + "title", so query a single token.
	results, err := Search(app, "new", 10)
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
