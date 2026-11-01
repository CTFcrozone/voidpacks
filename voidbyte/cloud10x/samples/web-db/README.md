# web-db reference project

A hardened Rust web service with PostgreSQL, deployed to k3d with kdd. Three workloads: `db` (StatefulSet), `db-mgmt` (one-shot Job that creates `app_user` and `app_db`), `web-server` (axum + sqlx, 2 replicas). `scaffold-web-db.md` reproduces it with your parameters. Copy `check.sh` and `lint.py` from `../web-app/` into a project built from it.

Names here are examples (`rust10x`, `rust10x-web-app`, `cloudapp`, `api.rust10x.local`, port `5000`, realm `dev_k3d`, `1-alpine`, `postgres:18-alpine`). A real project replaces them everywhere, consistently, and changes nothing else (`guide/base/scaffolding.md`).

Verified in testing: compiles (clippy and fmt clean); `db-mgmt` against a real PostgreSQL (idempotent, password with quotes, no secret in trace logs, non-zero exit on failure); `web-server` `/ready` 200 with the database and 503 without it, `/health` 200, graceful SIGTERM; rendered manifests pass `lint.py` (21 objects, 0 findings) and `check.sh`; a renamed copy passes too. Not verified here: the Docker builds and a live cluster deploy.

Flow: `cargo generate-lockfile && ./k3d.sh up && ./check.sh && ./k3d.sh build && ./k3d.sh deploy`, then `curl http://api.rust10x.local/ready`.

Secrets in `02-secrets.yaml` are `REPLACE_ME` placeholders for the local realm. The passwords must agree: `POSTGRES_PASSWORD` with the password in `SERVICE_PG_ROOT_URL`, and `SERVICE_DB_APP_PASSWORD` with the one in `SERVICE_DB_URL`. Use a secret manager outside local realms (`environments.md`).
