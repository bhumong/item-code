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
// Highlighted ocr_text wraps matches in <em>...</em> for frontend use.
// Note: FTS5's snippet() raises "wrong number of arguments" on this SQLite
// build when a MATCH finds rows, so we use highlight() instead.
func Search(app core.App, q string, limit int) ([]SearchResult, error) {
	if limit <= 0 {
		limit = defaultLimit
	}

	results := []SearchResult{}
	err := app.DB().NewQuery(`
		SELECT document_id, title, page_id, page_number,
		       highlight(search_fts, 1, '<em>', '</em>') AS snippet
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
