# KDD

`kdd` (Kubernetes-Driven Development) is a CLI that structures a cloud application into blocks and realms and wraps `docker` and `kubectl` into one command set. It has no runtime component and produces no artifacts of its own, apart from rendered manifests in `.out/`.

## Concepts

| Concept | Meaning |
|---------|---------|
| **System** | The whole application. One `kdd.yaml` at the system root. |
| **Block** | A thing that gets built: service, database image, queue image, frontend bundle. |
| **Realm** | A deployment destination: kube context, registry, manifest directory. |
| **Builder** | A command run in a block when a trigger file exists (`npm`, `tsc`, ...). |

## kdd.yaml

One or two YAML documents separated by a line starting with `---`. More than two is an error.

```yaml
vars:
  - from_file: crates/services/web-server/Cargo.toml
    extract: ["version"]
  - from_env: ["USER"]
overlays: [kdd.local.yaml]        # optional
---
system: rust10x
image_tag: "{{version}}"
block_base_dir: crates/services/

realms:
  _base_:
    web_external_ports: 8081
  dev:
    yaml_dir: k8s/dev/
    context: minikube
    registry: 192.168.0.104:5000
    confirm_delete: false

blocks:
  - name: db
  - name: queue
  - name: web-server
```

- The `---` line must not appear anywhere in the second document.
- The whole file is rendered as a Handlebars template before parsing (see Templating). Avoid literal `{{` elsewhere.

### First document: vars and overlays

| Key | Behavior |
|-----|----------|
| `vars[].from_file` + `extract` | Reads keys from a **`.json` or `.toml`** file. JSON: top-level string keys. TOML: a top-level key, else the key inside the first table that has it (so `version` is found in `[package]`). `version.workspace = true` is not resolved: use a literal version. Other extensions are skipped with a warning. |
| `vars[].from_env` | List of env var names. Unset variables are skipped silently. |
| `overlays` | List of extra kdd yaml files (relative to the root). Their `realms` are merged in and replace same-name realms; the main `realms._base_` applies to them. Use for machine-specific realms (local registry IP) in a git-ignored file. |

An item cannot have both `from_file` and `from_env`.

> `from_file` extracts literal values only. A Cargo `version.workspace = true` is rendered as `{ workspace = true }`. Use a literal version in the crate you extract from. See `contract.md`.

### Second document: top-level keys

| Key | Purpose |
|-----|---------|
| `system` | **Required.** System name. First part of every image name. |
| `image_tag` | Image tag. Normally `"{{version}}"`. If absent the tag is `default`. |
| `block_base_dir` | Base folder of block folders (`crates/services/`). |
| `blocks` | Block list. |
| `realms` | Named destinations. |
| `builders` | Build steps. Optional. |
| `versions` | Version-rewrite rules for `kdd version`. Optional. |

Every top-level scalar string key (`system`, `image_tag`, `block_base_dir`, ...) also becomes a template variable.

### Blocks

```yaml
blocks:
  - name: db                      # folder: {block_base_dir}/db/
  - name: web
    dir: frontends/web/           # explicit folder (relative to the root)
  - name: web-server
    dependencies: ['_common', 'web']
```

- Folder = `dir` if set, else `{block_base_dir}/{name}`, else `{name}`.
- `dependencies` run the dependency block's **builders** before this block's. They never docker-build the dependency. Already-built blocks are skipped.
- `dbuild` and `dpush` only consider blocks whose folder contains a file named `Dockerfile`.

### Realms

| Property | Meaning |
|----------|---------|
| `context` | **Required.** `kubectl` context. Identifies the realm (see Realm = context). |
| `yaml_dir` | **Required.** Manifest directory, or a list of directories. |
| `registry` | Image registry. Write it **without a trailing slash**: push trims it, but `{{registry}}` in manifests is verbatim. |
| `profile` | AWS CLI profile (default `default`). |
| `project` | GCP project. |
| `default_configurations` | Manifest names applied by `kapply`/`kcreate`/`kdelete` when none are given. |
| `confirm_delete` | **Defaults to `true`.** `kdelete` then requires typing `YES`. Set `false` only on throwaway clusters. |
| other scalar keys | Free-form; become template variables (`web_external_ports`). |

