# Single-VPS Deployment

This guide deploys the PocketBase executable and embedded Flutter Web app on one Linux VPS. SeaweedFS runs separately on the same VPS as the S3-compatible file store. A TLS-enabled reverse proxy publishes the application; neither PocketBase nor SeaweedFS needs a public listening port.

## Architecture

- `ocr-search` serves the Flutter app, PocketBase API, and admin UI from one origin on `127.0.0.1:8090`.
- SeaweedFS runs as a separate service and exposes its S3 API to the VPS at `127.0.0.1:9000`.
- A reverse proxy terminates HTTPS and forwards requests to PocketBase.
- PocketBase's database and local metadata live under `PB_DATA_DIR`; uploaded objects use SeaweedFS when S3 is configured.

The standalone binary does not contain credentials or SeaweedFS. The host-run binary uses `http://127.0.0.1:9000` for S3. The Compose-hosted PocketBase container uses the internal address `http://seaweedfs:8333` instead.

## Build the Binary

Build on a workstation with Go, Flutter, Docker Buildx, and the Docker engine available. From the repository root, install the pinned Task tool and Flutter dependencies, then build for the VPS architecture:

```sh
go tool task install
go tool task build
```

The default output is `dist/ocr-search` for Linux `amd64`. For an ARM64 VPS, use:

```sh
go tool task build PLATFORM=linux/arm64
```

Copy the matching binary to the VPS and install it, for example:

```sh
scp dist/ocr-search deploy@YOUR_VPS:/tmp/ocr-search
ssh deploy@YOUR_VPS 'sudo install -o root -g root -m 0755 /tmp/ocr-search /usr/local/bin/ocr-search'
```

Build the binary again whenever the frontend or backend changes; the Flutter Web files are embedded during the build.

## Start SeaweedFS

The repository Compose file can run only the SeaweedFS service while PocketBase runs as a host binary. On the VPS, create the root `.env` from `.env.example` without committing it. Set `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and `S3_BUCKET` to production values. Do not use the development `minioadmin` defaults.

Start SeaweedFS from the repository root:

```sh
docker compose up -d seaweedfs
docker compose ps seaweedfs
```

The Compose port binding keeps the S3 API on loopback at `127.0.0.1:9000`. Keep the `seaweedfs-data` volume; do not use `docker compose down -v` for routine shutdowns. If MinIO contains files that must be retained, migrate them separately before switching to SeaweedFS; this setup does not migrate MinIO objects.

## Configure PocketBase

Create a dedicated service account, a writable data directory, and a root-readable environment file. Adapt account and directory commands to the VPS distribution if needed:

```sh
sudo useradd --system --home-dir /var/lib/ocr-search --shell /usr/sbin/nologin ocrsearch
sudo install -d -o ocrsearch -g ocrsearch -m 0750 /var/lib/ocr-search
sudo install -d -o root -g root -m 0700 /etc/ocr-search
sudoedit /etc/ocr-search/ocr-search.env
sudo chown root:root /etc/ocr-search/ocr-search.env
sudo chmod 0600 /etc/ocr-search/ocr-search.env
```

Set the runtime variables in `/etc/ocr-search/ocr-search.env`:

```dotenv
PB_DATA_DIR=/var/lib/ocr-search/pb_data
PB_PUBLIC_URL=https://ocr.example.com
S3_ENDPOINT=http://127.0.0.1:9000
S3_BUCKET=pages
S3_ACCESS_KEY=REPLACE_WITH_STRONG_ACCESS_KEY
S3_SECRET_KEY=REPLACE_WITH_STRONG_SECRET
S3_REGION=us-east-1
OCR_API_KEY=REPLACE_WITH_OCR_PROVIDER_KEY
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
```

Replace the example hostname and placeholder credentials. Keep this file out of source control. `OCR_API_KEY` is required to process uploaded pages; other flows can run without it. Set the Google OAuth variables only when OAuth is configured. The app rejects an enabled S3 endpoint without `S3_ACCESS_KEY`; SeaweedFS also needs matching access and secret values.

## Run PocketBase with systemd

Create `/etc/systemd/system/ocr-search.service`:

```ini
[Unit]
Description=OCR Search PocketBase
After=network-online.target
Wants=network-online.target

[Service]
User=ocrsearch
Group=ocrsearch
EnvironmentFile=/etc/ocr-search/ocr-search.env
ExecStart=/usr/local/bin/ocr-search serve --http=127.0.0.1:8090
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Start the service after SeaweedFS is running:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now ocr-search
sudo systemctl status --no-pager ocr-search
curl --fail http://127.0.0.1:8090/api/health
```

The service runs PocketBase on loopback only. Put a TLS-enabled reverse proxy on the public interface and proxy the application hostname to `http://127.0.0.1:8090`. Forward the original host and HTTPS scheme so PocketBase can construct public URLs correctly. Allow public access only to the proxy's web ports and required administration access; do not expose ports `8090` or `9000` directly.

## First-Run Setup

Open `https://ocr.example.com/_/` and create a PocketBase superuser. There is no default superuser username or password. Add the permitted Google account email to `allowed_users`.

If Google OAuth is enabled, configure its callback URL as:

```text
https://ocr.example.com/api/oauth2-redirect
```

Keep `PB_PUBLIC_URL`, the reverse-proxy hostname, and the OAuth callback URL aligned. Do not put superuser or provider credentials in this guide or in source control.

## Verify and Operate

- Open `https://ocr.example.com/` and confirm the Flutter app loads from PocketBase.
- Open `https://ocr.example.com/api/health` and confirm PocketBase responds.
- Confirm file uploads are stored in the configured SeaweedFS bucket.
- After replacing the binary, run `sudo systemctl restart ocr-search` and check `sudo journalctl -u ocr-search` if it does not start.
- Back up both `PB_DATA_DIR` and SeaweedFS data. The database and uploaded objects are separate persistence layers and both are needed for a complete restore.

For the Compose production-image alternative and local-development workflow, see the repository [README](../README.md).
