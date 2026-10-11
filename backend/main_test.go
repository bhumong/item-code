package main

import "testing"

func TestNewPocketBaseAppUsesConfiguredDataDir(t *testing.T) {
	wantDataDir := t.TempDir()
	app := newPocketBaseApp(wantDataDir)

	if gotDataDir := app.DataDir(); gotDataDir != wantDataDir {
		t.Fatalf("DataDir() = %q, want %q", gotDataDir, wantDataDir)
	}
}
