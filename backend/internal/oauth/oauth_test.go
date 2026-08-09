package oauth

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"

	_ "ocrsearch/backend/internal/migrations"
)

func newTestApp(t *testing.T) *tests.TestApp {
	t.Helper()
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatalf("NewTestApp() error: %v", err)
	}
	t.Cleanup(app.Cleanup)
	return app
}

func seedAllowedUser(t *testing.T, app core.App, email string) {
	t.Helper()
	col, err := app.FindCollectionByNameOrId("allowed_users")
	if err != nil {
		t.Fatal(err)
	}
	rec := core.NewRecord(col)
	rec.Set("email", email)
	if err := app.Save(rec); err != nil {
		t.Fatalf("save allowed_user: %v", err)
	}
}

func TestIsAllowedTrue(t *testing.T) {
	app := newTestApp(t)
	seedAllowedUser(t, app, "bob@gmail.com")

	allowed, err := IsAllowed(app, "bob@gmail.com")
	if err != nil {
		t.Fatalf("IsAllowed() error: %v", err)
	}
	if !allowed {
		t.Error("IsAllowed() = false, want true for whitelisted email")
	}
}

func TestIsAllowedFalse(t *testing.T) {
	app := newTestApp(t)
	seedAllowedUser(t, app, "bob@gmail.com")

	allowed, err := IsAllowed(app, "mallory@gmail.com")
	if err != nil {
		t.Fatalf("IsAllowed() error: %v", err)
	}
	if allowed {
		t.Error("IsAllowed() = true, want false for non-whitelisted email")
	}
}

func TestIsAllowedEmptyEmail(t *testing.T) {
	app := newTestApp(t)

	allowed, err := IsAllowed(app, "")
	if err != nil {
		t.Fatalf("IsAllowed() error: %v", err)
	}
	if allowed {
		t.Error("IsAllowed() = true for empty email, want false")
	}
}

func TestIsAllowedExactMatch(t *testing.T) {
	app := newTestApp(t)
	seedAllowedUser(t, app, "bob@gmail.com")

	allowed, err := IsAllowed(app, "Bob@gmail.com")
	if err != nil {
		t.Fatalf("IsAllowed() error: %v", err)
	}
	if allowed {
		t.Error("IsAllowed() = true for differently-cased email, want false (exact match)")
	}
}
