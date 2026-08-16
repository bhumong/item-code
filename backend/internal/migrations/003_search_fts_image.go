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
