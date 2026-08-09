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
