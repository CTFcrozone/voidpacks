# KDD Best Practices

Best practices for using `kdd` — the Kubernetes-driven development and deployment CLI utility.

## Overview

`kdd` is a command-line utility to streamline Kubernetes-driven development and deployment. It has **no runtime components** and **no build artifacts** of its own. It structures a cloud application into a multi-service Kubernetes-oriented system and streamlines `docker`, `kubectl`, and cloud CLI into a single command-line set.

## File Structure

Place `kdd.yaml` at the **root of the system**. Each system has exactly one `kdd.yaml` file.

The typical project layout:

- `kdd.yaml` — Root kdd configuration
- `crates/services/` — Backend services (each with `Cargo.toml` and `Dockerfile`)
- `k8s/dev/` and `k8s/prod/` — Kubernetes manifests per environment
- `frontends/web/` — Frontend assets

## Configuration Format

`kdd` supports both **YAML** and **TOML** formats for `kdd.yaml`.

### YAML Format (Legacy / Node.js Projects)

```yaml
system: cstar
image_tag: "{{__version__}}"
block_base_dir: services/

blocks:
  - _common
  - web_server
  - agent
  - redis_queue
  - db
  - name: web
    dir: frontends/web/
  - name: web-server
    dependencies: ['_common', 'web']

realms:
  _base_:
    web_external_ports: 8080

  dev:
    yaml_dir: k8s/dev/
    context: docker-desktop
    confirm_delete: false

  aws:
    yaml_dir: k8s/aws/
    context: arn:aws:eks:us-west-2:843615417314:cluster/cstar-cluster
    profile: jc-root
    registry: 843615417314.dkr.ecr.us-west-2.amazonaws.com/
    default_configurations: ['agent', 'db', 'queue', 'web-server']
    confirm_delete: false

builders:
  - name: npm_install
    when_file: ./package.json
    exec:
      cmd: npm
      cmd_type: global
      args: ["install", "--color"]
  - name: tsc
    when_file: ./tsconfig.json
    exec:
      cmd: node_modules/.bin/tsc
  - name: rollup
    when_file: ./rollup.config.js
    replace: tsc
    exec:
      cmd: node_modules/.bin/rollup
      args: ["-c"]
  - name: pcss
    when_file: ./pcss.config.js
    exec:
      cmd: node_modules/.bin/pcss
```

### TOML Format (Rust Projects — Recommended)

```yaml
vars:
  - from_file: crates/services/web-server/Cargo.toml
    extract: ["version"]
  - from_env: ["USER"]
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

## Core Concepts

### Blocks

Blocks represent **things that get built**. Each block maps to a base block folder.

| Block Type | Directory | Description |
|------------|-----------|-------------|
| Backend Services | `services/_block_name_/` | Server-side logic, APIs, workers |
| Frontend Bundles | `frontends/_block_name_/` | Static assets (JS, CSS, HTML) |

#### Simple Block Declaration

```yaml
blocks:
  - name: db
  - name: queue
  - name: web-server
```

#### Block with Custom Directory

```yaml
blocks:
  - name: web
    dir: frontends/web/
```

#### Block with Build Dependencies

```yaml
blocks:
  - name: web-server
    dependencies: ['_common', 'web']
```

> **Note:** Dependencies affect `dbuild` order only. They do not affect runtime deployment.

### Realms

Realms represent **deployment destinations** (Kubernetes cluster targets).

#### Base Realm (`_base_`)

Properties defined in `_base_` are **shared across all realms**.

```yaml
realms:
  _base_:
    web_external_ports: 8081
```

#### Environment-Specific Realms

```yaml
realms:
  dev:
    yaml_dir: k8s/dev/
    context: minikube
    registry: 192.168.0.104:5000
    confirm_delete: false

  aws:
    yaml_dir: k8s/aws/
    context: arn:aws:eks:us-west-2:843615417314:cluster/cstar-cluster
    profile: jc-root
    registry: 843615417314.dkr.ecr.us-west-2.amazonaws.com/
    default_configurations: ['agent', 'db', 'queue', 'web-server']
    confirm_delete: false
