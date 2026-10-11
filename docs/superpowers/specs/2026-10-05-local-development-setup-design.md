# Local Development Setup Design

**Date:** 2026-10-05
**Status:** Approved by user on 2026-10-05

## Purpose

Provide repeatable local development and production workflows for the existing OCR Search application. In development, PocketBase and SeaweedFS run with Docker Compose while Flutter Web runs on the host. In production, Flutter Web assets are embedded in the PocketBase executable, which serves both the UI and API from one origin.

## Production Workflow

Run `go tool task install` once, then `go tool task prod` from the repository root. The production task compiles Flutter Web with the host Flutter SDK; the production Docker build embeds those generated assets in the Go executable with `go:embed` and starts that executable with PocketBase. PocketBase serves the app and API on port `8090`; SeaweedFS remains a separate object-storage service. No separate frontend server or container is required. When `BACKEND_URL` is not defined, Flutter uses the current page origin; development continues to override it with `http://localhost:8090`. SPA paths such as `/login` must return the embedded `index.html` on refresh.

After `go tool task install`, `go tool task build` exports a standalone `dist/ocr-search` Linux binary from the same embedded-web build. The default target is `linux/amd64`; `PLATFORM=linux/arm64` selects ARM64. The binary still requires runtime configuration and an external SeaweedFS service.

## User-visible workflow

1. Run `go tool task dev` from the repository root. The root Go module pins Task as Go tools; the command needs Go but does not need a globally installed Task binary.
2. The Taskfile `install` task downloads the root Go tool dependencies and Flutter packages. The `dev` task checks that `.env` exists without displaying or overwriting it, starts Docker Compose, waits for PocketBase health, then runs Flutter Web on port 8080 with `BACKEND_URL=http://localhost:8090`.
3. Open `http://localhost:8080` in a browser. Pressing Ctrl+C stops the Flutter process and Docker services while preserving named data volumes. `go tool task down` is available to stop the Docker stack separately.
4. On first use, open PocketBase at `http://localhost:8090/_/`, create a superuser, and add the Google account email to `allowed_users`. Google OAuth uses the callback URL `http://localhost:8090/api/oauth2-redirect`; OAuth credentials must be set in `.env` and the backend container recreated after changes.
5. A real `OCR_API_KEY` is required for uploaded pages to be processed by the OCR provider. The application can otherwise be launched and used for flows that do not require OCR.

The documentation will explain service URLs, health checks, the Task commands, first-run PocketBase setup, and that stopping the stack preserves named data volumes. It will not include or print credentials.

## Scope and files

- Add a root `Taskfile.yml` with `install`, `dev`, and `down` tasks. `dev` starts Docker Compose, waits for backend health, runs Flutter Web, and cleans up the services on exit.
- Add a `prod` Taskfile task and a production Compose override that build and run the PocketBase image containing the embedded Flutter Web assets.
- Add a `build` Taskfile task that exports the embedded PocketBase executable as a standalone Linux binary.
- Use a multi-stage backend Dockerfile: embed the host-built Flutter Web output into the Go binary and use a small runtime image. Keep the default development target Go-only; the build host must have the Flutter SDK.
- Add a PocketBase static route for the embedded web filesystem with SPA index fallback, and default the production web client to the current page origin.
- Add a root `.dockerignore` so the root build context never includes `.env`, local data, or generated Flutter build directories.
- Add a root `go.mod` with Go 1.26.5 tool directives for `github.com/go-task/task/v3/cmd/task`
- Add a concise root `README.md` with the one-command quickstart, first-run PocketBase setup, OAuth/allowlist prerequisites, and OCR configuration.
- Update `docker-compose.yml` to run `chrislusf/seaweedfs:4.48` as the S3-compatible object store, create the configured bucket at startup, expose S3 at `http://localhost:9000`, and start the backend only after SeaweedFS is healthy. The backend uses the internal endpoint `http://seaweedfs:8333`.
- Update backend startup to apply `PB_DATA_DIR` as PocketBase's default data directory so the database is stored in the Compose-mounted `/pb_data` volume.
- Embed the Flutter build output with Go's `embed.FS` and serve it through PocketBase with SPA index fallback. Retain the host Flutter dev server for the local development workflow.
- Preserve the existing MinIO volume without deleting it; existing MinIO objects are not migrated to SeaweedFS.

No separate frontend container, secret seeding, or application feature changes are included. `.env` is user-owned local configuration and must remain untracked and untouched.

## Verification

- Validate the Taskfile and Compose configuration without printing resolved environment values.
- Run backend Go tests from `backend/`.
- Run `flutter analyze`, `flutter test`, and `flutter build web` from `frontend/`.
- When local Docker/browser tools are available, run `go tool task dev`, check PocketBase health, and smoke-test that the Flutter Web app loads.
- Build the production Compose target and verify `/`, a deep link such as `/login`, PocketBase API/admin routes, and embedded Flutter assets.
