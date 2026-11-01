# Adding a service

Rules for adding one service (a block) to an existing project. They apply to humans and agents alike. Match the project's own conventions first: read `kdd.yaml`, `k3d.sh`, the existing manifests and the existing service crate, and change only what the new service requires.

## Parameters

| Name | Meaning |
|---|---|
| `BLOCK` | kebab-case name; used for the block, manifest, image, crate directory and pod label |
| `PORT` | pod port |
| `NEEDS_DB` | whether the service connects to the database |
| `EXPOSED` | whether an ingress route is needed |
| `INGRESS_PATH` | route prefix, when exposed |

Resolve every other value from the project, then `parameters.md`. Never copy names from the samples.

## Rust code

- New crate `crates/services/BLOCK`, a workspace member, modeled on the existing web-server crate. Dependencies are crates.io crates only; reuse the workspace's dependency versions and TLS policy (rustls).
- Routes: `GET /health`; `GET /ready` only when `NEEDS_DB`; nothing else the task does not ask for. `/health` and `/ready` stay at the root, they are for the probes.
- **An exposed service serves its own routes under `INGRESS_PATH`** (for `/echo`, its handlers are mounted at `/echo`). The ingress does not strip the prefix and no rewrite or middleware is added: that would tie the manifests to one ingress controller.
- Env var names follow the existing services' style; every one is listed in the answer.
- The crate builds clippy-clean: no unused imports, no dead code, no warnings.

## Files

- `kdd.yaml`: add the block `BLOCK`. Do not change realms.
- `crates/services/BLOCK/Dockerfile`: the same pattern as the existing service Dockerfiles (`ARG RUST_TAG`, `--locked`, numeric non-root user, exec-form entrypoint).
- `k8s/<yaml_dir>/`: a new numbered manifest for `BLOCK` with the next free number, placed so it applies after its dependencies. Existing files are not renumbered. It holds the ServiceAccount, Service, Deployment and, when replicas > 1, the PodDisruptionBudget.
- `k3d.sh`: add `BLOCK` to the build list, to `kdd dpush`, and to the deploy stages, gated by `kubectl rollout status`.
- **Existing files are edited only where unavoidable:** `kdd.yaml` (the block), `k3d.sh`, the workspace `Cargo.toml` (the member) and the Ingress (the path). Every other line of an edited file stays as it was, and every `---` separator of a multi-document file stays. `lint.py` fails on a merged document, but do not rely on it.
- **Network policies go in `BLOCK`'s own manifest; no existing policy is edited.** Policies are additive, so every connection is opened by new policies with both halves on pod ports: when `EXPOSED`, ingress from the ingress controller to `BLOCK`'s pod port; egress from `BLOCK` to each dependency's pod port; and for each dependency (the database, another service) one more policy named `<dependency>-allow-ingress-from-BLOCK` that allows ingress to the dependency's pods from `BLOCK`. DNS egress is already allowed for the whole namespace.
- The Ingress: add one path for `INGRESS_PATH`, placed before the catch-all `/`, when `EXPOSED`.
- Existing secrets and config: add the new env vars explicitly (every env var the code reads is set in the manifests).

## Consistency

- Pod label `run: "{{system}}-BLOCK"`; image `"{{registry}}/{{system}}-BLOCK:{{image_tag}}"`.
- All hardening rules apply (`kubernetes.md`, `lint.md`): non-root, read-only root, drop ALL, probes, resources, dedicated ServiceAccount.
- `check.sh` passes.
- Other realms: a realm directory with `confirm_delete: true` is not edited by this task. The answer says that those realms do not yet have the service.

## Answer format

- Each env var the code reads and the exact manifest line that sets it; fix any gap before answering.
- Every file created and every file modified, with a one-line reason each.
- Assumptions. If something required is missing, state it instead of guessing.
