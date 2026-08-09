package main

import (
	"context"
	"log"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
	"github.com/pocketbase/pocketbase/tools/osutils"
	"github.com/spf13/cobra"

	"ocrsearch/backend/internal/config"
	"ocrsearch/backend/internal/fts"
	_ "ocrsearch/backend/internal/migrations"
	"ocrsearch/backend/internal/oauth"
	"ocrsearch/backend/internal/ocr"
	"ocrsearch/backend/internal/queue"
	"ocrsearch/backend/internal/search"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	app := pocketbase.New()

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		Automigrate: osutils.IsProbablyGoRun(),
	})

	app.OnBootstrap().BindFunc(func(e *core.BootstrapEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		return config.ApplySettings(e.App, cfg)
	})

	fts.RegisterHooks(app)
	queue.RegisterHooks(app)
	oauth.RegisterHooks(app)
	search.RegisterRoutes(app)

	client := ocr.NewClient(ocr.Config{
		BaseURL: cfg.OCR.BaseURL,
		APIKey:  cfg.OCR.APIKey,
		Model:   cfg.OCR.Model,
		Timeout: cfg.OCR.Timeout,
	})
	opts := queue.ProcessOptions{
		Concurrency: cfg.OCR.Concurrency,
		RetryMax:    cfg.OCR.RetryMax,
	}

	app.Cron().MustAdd("ocr-worker", "*/1 * * * *", func() {
		if err := queue.ProcessBatch(context.Background(), app, client, opts); err != nil {
			log.Printf("ocr worker error: %v", err)
		}
	})

	app.RootCmd.AddCommand(&cobra.Command{
		Use:   "ocr-worker",
		Short: "Run a single OCR batch pass",
		Run: func(cmd *cobra.Command, args []string) {
			if err := queue.ProcessBatch(cmd.Context(), app, client, opts); err != nil {
				log.Fatal(err)
			}
		},
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
