# Scalable Image Upload Server

A production-ready image upload backend built with **Node.js + Express**, backed by **AWS S3**, load-balanced by **NGINX** across multiple instances, and fully containerised with **Docker Compose**. A **GitHub Actions** CI pipeline validates every push.

---

## Project Structure

```
Project_pep/
├── src/
│   ├── server.js          # Express app entry point
│   ├── routes/
│   │   └── upload.js      # POST /upload handler
│   └── config/
│       └── s3.js          # AWS S3 client singleton
├── nginx/
│   └── nginx.conf         # NGINX load-balancer config
├── tests/
│   └── upload.test.js     # Jest + supertest tests (S3 mocked)
├── .github/
│   └── workflows/
│       └── ci.yml         # GitHub Actions CI pipeline
├── Dockerfile             # Multi-stage Node.js 20 Alpine image
├── docker-compose.yml     # 2 backend instances + NGINX
├── eslint.config.mjs      # ESLint flat config
├── package.json
└── .env.example           # Environment variable template
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Node.js | 20+ |
| Docker | 24+ |
| Docker Compose | v2 |
| AWS Account | S3 bucket created |

---

## Setup

### 1. Clone and install

```bash
git clone <your-repo-url>
cd Project_pep
npm ci
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
AWS_ACCESS_KEY_ID=your_access_key_id
AWS_SECRET_ACCESS_KEY=your_secret_access_key
AWS_REGION=us-east-1
S3_BUCKET_NAME=your-bucket-name
PORT=3001
```

> **Note:** Make sure your S3 bucket allows public reads (or use the `signed_url` from the response for private buckets).

---

## Running the Server

### Option A — Single instance (local dev)

```bash
npm run dev          # runs on PORT from .env (default 3001)
```

### Option B — Multiple instances manually (no Docker)

Open two terminals:

```bash
# Terminal 1
PORT=3001 node src/server.js

# Terminal 2
PORT=3002 node src/server.js
```

Then point NGINX (or send requests directly) at `:3001` / `:3002`.

### Option C — Docker Compose (recommended, includes NGINX)

```bash
# Build and start all services in the background
docker compose up --build -d

# Check all containers are running
docker compose ps

# Tail logs from both backend instances
docker compose logs -f app1 app2
```

This starts:
| Container | Role | Port |
|-----------|------|------|
| `upload_server_1` | Backend instance 1 | 3001 (internal) |
| `upload_server_2` | Backend instance 2 | 3002 (internal) |
| `nginx_lb` | Load balancer | **80** (public) |

All requests go through **port 80** — NGINX distributes them round-robin.

---

## API Reference

### `POST /upload`

Upload a single image file.

| Property | Value |
|----------|-------|
| Content-Type | `multipart/form-data` |
| Field name | `image` |
| Allowed types | JPEG, PNG |
| Max size | 2 MB |

**Success response `200 OK`:**

```json
{
  "url": "https://your-bucket.s3.us-east-1.amazonaws.com/uploads/550e8400-e29b-41d4-a716-446655440000.jpg",
  "signed_url": "https://your-bucket.s3.us-east-1.amazonaws.com/uploads/...?X-Amz-Signature=...",
  "key": "uploads/550e8400-e29b-41d4-a716-446655440000.jpg",
  "size_bytes": 102400
}
```

**Error responses:**

| Scenario | Status | Body |
|----------|--------|------|
| Non-image file | 400 | `{"error":"Only JPEG and PNG images are allowed"}` |
| File > 2 MB | 400 | `{"error":"File size must not exceed 2 MB"}` |
| No file attached | 400 | `{"error":"No image file provided. Use field name \"image\"."}` |
| S3 not configured | 500 | `{"error":"S3_BUCKET_NAME is not configured on the server."}` |

### `GET /health`

Returns instance info — useful for verifying load-balancer distribution.

```json
{ "status": "ok", "instance": "localhost:3001" }
```

---

## Sample curl Commands

```bash
# Upload a valid JPEG through NGINX (port 80)
curl -X POST http://localhost/upload \
  -F "image=@/path/to/photo.jpg"

# Upload directly to instance 1 (bypass NGINX)
curl -X POST http://localhost:3001/upload \
  -F "image=@/path/to/photo.jpg"

# Upload directly to instance 2 (bypass NGINX)
curl -X POST http://localhost:3002/upload \
  -F "image=@/path/to/photo.jpg"

# Test: expect 400 — wrong file type
curl -X POST http://localhost/upload \
  -F "image=@/path/to/document.txt"

# Test: expect 400 — file too large (> 2 MB)
curl -X POST http://localhost/upload \
  -F "image=@/path/to/large.jpg"

# Health check
curl http://localhost/health
```

---

## Verifying Load Balancing

After several uploads through port 80, run:

```bash
docker compose logs app1 app2 | grep "Uploaded"
```

You will see log lines from both `upload_server_1` and `upload_server_2`, confirming NGINX is distributing requests in round-robin order.

Example output:
```
upload_server_1  | [Instance :3001] Uploaded uploads/abc123.jpg (98560 bytes)
upload_server_2  | [Instance :3002] Uploaded uploads/def456.jpg (75432 bytes)
upload_server_1  | [Instance :3001] Uploaded uploads/ghi789.jpg (110234 bytes)
upload_server_2  | [Instance :3002] Uploaded uploads/jkl012.jpg (89100 bytes)
```

---

## NGINX Configuration Explained

```nginx
upstream backend {
    # Default strategy is round-robin — no keyword needed
    server app1:3001;
    server app2:3002;
}

server {
    listen 80;
    client_max_body_size 2M;          # matches the backend 2 MB limit

    location / {
        proxy_pass http://backend;    # hands request to the upstream pool
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

NGINX resolves `app1` and `app2` using Docker's internal DNS (service names in `docker-compose.yml`).

---

## GitHub Actions CI Pipeline Explained

File: `.github/workflows/ci.yml`

**Triggers:** Every `push` and `pull_request` on any branch.

| Step | Command | Purpose |
|------|---------|---------|
| 1 | `actions/checkout@v4` | Clones repository |
| 2 | `actions/setup-node@v4` | Installs Node 20, restores npm cache |
| 3 | `npm ci` | Clean dependency install |
| 4 | `npm run lint` | ESLint — fails on errors |
| 5 | `npm test` | Jest tests with mocked S3 — no AWS creds needed |
| 6 | `docker build` | Validates the Dockerfile compiles successfully |

The workflow **fails automatically** if any step exits with a non-zero code, preventing broken code from being merged.

---

## Running Tests Locally

No AWS credentials required — S3 is fully mocked.

```bash
npm test
```

Expected output:
```
PASS  tests/upload.test.js
  POST /upload
    ✓ should reject a plain-text file with HTTP 400
    ✓ should reject a file larger than 2 MB with HTTP 400
    ✓ should upload a valid JPEG and return a URL with HTTP 200
    ✓ should upload a valid PNG and return a URL with HTTP 200
    ✓ should return 400 when no file is attached
    ✓ GET /health should return status ok

Test Suites: 1 passed, 1 total
Tests:       6 passed, 6 total
```

---

## Bonus Features

| Feature | Implementation |
|---------|---------------|
| **Image resizing** | `sharp` resizes images to max 1920 px wide before uploading |
| **Signed S3 URLs** | Response includes `signed_url` valid for 1 hour |
| **Dockerised** | Full `Dockerfile` + `docker-compose.yml` |

---

## Stopping All Services

```bash
docker compose down
```
