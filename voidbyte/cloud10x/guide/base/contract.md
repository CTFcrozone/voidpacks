# Consistency contract

Every name and version is defined once and only referenced elsewhere. A scaffold that breaks any rule here is wrong, even if it compiles.

## Single sources of truth

| Value | Defined in | Referenced by |
|---|---|---|
| system name | `system:` in `kdd.yaml` | `{{system}}` in manifests, `SYSTEM` in scripts (read from `kdd.yaml`) |
| image tag | `version = "X.Y.Z"` literal in `crates/services/web-server/Cargo.toml` | `kdd.yaml` var `version` -> `image_tag`; build script reads the same file |
| registry | `registry:` of the realm in `kdd.yaml` | `{{registry}}` in manifests |
| cluster, registry host, port | `CLUSTER`, `REG_NAME`, `REG_PORT` in the cluster script | realm `context: k3d-<CLUSTER>` and `registry: k3d-<REG_NAME>:<REG_PORT>` in `kdd.yaml`; `REG_NAME` is always `<CLUSTER>-reg.localhost` |
| namespace | `01`/`00-namespace` manifest | scripts and `-n` flags |
| env var names | the Rust config code | ConfigMap, Secrets, Job, Deployment: identical spelling |
| ports | one table in the web-server manifest header | Service targetPort, containerPort, probes, NetworkPolicy |

## Rules

- kdd `from_file` extract reads literal values only. `version.workspace = true` renders as `{ workspace = true }` and breaks image tags. The crate that supplies `version` must contain a literal `version = "X.Y.Z"`.
- One version for the whole system: all images use `{{image_tag}}`. Never hard-code a tag, never `latest`.
- The build script must fail when `VERSION` is empty or not `X.Y.Z`.
- Image refs are `"{{registry}}/{{system}}-<block>:{{image_tag}}"`. The build tags `localhost:5000/<system>-<block>:<version>`; `kdd dpush <block>` retags to the realm registry.
- Block name = manifest suffix = pod label suffix = image suffix = Dockerfile crate name. Example: `web-server`.
- Pod label `run: "{{system}}-<block>"` on every Deployment/StatefulSet/Job pod.
- Env var names are copied from the code, never invented in manifests.
- Every env var the code reads is set explicitly in the manifests (ConfigMap or `env:`), even when the code has a default. `check.sh` enforces this.
- Copy `check.sh` and `lint.py` (see `samples/web-app/`) into the project root unchanged. `lint.py` enforces the hardening rules (`lint.md`).
- Run `check.sh` after `./k3d.sh up` and before any build (kdd needs the cluster context).
- `Cargo.toml` dependencies are crates.io crates (or path/workspace members). `std`, `core`, `alloc` and module paths such as `std::env` are never dependencies.
- Names and versions in the pack's examples are placeholders; take real values per `parameters.md`.

## Known failure modes

Each of these happened in a real scaffold. All are checked by `check.sh` / `lint.py`.

| Symptom | Cause | Rule |
|---|---|---|
| `invalid reference format` on build | empty version: `version.workspace = true`, or a comment after `version = "..."` | literal version on its own line |
| `ImagePullBackOff` / push to the wrong registry | `REG_NAME` is the system name, not the cluster | `REG_NAME=<CLUSTER>-reg.localhost`; `kdd.yaml` registry derived from it |
| `cargo` manifest error `invalid unquoted key` | `std::env` listed as a dependency | std/core/alloc are never dependencies |
| env var unset at runtime | code reads a variable the manifest never sets | every `env::var` is set explicitly in the manifests |
| `rustc X is not supported by the following packages` | stale pinned Rust tag | floating `rust:${RUST_TAG}` (`parameters.md`) |
| cluster half-created, script continues | `\|\| true` on create commands | create only if absent; never mask failures |
| kdd prompt hangs `check.sh` | realm context does not exist yet | create the cluster first, then `check.sh` |
| realm "not found" though it is in an overlay | overlay path wrong or file missing; kdd skips it silently | `check.sh` fails on a missing overlay (except `kdd.local.yaml`) |
