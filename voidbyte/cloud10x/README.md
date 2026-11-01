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

## Reference projects

`samples/minimal/` is the smallest complete project: one hardened Rust service on k3d with kdd. It compiles, runs and passes `check.sh` and `lint.py` as shipped. The scaffold prompts reproduce it with your parameters instead of designing from scratch; that is what keeps the output consistent. `samples/web-app/` shows the fuller system (database, Job, network policies).

## Writing prompts for this pack

Ready-made templates are in `prompts/` (scaffold, add a service, add a realm, audit, PostgreSQL upgrade runbook). Copy one, edit its parameters, run it. To write your own, follow this section.

The pack holds the rules. The prompt holds the facts of one project and the scope of one task. A good prompt is short, parametric and checkable.

**Structure**

1. **Header:** the pro@coder YAML block with `knowledge_globs` for this pack, `context_globs`, `write_mode: true`, a `model`.
2. **Parameters** (names in `scaffolding.md`): every name and version the project needs, in one block (system, namespace, cluster, registry, realm, toolchain, base OS, database major). Values you leave out are resolved by `guide/base/parameters.md`.
3. **Scope:** exactly what to build and a "do not add" list. Unbounded prompts produce extra services.
4. **Contract:** the names that must agree across files (env vars, block names, ports). Point at `contract.md` instead of repeating it.
5. **Nothing else.** Invariant rules, self-checks, value mappings and answer formats belong in the pack (`guide/base/scaffolding.md`), not in every prompt.

**Rules**

- **Keep invariants in the pack.** If every user would have to write the same line, it is a pack rule. A prompt holds parameters, scope and facts about this application.
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
REG_PORT      = <port>              # registry host k3d-<CLUSTER>-reg.localhost
REALM         = <realm>
INGRESS_HOST  = <host>
RUST          = latest              # latest | <exact version>
BASE_OS       = alpine
PG_MAJOR      = <number>            # only for database scaffolds; pinned in manifests
```

# TASK

<One sentence: what to build, which reference project to start from, and "following `scaffolding.md`".>

Scope is exactly these workloads:

1. `<block>` - <what it is>
2. `<block>` - <what it is>

Do NOT add: <extra services, tools or features that must not appear>.

## Application facts

- <Routes, ports and env var names of each service.>
- <Secrets and their consumers.>
- <Network flows that must be allowed (both sides, pod ports).>
- <Anything else specific to this application.>

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
  parameters.md     what is a parameter, how values/versions are resolved (generic rules)
  contract.md       single sources of truth for names/versions, known failure modes
  scaffolding.md    method, parameters, value mapping, rules, self-check (shared by all scaffold prompts)
  architecture.md   layers, service placement, messaging
  containers.md     Dockerfile, entrypoint, image tagging, dev fast loop
  kubernetes.md     manifests, security, networking, scaling
  lint.md           hardening rules enforced by lint.py, waivers
  database.md       PostgreSQL, db-mgmt job, drop-based upgrades, backups
  valkey.md         queues, streams, pub/sub, cache
  environments.md   dev/staging/prod realms, promotion, digests, rollback
  ci.md             CI gates and rules
samples/web-app/
  kdd.yaml          KDD config (minikube realm + k3d realm)
  kdd.overlay.example.yaml   staging and prod realms (placeholders)
  k8s/dev/          KDD track: flat, block-named, templated manifests
  k8s/dev_k3s/      k3d/k3s track: numbered, namespaced, hardened manifests
  check.sh          consistency check (versions, images, labels, env vars, registry/cluster) + lint
  lint.py           hardening linter for rendered manifests (needs PyYAML)
  k3d.sh            build, push, staged apply with kdd (realm dev_k3d)
  .gitignore        kdd .out/ and local overlay
  crates/services/*/Dockerfile   web-server, db-mgmt
samples/minimal/    reference project (compiled and run in testing); prompts copy it with your parameters
samples/ci/
  github-actions.yml   reference pipeline
prompts/            pro@coder prompt templates (not loaded as knowledge)
  scaffold-minimal.md  scaffold-web-db.md  add-service.md  add-realm.md  audit.md  upgrade-postgres.md
```

## Conventions

- Reference projects (`samples/minimal/`) are followed file for file; names in them are examples.
- Guides are generic; samples are examples. System `rust10x`, namespace `rust10x-web-app` and all versions in samples are placeholders. Real values come from the user or project (`parameters.md`).
- Secrets in samples are `REPLACE_ME` placeholders. Never commit real values.
- `guide/base/kdd.md` is derived from the `kdd` source (CLI, loader, realm, docker, ktemplate, builders). Where behavior is not in the source, it is not asserted.

## License

Licensed under either of

- Apache License, Version 2.0 ([../../LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([../../LICENSE-MIT](LICENSE-MIT))

at your option. Unless you state otherwise, any contribution you intentionally submit for inclusion in this work, as defined in the Apache-2.0 license, is dual licensed as above, without any additional terms or conditions.
