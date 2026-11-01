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
```

Resolve every value not listed here per `parameters.md`. Samples in the knowledge are examples: never copy their names or versions.

# TASK

Create the smallest working KDD project: one Rust web service deployed to k3d. The directory has no code yet. Write the files directly. Scope is exactly one workload and nothing else:

1. `web-server` - a minimal axum crate `crates/services/web-server`

Do NOT add: database, db-mgmt, Postgres, Valkey, queues, extra services, Helm, Kustomize, ingress TLS, monitoring.

## Rust code

- Root `Cargo.toml` workspace with the single member; `resolver = "3"`; latest stable edition. No `rust-version` unless `RUST` is pinned. Dependencies are crates.io crates only, never `std` paths.
- `web-server` (axum, tokio, tracing): listens `0.0.0.0:8081`; `GET /health` (200), `GET /` (plain text name + version). Env: `PORT` (default 8081), `RUST_LOG`. Graceful shutdown on SIGTERM.
- Under ~60 lines, no unused dependencies.

## Files

- `kdd.yaml`: `system: SYSTEM`; vars `from_file` the web-server `Cargo.toml` version; realm `REALM` only (`confirm_delete: false`, `context: k3d-CLUSTER`, `registry: k3d-CLUSTER-reg.localhost:REGISTRY_PORT`); block `web-server`.
- `k8s/dev_k3s/`: `00-namespace` (Namespace + ServiceAccount), `01-web-server` (Service, Deployment, PodDisruptionBudget if replicas > 1), `02-ingress`, `03-network-policy` (default-deny ingress+egress, then allow the ingress controller -> web-server on the pod port).
- `crates/services/web-server/Dockerfile`, `.dockerignore`, `.gitignore` (`k8s/*/.out/`, `kdd.local.yaml`, `target/`).
- `k3d.sh` (`up`, `build`, `deploy`, `all`) with constants from PARAMETERS. `SYSTEM` is read from `kdd.yaml`. Build outside kdd with the workspace root as context, tag `localhost:5000/SYSTEM-web-server:<version>`, then `kdd dpush`. Deploy with `kdd kapply` and gate on `kubectl rollout status`.
- `check.sh` and `lint.py`: copy `samples/web-app/check.sh` and `samples/web-app/lint.py` unchanged; `check.sh` executable.

## Images

- Builder: `ARG RUST_TAG` then `FROM rust:${RUST_TAG}`; `latest` -> `1-<variant>`; variant follows `BASE_OS`. On alpine: `apk add --no-cache musl-dev`.
- Runtime: `alpine:3` or Debian stable slim per `BASE_OS`; numeric non-root `USER 10001:10001`; exec-form `ENTRYPOINT`.
- Manifest image ref: `"{{registry}}/{{system}}-web-server:{{image_tag}}"`. Never `latest`, never literal registry or version.

## Hardening

- Namespace Pod Security labels: `enforce: baseline`, `warn: restricted`, `audit: restricted`.
- Pod: `runAsNonRoot`, explicit user/group, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`, dedicated ServiceAccount (never `default`).
- Container: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`, `emptyDir` on `/tmp`, requests and limits, readiness and liveness probes.

## Consistency (see contract.md)

- The web-server `Cargo.toml` has a literal `version = "X.Y.Z"`, never `version.workspace = true`.
- Pod label `run: "{{system}}-web-server"`. Block, manifest, image and crate dir are all `web-server`.
- Every env var the code reads is set explicitly in the manifests (ConfigMap or `env:`), even when the code has a default. `check.sh` enforces this.
- In `k3d.sh`: `REG_NAME` is exactly `<CLUSTER>-reg.localhost` (never the system name). `kdd.yaml` realm: `context: k3d-<CLUSTER>`, `registry: k3d-<REG_NAME>:<REG_PORT>`.
- Do not write manifests that fail `check.sh` (it runs `lint.py`; rules in `lint.md`).

## Output

- List every file created and every assumption.
- End with exactly: `cargo generate-lockfile && ./k3d.sh up && ./check.sh && ./k3d.sh build && ./k3d.sh deploy`

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
