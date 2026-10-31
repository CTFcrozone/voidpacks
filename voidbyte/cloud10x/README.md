# cloud10x

Knowledge pack for building and deploying cloud applications with **KDD** (Kubernetes-Driven Development), Kubernetes, PostgreSQL and Valkey. Written for AI coding agents and humans: rules first, minimal prose, full manifests in `samples/`.

## Install

```sh
aip install git://github.com/CTFcrozone/voidpacks.git#voidbyte/cloud10x
```

## Use with pro@coder

In `coder-prompt.md`:

```yaml
knowledge_globs:
  - voidbyte@cloud10x/guide/**/*.md
  - voidbyte@cloud10x/samples/**/*.*   # optional: full reference manifests
```

No dedicated agent is shipped: `pro@coder` with this knowledge authors and reviews `kdd.yaml`, Dockerfiles and manifests. Executing `kdd` / `kubectl` against clusters stays a human action.

## Writing prompts for this pack

The pack holds the rules. The prompt holds the facts of one project and the scope of one task. A good prompt is short, parametric and checkable.

**Structure**

1. **Header:** the pro@coder YAML block with `knowledge_globs` for this pack, `context_globs`, `write_mode: true`, a `model`.
2. **Parameters:** every name and version the project needs, in one block (system, namespace, cluster, registry, realm, toolchain, base OS, database major). Values you leave out are resolved by `guide/base/parameters.md`.
3. **Scope:** exactly what to build and a "do not add" list. Unbounded prompts produce extra services.
4. **Contract:** the names that must agree across files (env vars, block names, ports). Point at `contract.md` instead of repeating it.
5. **Output:** ask for a list of created files, a list of assumptions, and the exact commands to run next.

**Rules**

- **State facts once.** Refer to parameters by name; never repeat a value in several places.
- **Say `latest` or a pin explicitly.** Toolchains float by default; databases are always pinned.
- **Forbid, don't hope.** List what must not appear (extra services, `latest` tags, hard-coded registries, OpenSSL).
- **Make it verifiable.** Ship a script that fails on drift (`samples/web-app/check.sh`) and name it in the prompt.
- **The agent writes, you run.** Agents author files; applying to a cluster is a human step.
- **Commit before `write_mode`.** Run on a clean tree so every change is a diff.
- **Do not paste samples as requirements.** Samples are examples; real names come from the parameters.

**Skeleton**

````markdown
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
  - crates/**/*.*
  - k8s/**/*.*

## Set to false to disable file writing (response below this file's prompt)
write_mode: true

auto_context:
  enabled: false

## Full model names or aliases (see ~/.aipack-base/config-default.toml)
model: <alias>
```

# PARAMETERS (edit these; everything below refers to them)

```
SYSTEM        = <name>
NAMESPACE     = <namespace>
CLUSTER       = <name>              # k3d cluster -> context k3d-<CLUSTER>
REGISTRY_PORT = <port>              # registry host k3d-<CLUSTER>-reg.localhost
REALM         = <realm>
INGRESS_HOST  = <host>
RUST          = latest              # latest | <exact version> | from rust-toolchain.toml
BASE_OS       = alpine              # alpine | debian
PG_MAJOR      = latest-stable       # or an explicit number; always pinned in manifests
```

Resolve every value not listed here per `parameters.md`. Samples in the knowledge are examples: never copy their names or versions.

# TASK

<One paragraph: what to create. State whether the directory is empty. Scope is exactly these workloads and nothing else:>

1. `<block>` - <what it is>
2. `<block>` - <what it is>

Do NOT add: <extra services, tools, or features that must not appear>.

## Rust code

- <Workspace layout, edition, dependency rules (crates.io only, no `std` paths), TLS policy.>
- <Per crate: routes, ports, env var names, behavior.>
- Env names are the contract: identical in config, secrets, Jobs and Deployments.

## Files

- <Each file or directory to write, with the parameters it uses.>
- `check.sh`: copy `samples/web-app/check.sh` unchanged; executable.

## Images

- <Base image policy per parameters.md: toolchain floating or pinned, stateful engines pinned, runtime OS, non-root user.>
- Manifest image refs: `"{{registry}}/{{system}}-<block>:{{image_tag}}"`. Never `latest`, never literal registry or version.

## Hardening (every pod)

- <Pod and container security context, writable paths, probes, resources.>
- <Secrets layout, replicas, disruption budget.>
- <NetworkPolicy: default-deny, then both-sided allows on pod ports.>

## Consistency (see contract.md)

- <Version source: literal `version`, never `version.workspace = true`.>
- <Names defined once; block names identical in blocks, manifests, labels, images, crate dirs.>
- <Every env var the code reads is set explicitly in the manifests, even when the code has a default.>
- Do not write manifests that fail `check.sh`.

## Output

- List every file created and every assumption (ports, env names, which default each unresolved parameter used).
- If something required is missing, state it instead of guessing.
- End with exactly: `<commands to run next>` (cluster first, then `./check.sh`, then build: kdd needs the cluster context).

====
````

**Review checklist after a run**

- File list matches the scope and nothing extra exists.
- `./check.sh` prints `OK` (run it after the cluster is up).
- `cargo check --workspace --locked` passes.
- No values copied from the samples that were not in your parameters.

## Layout

```
guide/base/
  kdd.md            kdd.yaml schema, commands, conventions   (start here)
  architecture.md   layers, service placement, messaging
  containers.md     Dockerfile, entrypoint, image tagging, dev fast loop
  kubernetes.md     manifests, security, networking, scaling
  database.md       PostgreSQL, db-mgmt job, drop-based upgrades, backups
  valkey.md         queues, streams, pub/sub, cache
  parameters.md     what is a parameter, how values/versions are resolved (generic rules)
  contract.md       single sources of truth for names/versions (read before scaffolding)
samples/web-app/
  kdd.yaml          KDD config (minikube realm)
  k8s/dev/          KDD track: flat, block-named, templated manifests
  k8s/dev_k3s/      k3d/k3s track: numbered, namespaced, hardened manifests
  check.sh          consistency check (versions, images, labels, env vars)
  k3d.sh            build, push, staged apply with kdd (realm dev_k3d)
  .gitignore        kdd .out/ and local overlay
  crates/services/*/Dockerfile   web-server, db-mgmt
```

## Conventions

- Guides are generic; samples are examples. System `rust10x`, namespace `rust10x-web-app` and all versions in samples are placeholders. Real values come from the user or project (`parameters.md`).
- Secrets in samples are `REPLACE_ME` placeholders. Never commit real values.
- `guide/base/kdd.md` is derived from the `kdd` source (CLI, loader, realm, docker, ktemplate, builders). Where behavior is not in the source, it is not asserted.
