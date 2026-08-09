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
	if len(gotBody.Messages) != 1 {
		t.Fatalf("messages len = %d, want 1", len(gotBody.Messages))
	}
	msg := gotBody.Messages[0]
	if msg.Role != "user" {
		t.Errorf("role = %q, want user", msg.Role)
	}
	if len(msg.Content) != 2 {
		t.Fatalf("content parts len = %d, want 2", len(msg.Content))
	}
	if msg.Content[0].Type != "text" || msg.Content[0].Text == "" {
		t.Errorf("text part = %+v, want non-empty prompt", msg.Content[0])
	}
	if msg.Content[1].Type != "image_url" || msg.Content[1].ImageURL == nil {
		t.Fatalf("image part = %+v, want image_url", msg.Content[1])
	}
	wantPrefix := "data:image/png;base64,"
	if !strings.HasPrefix(msg.Content[1].ImageURL.URL, wantPrefix) {
		t.Errorf("image url = %q, want prefix %q", msg.Content[1].ImageURL.URL, wantPrefix)
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
