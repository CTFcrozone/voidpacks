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
BLOCK         = <new-service>       # kebab-case; used for the block, manifest, image, crate dir and pod label
PORT          = <pod port>
NEEDS_DB      = yes | no
EXPOSED       = yes | no            # ingress route needed
INGRESS_PATH  = <path>              # if EXPOSED
```

Resolve every value not listed here from the existing project, then `parameters.md`. Never copy names from samples.

# TASK

Add one service `BLOCK` to the existing project. Read `kdd.yaml`, `k3d.sh`, the existing manifests and the existing crate first; match their conventions exactly (system, namespace, realm, numbering, label style). Change only what the new service requires.

## Rust code

- New crate `crates/services/BLOCK` (workspace member), modeled on the existing web-server crate: routes `GET /health`, optional `GET /ready` (only if `NEEDS_DB`).
- Dependencies are crates.io crates only. Reuse the workspace's existing dependency versions and TLS policy (rustls).
- Env var names: copy the style of existing services; list every one.

## Files

- `kdd.yaml`: add block `BLOCK`. Do not change realms.
- `crates/services/BLOCK/Dockerfile`: same pattern as the existing service Dockerfiles (`ARG RUST_TAG`).
- `k8s/<yaml_dir>/`: a new numbered manifest for `BLOCK` using the next free number after the existing files, placed so it applies after its dependencies. Do not renumber existing files. Service, Deployment, ServiceAccount, PodDisruptionBudget if replicas > 1.
- `k3d.sh`: add `BLOCK` to the build list and to the deploy stages, gated by `kubectl rollout status`.
- Existing `07-network-policy`-style file: add allow rules with BOTH sides on pod ports: ingress to `BLOCK` from its callers, egress from `BLOCK` to its dependencies and DNS. If `EXPOSED`, allow the ingress controller and extend the Ingress.
- Existing secrets/config: add new env vars explicitly (every env var the code reads is set in the manifests).

## Consistency (see contract.md, lint.md)

- Pod label `run: "{{system}}-BLOCK"`. Image `"{{registry}}/{{system}}-BLOCK:{{image_tag}}"`.
- All hardening rules apply (non-root, read-only root, drop ALL, probes, resources, dedicated ServiceAccount).
- Do not write manifests that fail `check.sh`.

## Output

- Before finishing, list each env var the code reads and the exact manifest line that sets it. Fix any gap before answering.
- List every file created and every file modified, with a one-line reason each.
- List assumptions. If something required is missing, state it instead of guessing.
- End with exactly: `cargo check --workspace --locked && ./check.sh && ./k3d.sh build && ./k3d.sh deploy`

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
