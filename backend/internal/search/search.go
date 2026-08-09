package search

import (
	"errors"
	"strings"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"

	"ocrsearch/backend/internal/fts"
)

var ErrMissingQuery = errors.New("missing q parameter")

// RunSearch executes the search logic shared by the HTTP handler and tests.
func RunSearch(app core.App, q string) ([]fts.SearchResult, error) {
	q = strings.TrimSpace(q)
	if q == "" {
		return nil, ErrMissingQuery
	}
	return fts.Search(app, q, 50)
}

// RegisterRoutes mounts GET /api/search behind auth.
func RegisterRoutes(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/search", func(e *core.RequestEvent) error {
			results, err := RunSearch(e.App, e.Request.URL.Query().Get("q"))
			if err != nil {
				if errors.Is(err, ErrMissingQuery) {
					return e.BadRequestError(err.Error(), nil)
				}
				return e.InternalServerError("search failed", err)
			}
			return e.JSON(200, results)
		}).Bind(apis.RequireAuth())
		return e.Next()
	})
}
