package ocr

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const defaultPrompt = "Extract all legible text from this image accurately."

type Config struct {
	BaseURL string
	APIKey  string
	Model   string
	Timeout time.Duration
}

type Client struct {
	baseURL string
	apiKey  string
	model   string
	http    *http.Client
}

type ContentPart struct {
	Type     string    `json:"type"`
	Text     string    `json:"text,omitempty"`
	ImageURL *ImageURL `json:"image_url,omitempty"`
}

type ImageURL struct {
	URL string `json:"url"`
}

type Message struct {
	Role    string        `json:"role"`
	Content []ContentPart `json:"content"`
}

type chatCompletionRequest struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
}

type chatCompletionResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

func NewClient(cfg Config) *Client {
	if cfg.BaseURL == "" {
		cfg.BaseURL = "https://openrouter.ai/api/v1"
	}
	if cfg.Model == "" {
		cfg.Model = "google/gemini-2.5-flash"
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 120 * time.Second
	}
	return &Client{
		baseURL: strings.TrimRight(cfg.BaseURL, "/"),
		apiKey:  cfg.APIKey,
		model:   cfg.Model,
		http:    &http.Client{Timeout: cfg.Timeout},
	}
}

func (c *Client) ExtractText(ctx context.Context, imageData []byte, mime string) (string, error) {
	if mime == "" {
		mime = http.DetectContentType(imageData)
	}

	reqBody := chatCompletionRequest{
		Model: c.model,
		Messages: []Message{{
			Role: "user",
			Content: []ContentPart{
				{Type: "text", Text: defaultPrompt},
				{
					Type: "image_url",
					ImageURL: &ImageURL{
						URL: fmt.Sprintf("data:%s;base64,%s", mime, base64.StdEncoding.EncodeToString(imageData)),
					},
				},
			},
		}},
	}

	payload, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/chat/completions", bytes.NewReader(payload))
	if err != nil {
		return "", fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("ocr provider returned status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var out chatCompletionResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}
	if len(out.Choices) == 0 {
		return "", fmt.Errorf("ocr provider returned no choices")
	}

	return out.Choices[0].Message.Content, nil
}
