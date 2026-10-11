# OCR Search

Local development runs PocketBase and SeaweedFS with Docker Compose. SeaweedFS provides the S3-compatible object-storage endpoint; the Flutter Web app runs on the host and connects to PocketBase at `http://localhost:8090`.

## Prerequisites

- Go 1.26.5 or newer
- Docker with the Docker Compose plugin
- Flutter SDK with a Dart version satisfying `frontend/pubspec.yaml`

## Quickstart

1. If `.env` does not already exist, copy `.env.example` to `.env`. Do not overwrite an existing `.env`; it is your local configuration.
2. Install the Go tool and Flutter dependencies:

   ```sh
   go tool task install
   ```

3. Start the local services and Flutter Web:

   ```sh
   go tool task dev
   ```

4. Open `http://localhost:8080`.

The `dev` task checks that `.env` exists without displaying its contents, starts Docker Compose, waits for PocketBase health, and then runs Flutter Web on port `8080` with `BACKEND_URL=http://localhost:8090`. Press Ctrl+C to stop Flutter and the Compose services. Named data volumes are preserved.

SeaweedFS reads `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and `S3_BUCKET` from the existing `.env` through Compose. It creates the configured bucket during startup, and its S3 API is available at `http://localhost:9000`.

## Production Deployment

Run the production target with:

```sh
go tool task install
go tool task prod
```

The `prod` task builds Flutter Web with the host Flutter SDK, then builds the production PocketBase image with those static assets embedded in the Go executable. PocketBase serves the UI and API from the same origin at `http://localhost:8090`; no separate frontend process or container is used. The embedded app defaults to the current page origin, so `BACKEND_URL` does not need a production-specific value. Flutter routes such as `/login` fall back to the embedded `index.html`.

For a public VPS, place a TLS-enabled reverse proxy in front of `127.0.0.1:8090`. SeaweedFS S3 is bound to `127.0.0.1:9000` and is not exposed on the public interface.

For a complete standalone-binary deployment walkthrough, see [Single-VPS Deployment](docs/single-vps-deployment.md).

## Standalone Binary

After `go tool task install`, build a Linux binary containing both PocketBase and the Flutter Web assets:

```sh
go tool task build
```

The output is `dist/ocr-search` for `linux/amd64` by default. For an ARM64 VPS, run `go tool task build PLATFORM=linux/arm64`. The binary still needs runtime environment variables (including `PB_DATA_DIR` and the SeaweedFS S3 settings); credentials are not embedded. When the binary runs on the host alongside the Compose SeaweedFS service, set its S3 endpoint to `http://127.0.0.1:9000`.

## Services

| Service | URL |
| --- | --- |
| Flutter Web app (development) | `http://localhost:8080` |
| PocketBase API and embedded production app | `http://localhost:8090` |
| PocketBase health check | `http://localhost:8090/api/health` |
| PocketBase admin UI | `http://localhost:8090/_/` |
| SeaweedFS S3 API | `http://localhost:9000` |

## First-run setup

On first use, open the PocketBase admin UI at `http://localhost:8090/_/` and create a superuser. Add the Google account email that will sign in to the `allowed_users` collection.

To enable Google OAuth, configure `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` in your local `.env`. Set the OAuth callback URL to:

```text
http://localhost:8090/api/oauth2-redirect
```

After changing OAuth credentials, recreate the backend container so it loads the updated environment:

```sh
docker compose up -d --force-recreate backend
```

Do not put credentials in this README or commit `.env`.

## OCR configuration

A real `OCR_API_KEY` in `.env` is required to process uploaded pages. The application can still be launched and used for flows that do not require OCR without a real OCR key.

## Stopping services

Press Ctrl+C while `go tool task dev` is running to stop Flutter and the Compose services. To stop the Docker stack separately, run:

```sh
go tool task down
```

Both shutdown paths preserve the named PocketBase and SeaweedFS data volumes. SeaweedFS uses a new data volume; MinIO objects are not migrated automatically. Back up or migrate any MinIO objects you still need before switching storage backends.
