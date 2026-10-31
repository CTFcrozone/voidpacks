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

## Layout

```
guide/base/
  kdd.md            kdd.yaml schema, commands, conventions   (start here)
  architecture.md   layers, service placement, messaging
  containers.md     Dockerfile, entrypoint, image tagging, dev fast loop
  kubernetes.md     manifests, security, networking, scaling
  database.md       PostgreSQL, db-mgmt job, drop-based upgrades, backups
  valkey.md         queues, streams, pub/sub, cache
samples/web-app/
  kdd.yaml          KDD config (minikube realm)
  k8s/dev/          KDD track: flat, block-named, templated manifests
  k8s/dev_k3s/      k3d/k3s track: numbered, namespaced, hardened manifests
  k3d.sh            build, push, staged apply with kdd (realm dev_k3d)
  .gitignore        kdd .out/ and local overlay
  crates/services/*/Dockerfile   web-server, db-mgmt
```

## Conventions

- System name `rust10x`, namespace `rust10x-web-app` in all samples. Replace for real systems.
- Secrets in samples are `REPLACE_ME` placeholders. Never commit real values.
- `guide/base/kdd.md` is derived from the `kdd` source (CLI, loader, realm, docker, ktemplate, builders). Where behavior is not in the source, it is not asserted.
