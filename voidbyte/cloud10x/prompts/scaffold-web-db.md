```yaml
#!meta (parametric prompt)

# See .aipack/.prompt/pro@coder/README.md for additional documentation
# Note: All relative paths are relative to the workspace directory (parent folder of .aipack/)

## Static knowledge (relative & absolute)
knowledge_globs:
  - voidbyte@cloud10x/guide/**/*.md
  - voidbyte@cloud10x/samples/**/*.*

## Files the AI will work on (paths & content included in prompt, relative only)
context_globs:
  - "*"
  - "crates/**/*.*"
  - "k8s/**/*.*"

## Set to false to disable file writing (response below this file's prompt)
write_mode: true

auto_context:
  enabled: false

## Full model names or aliases (see ~/.aipack-base/config-default.toml)
model: flash
```

# PARAMETERS (edit these; everything below refers to them)

```
SYSTEM        = rust10x
NAMESPACE     = rust10x-web-app
CLUSTER       = cloudapp            # k3d cluster -> context k3d-<CLUSTER>
REG_PORT      = 5000                # registry host k3d-<CLUSTER>-reg.localhost
REALM         = dev_k3d
INGRESS_HOST  = api.rust10x.local
RUST          = latest              # latest | <exact version>
BASE_OS       = alpine
PG_MAJOR      = <number>            # PostgreSQL major, pinned in the manifests
```

# TASK

Scaffold a web service with PostgreSQL and a db-mgmt Job, following `scaffolding.md`: `web-server` from `samples/minimal/`, the database parts from `samples/web-app/k8s/dev_k3s/` and `database.md`. Scope is exactly three workloads:

1. `db` - PostgreSQL `PG_MAJOR` (alpine variant), StatefulSet with `volumeClaimTemplates`, volume at `/var/lib/postgresql`.
2. `db-mgmt` - one-shot Job that creates the app database and `app_user` using the admin secret.
3. `web-server` - the reference service extended with a database pool.

Do NOT add: Valkey, queues, workers, extra services, Helm, Kustomize, service mesh, cert-manager, monitoring.

## Application facts

- `web-server` (axum, tokio, sqlx, tracing): `GET /health` (200, no DB), `GET /ready` (`SELECT 1`, 503 on failure), `GET /` (name + version). Fixed port 8081. Env: `SERVICE_DB_URL`, `RUST_LOG`.
- `db-mgmt` (tokio, sqlx): env `SERVICE_PG_ROOT_URL` (admin), `SERVICE_DB_APP_PASSWORD`. Idempotently creates role `app_user` (LOGIN, password from env) and database `app_db` owned by it; `CREATE DATABASE` outside a transaction. Never logs secrets. Non-zero exit on failure.
- `sqlx` with `default-features = false, features = ["runtime-tokio", "tls-rustls", "postgres", "macros"]`; no OpenSSL. Workspace members: `web-server`, `db-mgmt`.
- `SERVICE_DB_URL` targets `app_db` as `app_user` through the `<SYSTEM>-db` Service.
- Manifests under `k8s/dev_k3s/`: `00-namespace`, `01-config`, `02-secrets`, `03-postgres`, `04-db-mgmt-job`, `05-web-server`, `06-ingress`, `07-network-policy`. Blocks in `kdd.yaml`: `db`, `db-mgmt`, `web-server`. `k3d.sh` builds both images and deploys in stages (secrets and Postgres, then the db-mgmt Job recreated each deploy, then the web-server).
- Secrets: `postgres-secret` (superuser), `db-admin-secret` (db-mgmt only), `db-secret` (app user, web-server). Values `REPLACE_ME`.
- Postgres runs as the image's postgres uid/gid (70 on alpine) with matching `fsGroup`; writable paths via `emptyDir` (`/tmp`, `/var/run/postgresql`).
- NetworkPolicy (default-deny, then both-sided allows on pod ports): ingress controller to web-server; web-server to db 5432 and DNS; db ingress from web-server and db-mgmt only; db-mgmt to db 5432 and DNS.
- Web-server: 2 replicas, PodDisruptionBudget `minAvailable: 1`.

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