- `_base_` is not a realm. Its keys are merged into every realm; a realm's own value wins.
- Provider is chosen from the context name: `arn:aws...` → AWS, `gke...` → GCP, anything else → common.
- AWS: before a push, missing ECR repositories `{system}-{block}` are created with `aws ecr create-repository --profile`; on push failure kdd runs `aws ecr get-login-password` + `docker login` and retries once.
- Local registry = `registry` unset, or containing `localhost` or `127.0.0.1`.

### Builders

Run in a block folder before `dbuild`, or alone with `kdd build`. `watch_args` replace `args` under `kdd watch`.

```yaml
builders:
  - name: npm_install
    when_file: ./package.json
    run: session
    exec: { cmd: npm, args: ["install", "--color"] }
  - name: tsc
    when_file: ./tsconfig.json
    exec: { cmd: node_modules/.bin/tsc, watch_args: ["--watch"] }
  - name: rollup
    when_file: ./rollup.config.js
    replace: tsc
    exec: { cmd: node_modules/.bin/rollup, args: ["-c"] }
```

| Field | Meaning |
|-------|---------|
| `when_file` | Trigger. `./x` is relative to the block folder; otherwise relative to the root. Without it the builder never runs. |
| `replace` | Skip the named builder when this one triggers. |
| `run` | `block` (default, once per block) or `session` (once per kdd run). |
| `exec.cmd` | Resolved from its shape: `./x` = relative to the block folder; contains `/` = relative to the root; otherwise a global command on PATH. There is no `cmd_type`. |
| `exec.cwd` | `block_dir` (default) or `base_dir`. |
| `exec.args`, `exec.watch_args` | Argument lists. |

Rust blocks need no builder: the `Dockerfile` compiles.

### Versions

`versions` lists rules for `kdd version` (rewrites files in place): `val` (regex whose last capture group is the current value), `replace` (regex), `by` (replacement, supports `${1}`), `in` (files relative to the root). Use it to propagate the version into files such as HTML cache-busting query strings.

## Templating

Manifests in `yaml_dir` and `kdd.yaml` itself are **Handlebars** templates.

Variables, later wins:

1. `dir`, `dir_abs` (root path), `system`
2. `vars` from files and env
3. top-level scalar keys of `kdd.yaml`
4. realm keys (realm values over `_base_`), including `registry`, `context`, `yaml_dir`, custom keys. `confirm_delete` is excluded; lists and maps are not variables.

```yaml
image: "{{registry}}/{{system}}-web-server:{{image_tag}}"
port: {{web_external_ports}}
```

- `{{x}}` HTML-escapes the value (`& < > " '`). Use `{{{x}}}` for raw values such as URLs with `&`.
- Rendering writes to `{first yaml_dir}/.out/{realm}/`. Add `.out/` to `.gitignore`.
- Unknown variables render as empty. Check with `kdd ktemplate`.

## Commands

All accept `-d <root_dir>` (default `./`). Block lists are comma-separated, no spaces.

| Command | Action |
|---------|--------|
| `kdd realm [name]` | No name: list realms (`*` = current). With name: switch the kube context; if the context does not exist, asks `YES` to create it. |
| `kdd build [blocks]` | Run builders only. |
| `kdd watch [blocks]` | Run builders with `watch_args`, concurrently. |
| `kdd dbuild [blocks]` | Builders, then `docker build` for blocks with a `Dockerfile`. No list = all. |
| `kdd dpush [blocks]` | Tag and push images to the current realm's registry. |
| `kdd ktemplate [names]` | Render manifests only. |
| `kdd kapply` / `ka`, `kcreate` / `kc`, `kdelete` / `kd` `[names]` | Render, then `kubectl apply` / `create` / `delete -f` per file. |
| `kdd klog [names]` (`kl`, `klogs`) | Follow logs of matching pods; reconnects on restart. |
| `kdd kexec [names] [-b] -- <cmd>` (`kx`) | `kubectl exec` in **every** matching pod. `-b` wraps the command in `/bin/bash -c`. |
| `kdd kctx list` / `create <name>` / `delete <name>` | Manage kube contexts. |
| `kdd version` | Apply `versions` rules. |

## Build and push semantics