```

| Property | Description |
|----------|-------------|
| `yaml_dir` | Directory containing Kubernetes manifests |
| `context` | `kubectl` context for the cluster |
| `registry` | Docker image registry URL |
| `profile` | Cloud CLI profile (AWS) |
| `default_configurations` | Default blocks to deploy with `kapply` |
| `confirm_delete` | Require confirmation before `kdelete` |

### Builders

Builders define **build steps** for blocks based on file presence.

```yaml
builders:
  - name: npm_install
    when_file: ./package.json
    exec:
      cmd: npm
      cmd_type: global
      args: ["install", "--color"]

  - name: tsc
    when_file: ./tsconfig.json
    exec:
      cmd: node_modules/.bin/tsc

  - name: rollup
    when_file: ./rollup.config.js
    replace: tsc
    exec:
      cmd: node_modules/.bin/rollup
      args: ["-c"]
```

| Property | Description |
|----------|-------------|
| `name` | Builder identifier |
| `when_file` | File that triggers this builder |
| `exec.cmd` | Command to execute |
| `exec.cmd_type` | `global` or `block_dir` |
| `exec.args` | Arguments passed to the command |
| `replace` | Skip this builder if another builder already ran |

## Variable Substitution

### From File

Extract values from files (e.g., `Cargo.toml`, `package.json`).

```yaml
vars:
  - from_file: crates/services/web-server/Cargo.toml
    extract: ["version"]
```

Usage in `kdd.yaml`:
```yaml
image_tag: "{{version}}"
```

### From Environment

```yaml
vars:
  - from_env: ["USER"]
```

### Version Placeholder

Use `{{__version__}}` for Node.js projects (reads from `package.json`):

```yaml
system: cstar
image_tag: "{{__version__}}"
```

## Common Commands

### Realm Management

```bash
# Switch to a realm
kdd realm dev

# List available realms
kdd realm
```

### Docker Operations

```bash
# Build all docker blocks (and their dependencies)
kdd dbuild

# Build specific blocks
kdd dbuild agent,web-server

# Push all docker images to the current realm's registry
kdd dpush

# Push specific images
kdd dpush agent,web-server
```

> Docker images are tagged as: `{registry}/{system}-{service_name}:{image_tag}`
>
> Example: `http://localhost:5000/cba-web-server-DROP-001-SNAPSHOT`

### Kubernetes Operations

```bash
# Apply all default configurations
kdd kapply

# Apply specific configurations
kdd kapply web-server,agent

# Delete resources
kdd kdelete

# Create resources
kdd kcreate

# Execute command in a pod
kdd kexec
```

## Backend Block Build Rules

For backend blocks under `services/_block_name_/`, `kdd` applies these rules in order:

1. **If `package.json` exists** — `npm install` is called
2. **If `tsconfig.json` exists** — TypeScript compilation is called
3. **If `Dockerfile` exists** — `docker build ...` is called

### Docker Image Tagging Convention

```
{registry}/{system}-{service_name}:{image_tag}
```

| Component | Source |
|-----------|--------|
| `registry` | Current realm's `registry` property |
| `system` | `kdd.yaml` `system` property |
| `service_name` | Folder name under `services/` |
| `image_tag` | `image_tag` property (usually `{{__version__}}` or `{{version}}`) |

## Versioning Best Practices

### For Rust Projects (TOML-based)

Use `Cargo.toml` `version` field:

```yaml
vars:
  - from_file: crates/services/web-server/Cargo.toml
    extract: ["version"]
---
image_tag: "{{version}}"
```

### For Node.js Projects (package.json-based)

Use `package.json` `__version__` property (not the standard `version` field):

```json
{
  "name": "web-server",
  "__version__": "0.1.0-DROP-001-SNAPSHOT",
  "version": "0.0.0"
}
```

> **Why `__version__` instead of `version`?** The standard `package.json` `version` field forces SemVer compliance, which is too limiting for application versioning schemes.

### Version Propagation

Ensure the version is hardcoded into the minimum set of files so every part of the system knows its version:

- **Docker labels** — Use `image_tag` in `kdd.yaml`
- **Runtime code** — Inject version at build time
- **Web assets** — Append `?v={{version}}` to cache-bust static files


## Tips

- **Use `_base_` realm** for shared configuration to avoid duplication.
- **Tag images with version** extracted from `Cargo.toml` or `package.json` for traceability.
