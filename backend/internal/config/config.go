package config

import (
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

type Config struct {
	DataDir string

	S3    S3Config
	OCR   OCRConfig
	OAuth OAuthConfig
}

type S3Config struct {
	Enabled        bool
	Endpoint       string
	Bucket         string
	AccessKey      string
	SecretKey      string
	Region         string
	ForcePathStyle bool
}

type OCRConfig struct {
	BaseURL     string
	APIKey      string
	Model       string
	Concurrency int
	RetryMax    int
	Timeout     time.Duration
}

type OAuthConfig struct {
	GoogleClientID     string
	GoogleClientSecret string
}

func Load() (Config, error) {
	cfg := Config{
		DataDir: getenv("PB_DATA_DIR", "./pb_data"),
		S3: S3Config{
			Enabled:        os.Getenv("S3_ENDPOINT") != "",
			Endpoint:       os.Getenv("S3_ENDPOINT"),
			Bucket:         getenv("S3_BUCKET", "pages"),
			AccessKey:      os.Getenv("S3_ACCESS_KEY"),
			SecretKey:      os.Getenv("S3_SECRET_KEY"),
			Region:         getenv("S3_REGION", "us-east-1"),
			ForcePathStyle: true,
		},
		OCR: OCRConfig{
			BaseURL:     getenv("OCR_BASE_URL", "https://openrouter.ai/api/v1"),
			APIKey:      os.Getenv("OCR_API_KEY"),
			Model:       getenv("OCR_MODEL", "google/gemini-2.5-flash"),
			Concurrency: getenvInt("OCR_CONCURRENCY", 5),
			RetryMax:    getenvInt("OCR_RETRY_MAX", 3),
			Timeout:     getenvDuration("OCR_TIMEOUT", 120*time.Second),
		},
		OAuth: OAuthConfig{
			GoogleClientID:     os.Getenv("GOOGLE_OAUTH_CLIENT_ID"),
			GoogleClientSecret: os.Getenv("GOOGLE_OAUTH_CLIENT_SECRET"),
		},
	}

	if cfg.S3.Enabled && cfg.S3.AccessKey == "" {
		return cfg, fmt.Errorf("S3_ENDPOINT is set but S3_ACCESS_KEY is empty")
	}

	return cfg, nil
}

// ApplySettings persists env-driven PocketBase settings (S3 storage, meta, and
// the Google OAuth2 provider on the users auth collection). It is safe to call
// on every boot because it is idempotent.
func ApplySettings(app core.App, cfg Config) error {
	settings := app.Settings()
	settings.Meta.AppName = "OCR Search"
	settings.Meta.AppURL = getenv("PB_PUBLIC_URL", "http://localhost:8090")

	if cfg.S3.Enabled {
		settings.S3.Enabled = true
		settings.S3.Endpoint = cfg.S3.Endpoint
		settings.S3.Bucket = cfg.S3.Bucket
		settings.S3.Region = cfg.S3.Region
		settings.S3.AccessKey = cfg.S3.AccessKey
		settings.S3.Secret = cfg.S3.SecretKey
		settings.S3.ForcePathStyle = cfg.S3.ForcePathStyle
	} else {
		settings.S3.Enabled = false
	}

	if err := app.Save(settings); err != nil {
		return fmt.Errorf("failed to save settings: %w", err)
	}

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		return fmt.Errorf("failed to find users collection: %w", err)
	}

	if cfg.OAuth.GoogleClientID != "" && cfg.OAuth.GoogleClientSecret != "" {
		users.OAuth2.Enabled = true
		users.OAuth2.Providers = []core.OAuth2ProviderConfig{{
			Name:         "google",
			ClientId:     cfg.OAuth.GoogleClientID,
			ClientSecret: cfg.OAuth.GoogleClientSecret,
		}}
	} else {
		// Explicitly disable Google login when no credentials are configured
		// (PocketBase enables OAuth2 on auth collections by default).
		users.OAuth2.Enabled = false
		users.OAuth2.Providers = nil
	}
	if err := app.Save(users); err != nil {
		return fmt.Errorf("failed to save users oauth config: %w", err)
	}

	return nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getenvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func getenvDuration(key string, fallback time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return fallback
}
