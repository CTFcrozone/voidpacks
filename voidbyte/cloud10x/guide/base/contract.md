# Consistency contract

Every name and version is defined once and only referenced elsewhere. A scaffold that breaks any rule here is wrong, even if it compiles.

## Single sources of truth

| Value | Defined in | Referenced by |
|---|---|---|
| system name | `system:` in `kdd.yaml` | `{{system}}` in manifests, `SYSTEM` in scripts (read from `kdd.yaml`) |
| image tag | `version = "X.Y.Z"` literal in `crates/services/web-server/Cargo.toml` | `kdd.yaml` var `version` -> `image_tag`; build script reads the same file |
| registry | `registry:` of the realm in `kdd.yaml` | `{{registry}}` in manifests |
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
- Generate `check.sh` (see `samples/web-app/check.sh`) and run it after `./k3d.sh up` and before any build (kdd needs the cluster context).
- `Cargo.toml` dependencies are crates.io crates (or path/workspace members). `std`, `core`, `alloc` and module paths such as `std::env` are never dependencies.
- Names and versions in the pack's examples are placeholders; take real values per `parameters.md`.
