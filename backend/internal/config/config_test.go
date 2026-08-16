package config

import (
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/tests"
)

func TestLoadDefaults(t *testing.T) {
	t.Setenv("S3_ENDPOINT", "")
	t.Setenv("OCR_API_KEY", "")
	t.Setenv("OCR_MODEL", "")
	t.Setenv("OCR_CONCURRENCY", "")
	t.Setenv("OCR_RETRY_MAX", "")
	t.Setenv("OCR_TIMEOUT", "")
	t.Setenv("OCR_TEMPERATURE", "")
	t.Setenv("GOOGLE_OAUTH_CLIENT_ID", "")
	t.Setenv("GOOGLE_OAUTH_CLIENT_SECRET", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if cfg.DataDir != "./pb_data" {
		t.Errorf("DataDir = %q, want %q", cfg.DataDir, "./pb_data")
	}
	if cfg.S3.Enabled {
		t.Error("S3.Enabled = true, want false when S3_ENDPOINT unset")
	}
	if cfg.OCR.BaseURL != "https://openrouter.ai/api/v1" {
		t.Errorf("OCR.BaseURL = %q, want default", cfg.OCR.BaseURL)
	}
	if cfg.OCR.Model != "google/gemini-2.5-flash" {
		t.Errorf("OCR.Model = %q, want default", cfg.OCR.Model)
	}
	if cfg.OCR.Concurrency != 5 {
		t.Errorf("OCR.Concurrency = %d, want 5", cfg.OCR.Concurrency)
	}
	if cfg.OCR.RetryMax != 3 {
		t.Errorf("OCR.RetryMax = %d, want 3", cfg.OCR.RetryMax)
	}
	if cfg.OCR.Timeout != 120*time.Second {
		t.Errorf("OCR.Timeout = %v, want 120s", cfg.OCR.Timeout)
	}
	if cfg.OCR.Temperature != 0 {
		t.Errorf("OCR.Temperature = %v, want 0 (default)", cfg.OCR.Temperature)
	}
}

func TestLoadOverrides(t *testing.T) {
	t.Setenv("PB_DATA_DIR", "/tmp/pb")
	t.Setenv("S3_ENDPOINT", "http://localhost:9000")
	t.Setenv("S3_ACCESS_KEY", "minioadmin")
	t.Setenv("S3_SECRET_KEY", "minioadmin")
	t.Setenv("OCR_API_KEY", "sk-test")
	t.Setenv("OCR_MODEL", "google/gemini-3")
	t.Setenv("OCR_CONCURRENCY", "7")
	t.Setenv("OCR_TIMEOUT", "30s")
	t.Setenv("OCR_TEMPERATURE", "0.5")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if cfg.DataDir != "/tmp/pb" {
		t.Errorf("DataDir = %q, want /tmp/pb", cfg.DataDir)
	}
	if !cfg.S3.Enabled {
		t.Error("S3.Enabled = false, want true when S3_ENDPOINT set")
	}
	if cfg.S3.Endpoint != "http://localhost:9000" {
		t.Errorf("S3.Endpoint = %q", cfg.S3.Endpoint)
	}
	if cfg.S3.Bucket != "pages" {
		t.Errorf("S3.Bucket = %q, want pages", cfg.S3.Bucket)
	}
	if cfg.OCR.APIKey != "sk-test" {
		t.Errorf("OCR.APIKey = %q", cfg.OCR.APIKey)
	}
	if cfg.OCR.Model != "google/gemini-3" {
		t.Errorf("OCR.Model = %q", cfg.OCR.Model)
	}
	if cfg.OCR.Concurrency != 7 {
		t.Errorf("OCR.Concurrency = %d, want 7", cfg.OCR.Concurrency)
	}
	if cfg.OCR.Timeout != 30*time.Second {
		t.Errorf("OCR.Timeout = %v, want 30s", cfg.OCR.Timeout)
	}
	if cfg.OCR.Temperature != 0.5 {
		t.Errorf("OCR.Temperature = %v, want 0.5", cfg.OCR.Temperature)
	}
}

func TestLoadErrorsWhenS3EnabledWithoutKeys(t *testing.T) {
	t.Setenv("S3_ENDPOINT", "http://localhost:9000")
	t.Setenv("S3_ACCESS_KEY", "")
	if _, err := Load(); err == nil {
		t.Fatal("Load() = nil error, want error when S3 enabled without access key")
	}
}

func TestApplySettings(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	defer app.Cleanup()

	cfg := Config{
		S3: S3Config{
			Enabled:        true,
			Endpoint:       "http://localhost:9000",
			Bucket:         "pages",
			AccessKey:      "minioadmin",
			SecretKey:      "minioadmin",
			Region:         "us-east-1",
			ForcePathStyle: true,
		},
		OAuth: OAuthConfig{
			GoogleClientID:     "client-id",
			GoogleClientSecret: "client-secret",
		},
	}

	if err := ApplySettings(app, cfg); err != nil {
		t.Fatalf("ApplySettings() error: %v", err)
	}

	settings := app.Settings()
	if !settings.S3.Enabled {
		t.Error("settings.S3.Enabled = false, want true")
	}
	if settings.S3.Endpoint != "http://localhost:9000" {
		t.Errorf("settings.S3.Endpoint = %q", settings.S3.Endpoint)
	}
	if settings.S3.AccessKey != "minioadmin" {
		t.Errorf("settings.S3.AccessKey = %q", settings.S3.AccessKey)
	}
	if settings.Meta.AppName != "OCR Search" {
		t.Errorf("settings.Meta.AppName = %q, want OCR Search", settings.Meta.AppName)
	}

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatalf("find users collection: %v", err)
	}
	if !users.OAuth2.Enabled {
		t.Error("users.OAuth2.Enabled = false, want true")
	}
	if len(users.OAuth2.Providers) != 1 {
		t.Fatalf("users.OAuth2.Providers len = %d, want 1", len(users.OAuth2.Providers))
	}
	if users.OAuth2.Providers[0].Name != "google" {
		t.Errorf("provider name = %q, want google", users.OAuth2.Providers[0].Name)
	}
	if users.OAuth2.Providers[0].ClientId != "client-id" {
		t.Errorf("provider clientId = %q", users.OAuth2.Providers[0].ClientId)
	}
}

func TestApplySettingsSkipsOAuthWhenEnvEmpty(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	defer app.Cleanup()

	cfg := Config{}
	if err := ApplySettings(app, cfg); err != nil {
		t.Fatalf("ApplySettings() error: %v", err)
	}

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatalf("find users collection: %v", err)
	}
	if users.OAuth2.Enabled {
		t.Error("users.OAuth2.Enabled = true, want false when no OAuth env set")
	}
}
