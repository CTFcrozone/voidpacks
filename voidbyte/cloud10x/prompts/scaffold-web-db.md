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
REGISTRY_PORT = 5000                # registry host k3d-<CLUSTER>-reg.localhost
REALM         = dev_k3d
INGRESS_HOST  = api.rust10x.local
RUST          = latest              # latest | <exact version> | from rust-toolchain.toml
BASE_OS       = alpine              # alpine | debian
PG_MAJOR      = latest-stable       # or an explicit number; always pinned in manifests
```

Resolve every value not listed here per `parameters.md`. Samples in the knowledge are examples: never copy their names or versions.

# TASK

Create a new Rust workspace AND its deployment using the cloud10x knowledge. The directory has no code yet. Write the files directly. Scope is exactly three workloads and nothing else:

1. `db` - PostgreSQL (`PG_MAJOR`, `BASE_OS` variant), StatefulSet with `volumeClaimTemplates`
2. `db-mgmt` - one-shot Job that creates the app database and `app_user` using the admin secret
3. `web-server` - a new minimal crate `crates/services/web-server`

Do NOT add: Valkey, queues, workers, extra services, Helm, Kustomize, service mesh, cert-manager, monitoring.

## Base (follow, do not reinvent)

- `web-server`, `kdd.yaml`, `k3d.sh`, Dockerfile pattern, namespace, ingress, hardening and NetworkPolicy style: reproduce `samples/minimal/` and apply the PARAMETERS the same way (value mapping in `prompts/scaffold-minimal.md`; reference values `rust10x`, `rust10x-web-app`, `cloudapp`, `api.rust10x.local`, `5000`, `dev_k3d`).
- Database parts (`01-config`, `02-secrets`, `03-postgres`, `04-db-mgmt-job`, network policies for the DB): follow `samples/web-app/k8s/dev_k3s/` and `database.md`, adapted to the three workloads below. Drop everything about Valkey, queues and the `queue` block.
- Every Dockerfile is the reference Dockerfile with only the crate name changed (`web-server` -> `db-mgmt`); no other layout applies.
- Add to the reference only what the three workloads need; keep every convention of the reference unchanged.

## Rust code

- Root `Cargo.toml` workspace with members `crates/services/web-server`, `crates/services/db-mgmt`; `resolver = "3"`; edition = the latest stable edition. Do not set `rust-version` unless `RUST` is pinned (then use it). Dependencies are crates.io crates only: never `std`, `core`, `alloc` or module paths such as `std::env`. User runs `cargo generate-lockfile` (state it); images build with `--locked`.
- No OpenSSL. rustls only: `sqlx` with `default-features = false, features = ["runtime-tokio", "tls-rustls", "postgres", "macros"]`. No `native-tls`, `openssl`, sqlite or mysql features.
- `web-server` (axum, tokio, sqlx, tracing): listens `0.0.0.0:8081`; `GET /health` (200, no DB), `GET /ready` (`SELECT 1`, 503 on failure), `GET /` (plain text name + version). Env: `SERVICE_DB_URL`, `PORT` (default 8081), `RUST_LOG`. Graceful shutdown on SIGTERM. No static folder.
- `db-mgmt` (tokio, sqlx): env `SERVICE_PG_ROOT_URL` (admin), `SERVICE_DB_APP_PASSWORD`. Idempotently creates role `app_user` (LOGIN, password from env) and database `app_db` owned by it. `CREATE DATABASE` outside a transaction. Never logs secrets. Non-zero exit on failure.
- Env names are the contract: identical in config, secrets, Job and Deployment. `SERVICE_DB_URL` targets `app_db` as `app_user` through the `<SYSTEM>-db` Service.
- Each crate under ~100 lines, no unused dependencies.

## Files

- `kdd.yaml`: `system: SYSTEM`; vars `from_file` the web-server `Cargo.toml` version; realm `REALM` only (`confirm_delete: false`, `context: k3d-CLUSTER`, `registry: k3d-CLUSTER-reg.localhost:REGISTRY_PORT`); blocks `db`, `db-mgmt`, `web-server`.
- `k8s/dev_k3s/` numbered, one concern per file: `00-namespace`, `01-config`, `02-secrets`, `03-postgres`, `04-db-mgmt-job`, `05-web-server`, `06-ingress`, `07-network-policy`.
- `crates/services/web-server/Dockerfile`, `crates/services/db-mgmt/Dockerfile`, `.dockerignore`, `.gitignore` (`k8s/*/.out/`, `kdd.local.yaml`, `target/`).
- `k3d.sh` (`up`, `build`, `deploy`, `all`) with constants from PARAMETERS: `CLUSTER`, `REG_NAME=CLUSTER-reg.localhost` (k3d adds the `k3d-` prefix), `REG_PORT`, `REALM`, `NS`. `SYSTEM` is read from `kdd.yaml`. Build outside kdd with the workspace root as context, tag `localhost:5000/SYSTEM-<block>:<version>`, then `kdd dpush`. Deploy in stages gated by `kubectl rollout status` / `wait`. kdd exits 0 even on failure.
- `check.sh` and `lint.py`: copy `samples/web-app/check.sh` and `samples/web-app/lint.py` unchanged; `check.sh` executable.

## Images

- Postgres: `postgres:<PG_MAJOR>` with the `BASE_OS` variant, pinned to that major. Volume mounted at `/var/lib/postgresql`, `PGDATA=/var/lib/postgresql/data`.
- Builder: `ARG RUST_TAG` then `FROM rust:${RUST_TAG}`. `RUST=latest` -> default `1-<variant>` (floats to latest stable); pinned -> `<version>-<variant>`. Variant follows `BASE_OS` (`alpine` or `slim`). On alpine: `apk add --no-cache musl-dev`.
- Runtime: `alpine:3` or Debian stable slim per `BASE_OS`; `ca-certificates` only; numeric non-root `USER 10001:10001`; exec-form `ENTRYPOINT`.
- `cargo build --locked --release -p <crate>` with BuildKit cache mounts.
- Manifest image refs: `"{{registry}}/{{system}}-<block>:{{image_tag}}"`. Never `latest`, never literal registry or version.

## Hardening (every pod)

- Namespace Pod Security labels: `enforce: baseline`, `warn: restricted`, `audit: restricted`.
- Pod: `runAsNonRoot`, explicit `runAsUser`/`runAsGroup`, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`, dedicated ServiceAccount per workload.
- Container: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`; writable paths only via `emptyDir` (`/tmp`; postgres also `/var/run/postgresql`).
- Postgres runs as the image's postgres uid/gid (70 on alpine, 999 on debian) with matching `fsGroup`. Data only on the PVC.
- Requests and limits, readiness and liveness probes on every container.
- Secrets: `postgres-secret` (superuser), `db-admin-secret` (db-mgmt only), `db-secret` (app user, web-server). Values `REPLACE_ME`. No real secrets or TLS keys in the repo.
- Web-server: 2 replicas, PodDisruptionBudget `minAvailable: 1`, spread constraints or anti-affinity.
- NetworkPolicy: default-deny ingress and egress, then allows with BOTH sides, on POD ports: ingress controller -> web-server; web-server -> db 5432 + DNS; db ingress from web-server and db-mgmt only; db-mgmt -> db 5432 + DNS.
- db-mgmt Job: small `backoffLimit`, `ttlSecondsAfterFinished`, `restartPolicy: OnFailure`; recreated each deploy.

## Consistency (see contract.md)

- The web-server `Cargo.toml` has a literal `version = "X.Y.Z"`, never `version.workspace = true` (kdd would render `{ workspace = true }`).
- `system` defined once in `kdd.yaml`. Block names are `db`, `db-mgmt`, `web-server` everywhere: blocks, manifests, labels, image names, crate dirs.
- Pod label `run: "{{system}}-<block>"`.
- Every env var the code reads is set explicitly in the manifests (ConfigMap or `env:`), even when the code has a default. `check.sh` enforces this.
- In `k3d.sh`: `REG_NAME` is exactly `<CLUSTER>-reg.localhost` (never the system name). `kdd.yaml` realm: `context: k3d-<CLUSTER>`, `registry: k3d-<REG_NAME>:<REG_PORT>`.
- Do not write manifests that fail `check.sh` (it runs `lint.py`; rules in `lint.md`).

## Self-check (do this before answering; fix any failure silently)

1. `k3d.sh`: `REG_NAME` is exactly `<CLUSTER>-reg.localhost`; `kdd.yaml` realm has `context: k3d-<CLUSTER>` and `registry: k3d-<REG_NAME>:<REG_PORT>`.
2. `crates/services/web-server/Cargo.toml`: `version = "X.Y.Z"` literal on its own line, no trailing comment, never `version.workspace = true`.
3. Every env var the code reads is set in the manifests; list each var and the manifest line that sets it.
4. No `std`, `core` or module paths (`std::env`) in any `Cargo.toml`.
5. `k3d.sh` contains no `|| true`.
6. Every Dockerfile: `ARG RUST_TAG` before `FROM rust:${RUST_TAG}`, `cargo build --locked`, numeric `USER`, exec-form `ENTRYPOINT`.
7. Every workload: dedicated ServiceAccount (defined in `00-namespace`), `automountServiceAccountToken: false`, probes, requests and limits, label `run`.
8. The Namespace has the three Pod Security labels and a default-deny NetworkPolicy exists.
9. No value from the reference project survives where a parameter differs (search for its example names).

## Output

- Before finishing, list each env var the code reads and the exact manifest line that sets it. Fix any gap before answering.
- List every file created and every assumption (ports, env names, health path, which default each unresolved parameter used).
- Env var names must match the Rust code you wrote.
- If something required is missing, state it instead of guessing.
- End with exactly: `cargo generate-lockfile && ./k3d.sh up && ./check.sh && ./k3d.sh build`

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
