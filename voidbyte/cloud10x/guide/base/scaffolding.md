# Scaffolding

Applies to every scaffold prompt. A prompt carries only the parameters, the scope and the facts specific to the application. The method, the rules and the checks live here.

## Method

1. Start from a reference project: `samples/minimal/` (one service) or `samples/web-db/` (service, PostgreSQL, db-mgmt Job).
2. Reproduce it with the parameters applied. Do not design, improve, reformat or reorder.
3. Precedence when sources disagree: user parameters, then the reference projects, then guide text, then guide snippets (`parameters.md`).
4. Run the self-check below before answering.

## Parameters

| Name | Meaning | Reference value |
|---|---|---|
| `SYSTEM` | kdd system name, resource prefix | `rust10x` |
| `NAMESPACE` | Kubernetes namespace | `rust10x-web-app` |
| `CLUSTER` | k3d cluster; context is `k3d-<CLUSTER>` | `cloudapp` |
| `REG_PORT` | k3d registry port; host is `k3d-<CLUSTER>-reg.localhost` | `5000` |
| `REALM` | kdd realm | `dev_k3d` |
| `INGRESS_HOST` | ingress hostname | `api.rust10x.local` |
| `RUST` | `latest` or an exact version | `latest` |
| `BASE_OS` | runtime base; the reference supports `alpine` only | `alpine` |
| `PG_MAJOR` | PostgreSQL major, always pinned (`samples/web-db/` only) | `18` |

## Value mapping (`samples/minimal/` and `samples/web-db/`)

Replace every occurrence of the reference value with the parameter value, in every file, and change nothing else. Apply the rows in this order.

| Reference value | Parameter |
|---|---|
| `rust10x-web-app` | `NAMESPACE` |
| `api.rust10x.local` | `INGRESS_HOST` |
| `rust10x` (system name, everywhere else) | `SYSTEM` |
| `cloudapp` | `CLUSTER` |
| `5000` in `REG_PORT` and `registry:` | `REG_PORT` |
| `dev_k3d` | `REALM` |
| `1-alpine` (`ARG RUST_TAG`) | `1-alpine` for `RUST=latest`, otherwise `<RUST>-alpine` |
| `postgres:18-alpine` (`samples/web-db/` only) | `postgres:<PG_MAJOR>-alpine` |

The fixed `localhost:5000` in the `docker build` tag stays: it is kdd's local prefix, not the registry port.

## Dotfiles

Globs may hide dotfiles, so their content is given here. Create them exactly.

`.gitignore`:

```
# kdd rendered manifests
k8s/*/.out/

# machine-specific kdd realms (overlay)
kdd.local.yaml

target/
.aipack/
```

`.dockerignore`:

```
target/
.git/
.aipack/
k8s/
*.md
```

## Rules

- Files: exactly those in the reference project, plus `check.sh` and `lint.py` copied byte for byte from `samples/web-app/`.
- Every Dockerfile is the reference Dockerfile verbatim, comments included; only the crate name changes for another binary. No other layout applies.
- Same paths, code, comments, ports, labels, security settings and structure. `version = "0.1.0"` stays a literal on its own line.
- Database scaffolds are `samples/web-db/`: same files, same names, nothing added (no Valkey, queues, workers).
- If a parameter value is unsupported (`BASE_OS` other than `alpine`, `RUST` neither `latest` nor a version), write nothing and say so.

## Self-check

Do this before answering and fix any failure silently.

1. `k3d.sh`: `REG_NAME` is exactly `<CLUSTER>-reg.localhost`; the `kdd.yaml` realm has `context: k3d-<CLUSTER>` and `registry: k3d-<REG_NAME>:<REG_PORT>`.
2. `crates/services/web-server/Cargo.toml`: `version = "X.Y.Z"` literal on its own line, no trailing comment, never `version.workspace = true`.
3. Every env var the code reads is set in the manifests; list each var and the manifest line that sets it.
4. No `std`, `core` or module paths (`std::env`) in any `Cargo.toml`.
5. `k3d.sh` contains no `|| true`.
6. Every Dockerfile: `ARG RUST_TAG` before `FROM rust:${RUST_TAG}`, `cargo build --locked`, numeric `USER`, exec-form `ENTRYPOINT`.
7. Every workload: dedicated ServiceAccount (defined in `00-namespace`), `automountServiceAccountToken: false`, probes, requests and limits, label `run`.
8. The Namespace has the three Pod Security labels and a default-deny NetworkPolicy exists.
9. No value from the reference project survives where a parameter differs (search for its example names).

## Answer format

- A table of the parameter values applied (and the default used for any unset one).
- The files written, and one line per self-check item.
- Any assumption or missing fact, stated instead of guessed.
- End with exactly: `cargo generate-lockfile && ./k3d.sh up && ./check.sh && ./k3d.sh build && ./k3d.sh deploy`
