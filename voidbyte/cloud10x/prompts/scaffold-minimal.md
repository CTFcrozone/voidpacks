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
RUST          = latest              # latest | <exact version, e.g. 1.94.0>
BASE_OS       = alpine              # the reference supports alpine only
```

# TASK

Reproduce the reference project `samples/minimal/` file for file, applying the parameters. Do NOT design, improve, reformat or reorder anything.

## Value mapping

Replace every occurrence of the reference value with the parameter value, in every file, and change nothing else:

| Reference value | Parameter |
|---|---|
| `rust10x-web-app` | `NAMESPACE` |
| `api.rust10x.local` | `INGRESS_HOST` |
| `rust10x` (system name, everywhere else) | `SYSTEM` |
| `cloudapp` | `CLUSTER` |
| `5000` in `REG_PORT` and `registry:` | `REG_PORT` |
| `dev_k3d` | `REALM` |
| `1-alpine` (`ARG RUST_TAG`) | `1-alpine` for `RUST=latest`, otherwise `<RUST>-alpine` |

Apply `rust10x-web-app` before `rust10x`. The fixed `localhost:5000` in the `docker build` tag stays (kdd's local prefix).

## Dotfiles (create with exactly this content; globs may hide them from you)

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

- Files: exactly those in `samples/minimal/` (its two dotfiles are given above), plus `check.sh` and `lint.py` copied byte for byte from `samples/web-app/`.
- Same paths, same code, same comments, same ports (8081), labels, security settings and structure.
- `version = "0.1.0"` stays a literal on its own line.
- If `BASE_OS` is not `alpine`, or `RUST` is neither `latest` nor a version, write nothing and say so.

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

- A table of the values you applied.
- The list of files written, and the result of each self-check item (one line each).
- End with exactly: `cargo generate-lockfile && ./k3d.sh up && ./check.sh && ./k3d.sh build && ./k3d.sh deploy`

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
