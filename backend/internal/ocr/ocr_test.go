package ocr

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestExtractTextSuccess(t *testing.T) {
	var gotBody chatCompletionRequest
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer sk-test" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer sk-test")
		}
		if ct := r.Header.Get("Content-Type"); ct != "application/json" {
			t.Errorf("Content-Type = %q, want application/json", ct)
		}
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"Extracted page text"}}]}`))
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "sk-test", Model: "google/gemini-test"})
	text, err := c.ExtractText(context.Background(), []byte("fake-image-bytes"), "image/png")
	if err != nil {
		t.Fatalf("ExtractText() error: %v", err)
	}
	if text != "Extracted page text" {
		t.Errorf("text = %q, want %q", text, "Extracted page text")
	}

	if gotBody.Model != "google/gemini-test" {
		t.Errorf("request model = %q", gotBody.Model)
	}
	if gotBody.Temperature != 0 {
		t.Errorf("request temperature = %v, want 0", gotBody.Temperature)
	}
	if len(gotBody.Messages) != 2 {
		t.Fatalf("messages len = %d, want 2 (system + user)", len(gotBody.Messages))
	}
	sys := gotBody.Messages[0]
	if sys.Role != "system" {
		t.Errorf("messages[0] role = %q, want system", sys.Role)
	}
	if len(sys.Content) != 1 || sys.Content[0].Type != "text" {
		t.Fatalf("system content = %+v, want single text part", sys.Content)
	}
	if !strings.Contains(sys.Content[0].Text, "high-precision Optical Character Recognition") {
		t.Errorf("system prompt missing high-precision intro: %q", sys.Content[0].Text)
	}
	user := gotBody.Messages[1]
	if user.Role != "user" {
		t.Errorf("messages[1] role = %q, want user", user.Role)
	}
	if len(user.Content) != 1 || user.Content[0].Type != "image_url" || user.Content[0].ImageURL == nil {
		t.Fatalf("user content = %+v, want single image_url part", user.Content)
	}
	wantPrefix := "data:image/png;base64,"
	if !strings.HasPrefix(user.Content[0].ImageURL.URL, wantPrefix) {
		t.Errorf("image url = %q, want prefix %q", user.Content[0].ImageURL.URL, wantPrefix)
	}
}

func TestExtractTextSendsTemperature(t *testing.T) {
	var raw map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"ok"}}]}`))
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "k", Model: "m", Temperature: 0.5})
	if _, err := c.ExtractText(context.Background(), []byte("x"), "image/png"); err != nil {
		t.Fatalf("ExtractText() error: %v", err)
	}
	temp, ok := raw["temperature"].(float64)
	if !ok || temp != 0.5 {
		t.Errorf("temperature = %v (%T), want 0.5", raw["temperature"], raw["temperature"])
	}
}

func TestExtractTextHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "bad", Model: "m"})
	if _, err := c.ExtractText(context.Background(), []byte("x"), "image/png"); err == nil {
		t.Fatal("ExtractText() = nil error, want error on 401")
	}
}

func TestExtractTextEmptyChoices(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[]}`))
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "k", Model: "m"})
	if _, err := c.ExtractText(context.Background(), []byte("x"), "image/png"); err == nil {
		t.Fatal("ExtractText() = nil error, want error when no choices")
	}
}

func TestExtractTextTimeout(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(300 * time.Millisecond)
	}))
	defer srv.Close()

	c := NewClient(Config{BaseURL: srv.URL, APIKey: "k", Model: "m", Timeout: 50 * time.Millisecond})
	if _, err := c.ExtractText(context.Background(), []byte("x"), "image/png"); err == nil {
		t.Fatal("ExtractText() = nil error, want timeout error")
	}
}
