package oauth

import (
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// IsAllowed reports whether email is present in the allowed_users whitelist.
func IsAllowed(app core.App, email string) (bool, error) {
	if email == "" {
		return false, nil
	}
	records, err := app.FindRecordsByFilter(
		"allowed_users",
		"email = {:email}",
		"",
		1,
		0,
		dbx.Params{"email": email},
	)
	if err != nil {
		return false, err
	}
	return len(records) > 0, nil
}

// RegisterHooks binds the Google OAuth whitelist check. Non-whitelisted
// emails abort authentication with a 403.
func RegisterHooks(app core.App) {
	app.OnRecordAuthWithOAuth2Request("users").BindFunc(func(e *core.RecordAuthWithOAuth2RequestEvent) error {
		if e.OAuth2User == nil || e.OAuth2User.Email == "" {
			return e.ForbiddenError("Email is not whitelisted", nil)
		}
		allowed, err := IsAllowed(e.App, e.OAuth2User.Email)
		if err != nil {
			return e.InternalServerError("Failed to verify whitelist", err)
		}
		if !allowed {
			return e.ForbiddenError("Your email is not whitelisted", nil)
		}
		return e.Next()
	})
}
