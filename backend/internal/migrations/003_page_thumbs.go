package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// PageThumbSizes are the thumbnail sizes PocketBase may generate for page
// images. The file API only serves ?thumb= values that are either the built-in
// 100x100 or declared on the file field, so any size the frontend requests has
// to be listed here. The suffix selects the crop mode (t = crop from top,
// f = fit inside the viewbox without cropping).
var PageThumbSizes = []string{
	"100x120t", // search result tile
	"360x360t", // document page gallery tile
}

func init() {
	migrations.Register(declarePageThumbs, clearPageThumbs)
}

func declarePageThumbs(app core.App) error {
	pages, err := app.FindCollectionByNameOrId("pages")
	if err != nil {
		return err
	}
	field, _ := pages.Fields.GetByName("image").(*core.FileField)
	if field == nil {
		return nil
	}
	field.Thumbs = append([]string(nil), PageThumbSizes...)
	return app.Save(pages)
}

func clearPageThumbs(app core.App) error {
	pages, err := app.FindCollectionByNameOrId("pages")
	if err != nil {
		return nil
	}
	field, _ := pages.Fields.GetByName("image").(*core.FileField)
	if field == nil {
		return nil
	}
	field.Thumbs = nil
	return app.Save(pages)
}
