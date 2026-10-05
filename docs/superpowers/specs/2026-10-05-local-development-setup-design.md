# Local Development Setup Design

**Date:** 2026-10-05
**Status:** Approved in conversation; awaiting written-spec review

## Purpose

Provide a reliable local run path for the existing OCR Search application: PocketBase and MinIO run with Docker Compose, while the Flutter Web app runs with the host Flutter SDK and talks to PocketBase at `http://localhost:8090`.

## User-visible workflow

1. Keep `.env` local and ignored by Git. If it is absent, create it from `.env.example` without overwriting an existing file; fill in Google OAuth and OCR credentials when those capabilities are needed.
2. Start the backend stack with Docker Compose. The backend must wait for MinIO to become healthy and for the bucket initialization service to complete successfully.
3. On first use, open PocketBase at `http://localhost:8090/_/`, create a superuser, and add the Google account email to `allowed_users`. Google OAuth uses the callback URL `http://localhost:8090/api/oauth2-redirect`; OAuth credentials must be set in `.env` and the backend container recreated after changes.
4. From `frontend/`, fetch Flutter packages and run the web-server device on port 8080 with `BACKEND_URL=http://localhost:8090`. Open `http://localhost:8080` in a browser.
5. A real `OCR_API_KEY` is required for uploaded pages to be processed by the OCR provider. The application can otherwise be launched and used for flows that do not require OCR.

The documentation will explain service URLs, health checks, normal shutdown, and that `docker compose down` preserves named data volumes. It will not include or print credentials.

## Scope and files

- Add a root `README.md` with the end-to-end local quickstart, first-run PocketBase setup, OAuth/allowlist prerequisites, OCR configuration, and verification commands.
- Replace the generated placeholder text in `frontend/README.md` with a concise pointer to the root guide and the frontend run command.
- Update `docker-compose.yml` so the backend depends on successful completion of `minio-init`, in addition to MinIO health.

No frontend container, deployment configuration, secret seeding, or application feature changes are included. `.env` is user-owned local configuration and must remain untracked and untouched.

## Verification

- Validate Compose configuration without printing resolved environment values.
- Run backend Go tests from `backend/`.
- Run `flutter analyze`, `flutter test`, and `flutter build web` from `frontend/`.
- When local Docker/browser tools are available, start the stack, check PocketBase health, and smoke-test that the Flutter Web app loads.