- `docker build --rm -t localhost:5000/{system}-{block}:{image_tag} .` runs with the **block folder as build context**. A `Dockerfile` that needs files outside its block folder (a Rust workspace) cannot be built by `kdd dbuild`.
- `dbuild` pushes automatically only when the current realm has a local registry. Otherwise run `kdd dpush`.
- `dpush` runs `docker tag localhost:5000/{system}-{block}:{tag} {registry}/{system}-{block}:{tag}` then `docker push`. It needs that local tag to exist.

Rust workspace flow (build outside kdd, publish and deploy with kdd):

```sh
VERSION=$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' crates/services/web-server/Cargo.toml | head -n1)
docker build -f crates/services/web-server/Dockerfile \
  -t localhost:5000/rust10x-web-server:$VERSION .
kdd dpush web-server
kdd kapply web-server
```

The block folder must still hold a `Dockerfile` (it is what `dpush` filters on).

## Apply semantics

- No names and no `default_configurations`: **all** `*.yaml` files directly in `yaml_dir`. Not recursive. `.yml` is ignored.
- With names: `{name}.yaml` per name; unknown names are skipped silently.
- Files are applied sorted by file stem, regardless of the order of names. A `_` prefix sorts after digits and before lowercase letters, so `_conf.yaml` precedes `db.yaml`; `00-namespace.yaml` precedes both. This ordering is the only meaning of `_` or numeric prefixes.
- With several `yaml_dir` entries, the first directory containing a stem wins.
- Dependencies between files (Namespace before Secret before Pod) are expressed by file names.
- kdd does not wait for readiness. Stage applies and wait with `kubectl rollout status` / `wait` between them.
- `kubectl` runs in the context's current namespace for `klog`/`kexec`. Set it: `kubectl config set-context --current --namespace=<ns>`.

## Exit codes

`kdd` prints errors but exits `0`. In scripts, never rely on its exit status: gate each stage on `kubectl rollout status` / `kubectl wait` or check the output.

## Realm = context

The current realm is the realm whose `context` equals `kubectl config current-context`. `kdd realm dev` only changes the kube context.

- Two realms must not share a context (the first match wins).
- A current context that matches no realm gives "no current realm" for `dpush`, `kapply`, `klog`, `kexec`.

## Pod labels for klog and kexec

`klog` and `kexec` select pods by the label `run: {system}-{name}` (exact match, e.g. `rust10x-web-server`). Every pod template of a kdd-managed service carries it, next to `app`:

```yaml
template:
  metadata:
    labels:
      app: rust10x-web-server
      run: "{{system}}-web-server"
```

## Conventions

- Names in the examples (`rust10x`, `192.168.0.104`, ports) are placeholders. Use the user's own values.
- One manifest per block, named after the block: `db.yaml`, `queue.yaml`, `web-server.yaml`. Shared resources go in `_`-prefixed files: `_conf.yaml` (ConfigMap, Secret), `_in.yaml` (external Service). Numbered files (`00-`, `01-`) when order matters across many files.
- Manifests are flat in `yaml_dir`.
- Images are always templated: `"{{registry}}/{{system}}-{block}:{{image_tag}}"`. Hard-coded registries and versions are defects.
- Version: Rust from `Cargo.toml` via `vars`; Node from a `__version__` field in `package.json` (the standard `version` field forces SemVer). One version source per system. Never `latest`.
- Realms: `dev`, `staging`, `prod`, plus a cluster suffix when needed (`dev_k3d`). Realms differ in destination values, not structure.
- `confirm_delete` stays `true` everywhere except throwaway local clusters.
- Commit `kdd.yaml`; keep machine-specific realms in a git-ignored overlay; never commit secrets or kubeconfigs. In public repos keep cloud account IDs and ARNs out of realms.
- `kapply`/`kdelete` against non-dev realms is a human action. Agents author, humans apply.

## Dev workflow

```sh
docker run -d -p 5000:5000 --restart=unless-stopped --name registry registry   # once
minikube start --insecure-registry="<host-ip>:5000"                            # once

kdd realm dev
kdd dbuild db,queue       # block folders hold their Dockerfile
kdd dpush
kdd kapply
kdd klog web-server
```

k3d/k3s flow with staged applies: `samples/web-app/k3d.sh`.
