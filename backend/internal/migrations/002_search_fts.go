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
