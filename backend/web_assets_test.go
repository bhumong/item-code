package main

import "testing"

func TestEmbeddedWebAssetsContainIndex(t *testing.T) {
	index, err := embeddedWebAssets.ReadFile("web/dist/index.html")
	if err != nil {
		t.Fatalf("failed to read embedded index.html: %v", err)
	}
	if len(index) == 0 {
		t.Fatal("embedded index.html is empty")
	}
}
