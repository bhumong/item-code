# Local Development Setup Design

**Date:** 2026-10-05
**Status:** Revised per user direction; awaiting written-spec review

## Purpose

Provide one repeatable local development command for the existing OCR Search application: PocketBase and MinIO run with Docker Compose, while the Flutter Web app runs with the host Flutter SDK and talks to PocketBase at `http://localhost:8090`.

## User-visible workflow

1. Run `go tool task dev` from the repository root. The root Go module pins Task and mockgen as Go tools; the command needs Go but does not need a globally installed Task binary.
2. The Taskfile `install` task downloads the root Go tool dependencies and Flutter packages. The `dev` task checks that `.env` exists without displaying or overwriting it, starts Docker Compose, waits for PocketBase health, then runs Flutter Web on port 8080 with `BACKEND_URL=http://localhost:8090`.
3. Open `http://localhost:8080` in a browser. Pressing Ctrl+C stops the Flutter process and Docker services while preserving named data volumes. `go tool task down` is available to stop the Docker stack separately.
4. On first use, open PocketBase at `http://localhost:8090/_/`, create a superuser, and add the Google account email to `allowed_users`. Google OAuth uses the callback URL `http://localhost:8090/api/oauth2-redirect`; OAuth credentials must be set in `.env` and the backend container recreated after changes.
5. A real `OCR_API_KEY` is required for uploaded pages to be processed by the OCR provider. The application can otherwise be launched and used for flows that do not require OCR.

The documentation will explain service URLs, health checks, the Task commands, first-run PocketBase setup, and that stopping the stack preserves named data volumes. It will not include or print credentials.

## Scope and files

- Add a root `Taskfile.yml` with `install`, `dev`, and `down` tasks. `dev` starts Docker Compose, waits for backend health, runs Flutter Web, and cleans up the services on exit.
- Add a root `go.mod` with Go 1.26.5 tool directives for `github.com/go-task/task/v3/cmd/task` and `go.uber.org/mock/mockgen`.
- Add a concise root `README.md` with the one-command quickstart, first-run PocketBase setup, OAuth/allowlist prerequisites, and OCR configuration.
- Update `docker-compose.yml` so the backend depends on successful completion of `minio-init`, in addition to MinIO health.

No frontend container, deployment configuration, secret seeding, or application feature changes are included. `.env` is user-owned local configuration and must remain untracked and untouched.

## Verification

- Validate the Taskfile and Compose configuration without printing resolved environment values.
- Run backend Go tests from `backend/`.
- Run `flutter analyze`, `flutter test`, and `flutter build web` from `frontend/`.
- When local Docker/browser tools are available, run `go tool task dev`, check PocketBase health, and smoke-test that the Flutter Web app loads.
