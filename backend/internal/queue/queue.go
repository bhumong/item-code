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
